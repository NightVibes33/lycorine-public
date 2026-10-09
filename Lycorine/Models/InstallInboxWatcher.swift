import Combine
import Foundation

enum InstallAction: String {
    case install
    case uninstall
}

struct InstallRequest {
    let id: String
    let action: InstallAction
    let inbox: URL

    func file(_ suffix: String) -> URL {
        inbox.appendingPathComponent("\(id).\(suffix)")
    }
}

enum InstallInbox {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lycorined", isDirectory: true)
    }

    static func queue(_ action: InstallAction) throws -> InstallRequest {
        let fm = FileManager.default
        let inbox = url
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        let request = InstallRequest(id: UUID().uuidString, action: action, inbox: inbox)

        do {
            if action == .install {
                guard let source = Bundle.main.url(forResource: "bootstrap.tar", withExtension: "zst") else {
                    throw cryptex_err(msg: "missing bootstrap archive")
                }
                
                try fm.copyItem(at: source, to: request.file("bootstrap.tar.zst"))
            }
            let contents = Data("\(action.rawValue)\n".utf8)
            try contents.write(to: request.file("request"), options: .atomic)
        } catch {
            try? fm.removeItem(at: request.file("bootstrap.tar.zst"))
            throw error
        }
        return request
    }

    static func cleanFinished(_ request: InstallRequest) {
        let fm = FileManager.default
        for suffix in ["processing", "result.plist", "bootstrap.tar.zst"] {
            try? fm.removeItem(at: request.file(suffix))
        }
    }

    static func clearCompleted() throws -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let names = try fm.contentsOfDirectory(atPath: url.path)
        var removed = 0
        for name in names where name.hasSuffix(".result.plist") {
            let id = String(name.dropLast(".result.plist".count))
            guard UUID(uuidString: id) != nil else { continue }
            for suffix in ["result.plist", "processing", "bootstrap.tar.zst"] {
                let path = url.appendingPathComponent("\(id).\(suffix)")
                if fm.fileExists(atPath: path.path) {
                    try fm.removeItem(at: path)
                    removed += 1
                }
            }
        }
        return removed
    }
}

final class InstallStatusModel: ObservableObject {
    @Published private(set) var status = "ready"
    @Published private(set) var isWorking = false

    private var request: InstallRequest?
    private var timer: Timer?
    private var action: InstallAction = .install
    private var operationFinished = false
    private var operationFailed = false
    private var resultStatus: Int?
    private var logByteCount = 0
    private var acknowledged = false

    func begin(action: InstallAction) {
        timer?.invalidate()
        timer = nil
        request = nil
        self.action = action
        operationFinished = false
        operationFailed = false
        resultStatus = nil
        logByteCount = 0
        acknowledged = false
        status = action == .install ? "preparing install…" : "preparing uninstall…"
        isWorking = true
    }

    func watch(_ request: InstallRequest) {
        self.request = request
        status = "waiting for lycorined…"
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        refresh()
    }

    func operationComplete() {
        operationFinished = true
        finishIfReady()
    }

    func failed(_ error: Error) {
        print("\(action.rawValue) failed: \(error)")
        operationFailed = true
        operationFinished = true
        if resultStatus != nil {
            finishIfReady()
            return
        }
        if let request, resultStatus == nil {
            let pending = request.file("request")
            if FileManager.default.fileExists(atPath: pending.path),
               (try? FileManager.default.removeItem(at: pending)) != nil {
                InstallInbox.cleanFinished(request)
                stop("\(action.rawValue) failed")
                return
            }
            if FileManager.default.fileExists(atPath: request.file("processing").path) {
                status = "\(action.rawValue) failed; waiting for lycorined…"
                return
            }
        }
        stop("\(action.rawValue) failed")
    }

    private func refresh() {
        guard let request else { return }
        let fm = FileManager.default
        let processing = request.file("processing")
        if let data = try? Data(contentsOf: processing) {
            if !acknowledged {
                acknowledged = true
                if !operationFailed {
                    status = action == .install ? "lycorined installing bootstrap…" : "lycorined uninstalling…"
                }
                print("lycorined accepted \(action.rawValue) request")
            }
            let header = Data("\(action.rawValue)\n".utf8)
            if data.starts(with: header) {
                if data.count < logByteCount { logByteCount = header.count }
                let offset = min(max(logByteCount, header.count), data.count)
                if let update = String(data: data.subdata(in: offset..<data.count), encoding: .utf8) {
                    logByteCount = data.count
                    let trimmed = update.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { print(trimmed) }
                }
            }
        }

        let result = request.file("result.plist")
        guard fm.fileExists(atPath: result.path), resultStatus == nil else { return }
        do {
            let data = try Data(contentsOf: result)
            let value = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let fields = value as? [String: Any],
                  let returnedAction = fields["action"] as? String,
                  returnedAction == action.rawValue,
                  let code = fields["status"] as? Int else {
                stop("\(action.rawValue) status unavailable")
                return
            }
            resultStatus = code
            print("lycorined \(action.rawValue) result: \(code)")
            if !operationFailed {
                status = code == 0 ? "bootstrap \(action == .install ? "installed" : "uninstalled")" : "\(action.rawValue) failed (\(code))"
            }
            finishIfReady()
        } catch {
            stop("\(action.rawValue) status unavailable")
        }
    }

    private func finishIfReady() {
        guard operationFinished, let code = resultStatus else { return }
        if let request { InstallInbox.cleanFinished(request) }
        let message: String
        if operationFailed || code != 0 {
            message = "\(action.rawValue) failed\(code == 0 ? "" : " (\(code))")"
        } else {
            message = action == .install ? "installed" : "uninstalled"
        }
        stop(message)
    }

    private func stop(_ message: String) {
        timer?.invalidate()
        timer = nil
        request = nil
        status = message
        isWorking = false
    }

    deinit { timer?.invalidate() }
}
