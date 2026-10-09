import Foundation
import Combine

/// A discovered service identifies a Bonjour advertisement, not an authorized iPhone.
struct RSDDiscoveredService: Identifiable {
    let name: String
    let host: String
    let port: Int
    var id: String { "\(name)|\(host)|\(port)" }
}

final class RSDDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published private(set) var services: [RSDDiscoveredService] = []
    @Published private(set) var isSearching = false
    @Published private(set) var status = "No remote-pairing scan performed"

    private var browser: NetServiceBrowser?
    private var resolving: [NetService] = []

    func start() {
        stop()
        services.removeAll()
        status = "Looking for advertised _remotepairing._tcp services…"
        isSearching = true
        let candidate = NetServiceBrowser()
        candidate.delegate = self
        browser = candidate
        candidate.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
    }

    func stop() {
        browser?.stop()
        browser?.delegate = nil
        browser = nil
        resolving.forEach {
            $0.stop()
            $0.delegate = nil
        }
        resolving.removeAll()
        isSearching = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        resolving.append(service)
        service.delegate = self
        service.resolve(withTimeout: 8.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let port = sender.port
        let name = sender.name
        let host = sender.hostName ?? "host unknown"
        DispatchQueue.main.async {
            guard self.isSearching, (1...65535).contains(port) else { return }
            let found = RSDDiscoveredService(name: name, host: host, port: port)
            if !self.services.contains(where: { $0.id == found.id }) {
                self.services.append(found)
                self.services.sort { $0.name < $1.name }
            }
            self.status = "\(self.services.count) remote pairing service(s). Select the one associated with this device."
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        DispatchQueue.main.async {
            if self.services.isEmpty {
                self.status = "The discovered service could not be resolved. Enter the port manually."
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        DispatchQueue.main.async {
            self.isSearching = false
            self.status = "Bonjour discovery unavailable. Enter the port manually."
        }
    }
}
