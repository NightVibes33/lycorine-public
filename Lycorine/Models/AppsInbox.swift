import Combine
import Foundation

enum AppCloneState: String, Decodable {
    case available
    case enabled
    case disabled

    var label: String {
        switch self {
        case .available: "Not configured"
        case .enabled: "Tweaks enabled"
        case .disabled: "Tweaks disabled"
        }
    }
}

struct InstalledApp: Decodable, Identifiable {
    let bundleID: String
    let name: String
    let type: String
    let version: String
    let executable: String
    let cloneState: AppCloneState

    var id: String { bundleID }
}

private enum AppsAction: String {
    case list = "list_apps"
    case enable = "tweak_app"
    case disable = "disable_app"
}

private struct AppsResult: Decodable {
    let action: String
    let status: Int
    let apps: [InstalledApp]?
}

@MainActor
private enum AppsInbox {
    static func perform(_ action: AppsAction, target: String? = nil, progress: (String) -> Void) async throws -> AppsResult {
        let fm = FileManager.default
        let inbox = InstallInbox.url
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let id = UUID().uuidString
        func file(_ suffix: String) -> URL { inbox.appendingPathComponent("\(id).\(suffix)") }

        if let target {
            let data = try PropertyListSerialization.data(fromPropertyList: ["target": target], format: .binary, options: 0)
            try data.write(to: file("target.plist"), options: .atomic)
        }
        try Data("\(action.rawValue)\n".utf8)
            .write(to: file("request"), options: .atomic)

        let deadline = Date().addingTimeInterval(action == .list ? 20 : 180)
        var lastProgress = ""
        while Date() < deadline {
            if let data = try? Data(contentsOf: file("processing")),
               let text = String(data: data, encoding: .utf8),
               let line = text.split(separator: "\n").dropFirst().last.map(String.init),
               line != lastProgress {
                lastProgress = line
                progress(line)
            }

            if let data = try? Data(contentsOf: file("result.plist")) {
                let result = try PropertyListDecoder().decode(AppsResult.self, from: data)
                for suffix in ["processing", "result.plist", "target.plist"] {
                    try? fm.removeItem(at: file(suffix))
                }
                guard result.status == 0 else {
                    throw NSError(domain: "Lycorine.Apps", code: result.status, userInfo: [NSLocalizedDescriptionKey: lastProgress.isEmpty ? "roothelper failed (\(result.status))" : lastProgress])
                }
                return result
            }
            try await Task.sleep(for: .milliseconds(400))
        }
        
        throw NSError(domain: "Lycorine.Apps", code: 1, userInfo: [NSLocalizedDescriptionKey: "Roothelper did not respond before request timeout. The helper may not be installed/running; this is independent of RemotePairing and TSS."])
    }
}

@MainActor
final class AppsModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false
    @Published private(set) var busyAppID: String?
    @Published private(set) var status = ""
    private var hasLoaded = false

    func loadIfNeeded() {
        if !hasLoaded { refresh() }
    }

    func refresh() {
        guard !isLoading, busyAppID == nil else { return }
        isLoading = true
        status = "Loading apps…"
        Task {
            do {
                let result = try await AppsInbox.perform(.list) { status = $0 }
                apps = result.apps ?? []
                hasLoaded = true
                status = "\(apps.count) apps"
            } catch {
                status = error.localizedDescription
                print("(applist) \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    func toggle(_ app: InstalledApp, ) {
        guard busyAppID == nil, !isLoading else { return }
        let enable = app.cloneState != .enabled
        busyAppID = app.id
        status = "\(enable ? "Enabling" : "Disabling") tweaks for \(app.name)…"
        Task {
            do {
                _ = try await AppsInbox.perform(enable ? .enable : .disable,
                                                target: app.bundleID) { status = $0 }
                print("(applist) \(enable ? "enabled" : "disabled") tweaks for \(app.name)")
                let result = try await AppsInbox.perform(.list) { status = $0 }
                apps = result.apps ?? []
                status = "\(app.name): tweaks \(enable ? "enabled" : "disabled")"
            } catch {
                status = error.localizedDescription
                print("(applist) \(app.name): \(error.localizedDescription)")
            }
            busyAppID = nil
        }
    }
}
