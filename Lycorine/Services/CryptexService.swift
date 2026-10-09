import Foundation
import CryptoKit
import Darwin
import IDevice
import IDeviceSwift

// This is an independent, public-API reconstruction. It DOES NOT implement
// the missing TSS authorization flaw or create Apple-signed research tickets.
struct cryptex_err: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

struct LycorineInstalledCryptex {
    let identifier: String
    let version: String
}

struct LycorineSignedCryptex {
    let id: String
    let version: String
    let image: Data
    let trustcache: Data
    let info: Data
    let volumehash: Data
    let ticket: Data
    let properties: [String: Any]
}

// Use a prefixed symbol declaration so the libplist ABI is explicit.
// plist_from_xml returns 0 on success and allocates an owned plist_t.
@_silgen_name("plist_from_xml")
private func lycorine_plist_from_xml(
    _ input: UnsafePointer<CChar>?, _ length: UInt32,
    _ output: UnsafeMutablePointer<OpaquePointer?>
) -> Int32

@_silgen_name("plist_free")
private func lycorine_plist_free(_ ptr: OpaquePointer?)

final class cryptex_service {
    static let shared = cryptex_service()
    private init() {}

    static func check(
        _ error: UnsafeMutablePointer<IdeviceFfiError>?,
        _ operation: String
    ) throws {
        guard let error else { return }
        let message = error.pointee.message.map(String.init(cString:)) ?? "unknown iDevice error"
        idevice_error_free(error)
        throw cryptex_err(msg: "\(operation): \(message)")
    }

    // A valid pairing record and an existing RSD/LocalDevVPN tunnel are
    // prerequisites. One cryptexd RPC consumes its connection.
    func withCryptexd<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        let pairingPath = HeartbeatManager.pairingFile()
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            throw cryptex_err(msg: "No pairing record. Import a valid RSD pairing file in Settings.")
        }
        // The pairing file and reachable RSD endpoint are separate prerequisites.
        // A file existing on disk is NOT proof the device accepted its credentials.

        var pairing: OpaquePointer?
        try Self.check(rp_pairing_file_read(pairingPath, &pairing), "read RSD pairing")
        guard let pairing else { throw cryptex_err(msg: "RSD pairing record is empty") }
        defer { rp_pairing_file_free(pairing) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        let tunnelHost = LycorineRSD.host
        let tunnelPort = LycorineRSD.port
        address.sin_port = CFSwapInt16HostToBig(tunnelPort)
        guard inet_pton(AF_INET, tunnelHost, &address.sin_addr) == 1 else {
            throw cryptex_err(msg: "Invalid RSD IPv4 address in Settings (\(tunnelHost)).")
        }

        var adapter: OpaquePointer?
        var handshake: OpaquePointer?
        let tunnelError = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: idevice_sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0, socklen_t(MemoryLayout<sockaddr_in>.size),
                    "Lycorine", pairing, nil, nil, &adapter, &handshake
                )
            }
        }
        if let tunnelError {
            let message = tunnelError.pointee.message.map { String(cString: $0) } ?? "unknown connection error"
            idevice_error_free(tunnelError)
            let advice: String
            if message.localizedCaseInsensitiveContains("connectionreset")
                || message.localizedCaseInsensitiveContains("connection reset") {
                advice = "The peer reset the RemotePairing handshake. This can happen WHILE LocalDevVPN is connected. Discover this iPhone's current RemotePairing port, then check whether the imported RSD record was paired on the same network path. A structurally valid file is not proof of pairing authorization."
            } else {
                advice = "Confirm the configured peer IP/port and the imported remote-pairing record. VPN connectivity and remote-pairing trust are separate checks."
            }
            throw cryptex_err(msg: "RemotePairing at \(tunnelHost):\(tunnelPort) failed: \(message). \(advice) Apple TSS was not contacted.")
        }
        guard let adapter, let handshake else {
            throw cryptex_err(msg: "RSD did not return an adapter and handshake")
        }
        defer {
            rsd_handshake_free(handshake)
            adapter_free(adapter)
        }

        var client: OpaquePointer?
        try Self.check(cryptexd_connect_rsd(adapter, handshake, &client), "connect cryptexd")
        guard let client else { throw cryptex_err(msg: "cryptexd connection missing") }
        // cryptexd RPCs consume the handle, including on error.
        return try operation(client)
    }

    func list_installed() throws -> [LycorineInstalledCryptex] {
        try withCryptexd { client in
            var array: UnsafeMutablePointer<InstalledCryptexC>?
            var count: Int = 0
            try Self.check(
                cryptexd_copy_installed(client, &array, &count),
                "list installed cryptexes"
            )
            defer { cryptexd_free_installed(array, UInt(count)) }
            guard let array, count > 0 else { return [] }
            return (0..<count).map { index in
                let entry = array[index]
                return LycorineInstalledCryptex(
                    identifier: entry.identifier.map { String(cString: $0) } ?? "",
                    version: entry.version.map { String(cString: $0) } ?? ""
                )
            }
        }
    }

    // Only accept an ALREADY signed Cryptex bundle; do not fabricate a ticket.
    // The original Lycorine bundle is not provided in the public repository.
    static func load_sealed_img() throws -> LycorineSignedCryptex {
        let name = "com.saccharine.lycorine.recovery.cxbd.signed"
        let bundled = Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true)
        guard let root = LycorineTSS.savedBundle() ?? bundled,
              FileManager.default.fileExists(atPath: root.path) else {
            throw cryptex_err(msg: "No signed Lycorine cryptex is available. Import a research cryptex and request fresh TSS authorization first; Apple's patched authorization policy may refuse it. This is separate from RSD connectivity.")
        }

        let restore = root.appendingPathComponent("Restore", isDirectory: true)
        let manifestURL = restore.appendingPathComponent("BuildManifest.plist")
        let raw = try Data(contentsOf: manifestURL)
        guard let manifest = try PropertyListSerialization.propertyList(
            from: raw, format: nil
        ) as? [String: Any],
              let identities = manifest["BuildIdentities"] as? [[String: Any]],
              let identity = identities.first(where: {
                  ($0["Info"] as? [String: Any])?["Variant"] as? String == "research"
              }),
              let entries = identity["Manifest"] as? [String: Any] else {
            throw cryptex_err(msg: "Signed Cryptex has no research BuildIdentity")
        }

        func asset(_ key: String) throws -> Data {
            guard let entry = entries[key] as? [String: Any],
                  let metadata = entry["Info"] as? [String: Any],
                  let relative = metadata["Path"] as? String,
                  let digest = entry["Digest"] as? Data else {
                throw cryptex_err(msg: "Missing Cryptex manifest entry: \(key)")
            }
            let base = restore.resolvingSymlinksInPath().standardizedFileURL
            let url = restore.appendingPathComponent(relative)
                .resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(base.path + "/") else {
                throw cryptex_err(msg: "Unsafe Cryptex asset path: \(key)")
            }
            let bytes = try Data(contentsOf: url)
            guard !bytes.isEmpty, Data(SHA384.hash(data: bytes)) == digest else {
                throw cryptex_err(msg: "Cryptex SHA-384 integrity mismatch: \(key)")
            }
            return bytes
        }

        let image = try asset("Cryptex1,GenericDmg")
        let trustcache = try asset("Cryptex1,GenericTrustCache")
        let info = try asset("Cryptex1,CryptexInfoPlist")
        let volumehash = try asset("Cryptex1,GenericVolume")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let tickets = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.lastPathComponent.lowercased().hasSuffix("im4m") }
        guard tickets.count == 1 else {
            throw cryptex_err(msg: "Expected one personalized Image4 ticket, found \(tickets.count)")
        }
        let ticket = try Data(contentsOf: tickets[0])
        guard !ticket.isEmpty else { throw cryptex_err(msg: "Image4 ticket is empty") }

        // Match idevice's documented Cryptex1 properties. NSNumber survives
        // XML plist serialization as integer/boolean and preserves uint64.
        func required(_ key: String) throws -> Any {
            guard let value = identity[key] else {
                throw cryptex_err(msg: "BuildIdentity missing \(key)")
            }
            return value
        }
        let properties: [String: Any] = [
            "Cryptex1,UseProductClass": try required("Cryptex1,UseProductClass"),
            "MountedCryptex": false,
            "Cryptex1,SubType": try required("Cryptex1,SubType"),
            "Cryptex1,NonceDomain": try required("Cryptex1,NonceDomain"),
            "Cryptex1,Version": try required("Cryptex1,Version"),
            "Cryptex1,PreauthVersion": try required("Cryptex1,PreauthorizationVersion")
        ]
        let infoDict = (try? PropertyListSerialization.propertyList(from: info, format: nil))
            as? [String: Any] ?? [:]
        return LycorineSignedCryptex(
            id: infoDict["CFBundleIdentifier"] as? String ?? "com.saccharine.lycorine.recovery",
            version: infoDict["CFBundleVersion"] as? String ?? "1.0.0.0",
            image: image, trustcache: trustcache, info: info, volumehash: volumehash,
            ticket: ticket, properties: properties
        )
    }

    // This performs an actual cryptexd RPC for a pre-authorized signed image.
    // It cannot create or authorize a ticket or bypass Apple's TSS policy.
    func install_sealed_img(_ bundle: LycorineSignedCryptex) throws -> LycorineInstalledCryptex {
        let xml = try PropertyListSerialization.data(
            fromPropertyList: bundle.properties, format: .xml, options: 0
        )
        guard xml.count <= Int(UInt32.max) else {
            throw cryptex_err(msg: "Invalid oversized Cryptex properties")
        }
        var properties: OpaquePointer?
        let status: Int32 = xml.withUnsafeBytes { bytes in
            lycorine_plist_from_xml(
                bytes.bindMemory(to: CChar.self).baseAddress,
                UInt32(xml.count), &properties
            )
        }
        guard status == 0, let properties else {
            throw cryptex_err(msg: "Unable to convert Cryptex properties into an XPC plist")
        }
        defer { lycorine_plist_free(properties) }

        try withCryptexd { client in
            try bundle.image.withUnsafeBytes { image in
                try bundle.trustcache.withUnsafeBytes { trustcache in
                    try bundle.ticket.withUnsafeBytes { ticket in
                        try bundle.info.withUnsafeBytes { info in
                            try bundle.volumehash.withUnsafeBytes { volume in
                                var request = CryptexInstallRequestC()
                                request.image = image.bindMemory(to: UInt8.self).baseAddress
                                request.image_len = UInt(bundle.image.count)
                                request.trustcache = trustcache.bindMemory(to: UInt8.self).baseAddress
                                request.trustcache_len = UInt(bundle.trustcache.count)
                                request.im4m = ticket.bindMemory(to: UInt8.self).baseAddress
                                request.im4m_len = UInt(bundle.ticket.count)
                                request.info = info.bindMemory(to: UInt8.self).baseAddress
                                request.info_len = UInt(bundle.info.count)
                                request.volumehash = volume.bindMemory(to: UInt8.self).baseAddress
                                request.volumehash_len = UInt(bundle.volumehash.count)
                                request.cryptex1_properties = UnsafeMutableRawPointer(properties)
                                request.image_type_index = 10
                                request.persistence = 2
                                request.nonce_persistence = 1
                                request.auth = 0
                                try Self.check(cryptexd_install(client, &request), "install signed cryptex")
                            }
                        }
                    }
                }
            }
        }
        // Installation succeeded only if cryptexd accepted the signed image.
        let installed = try list_installed()
        guard let match = installed.first(where: { $0.identifier == bundle.id }) else {
            throw cryptex_err(msg: "cryptexd returned success but did not report the expected installed identifier")
        }
        return match
    }
}
