import Foundation
import CryptoKit
import IDevice

// Public Cryptex1 client protocol. This does not recreate Lycorine's patched TSS exploit.
struct LycorineTSSResult {
    let signedBundle: URL
    let diagnostics: URL
}
enum LycorineTSSError: LocalizedError {
    case stopped(String)
    var errorDescription: String? {
        if case .stopped(let value) = self { return value }
        return "TSS request failed"
    }
}
@_silgen_name("plist_to_xml")
private func lyc_to_xml(_ node: UnsafeMutableRawPointer?,
    _ out: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ size: UnsafeMutablePointer<UInt32>) -> Int32
@_silgen_name("plist_mem_free")
private func lyc_mem_free(_ ptr: UnsafeMutableRawPointer?)
@_silgen_name("plist_free")
private func lyc_node_free(_ ptr: OpaquePointer?)

final class LycorineTSS {
    static let shared = LycorineTSS()
    private init() {}
    private static let signedName = "com.saccharine.lycorine.recovery.cxbd.signed"

    private static func numeric(_ value: Any?, _ name: String) throws -> UInt64 {
        if let n = value as? NSNumber { return n.uint64Value }
        if let s = value as? String {
            let hex = s.hasPrefix("0x")
            if let n = UInt64(hex ? String(s.dropFirst(2)) : s, radix: hex ? 16 : 10) { return n }
        }
        throw LycorineTSSError.stopped("Invalid or missing \(name)")
    }
    private static func baseFolder() throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lycorine/Cryptex", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    static func savedBundle() -> URL? {
        guard let base = try? baseFolder() else { return nil }
        let path = base.appendingPathComponent(signedName, isDirectory: true)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }
    static func failureReport(_ reason: String) -> URL? {
        guard let base = try? baseFolder() else { return nil }
        let destination = base.appendingPathComponent("tss-failure-\(UUID().uuidString).txt")
        let sanitized = String(reason.prefix(500)).replacingOccurrences(
            of: "[0-9A-Fa-f]{16,}", with: "[redacted]", options: .regularExpression
        )
        let lines = [
            "Cryptex1 request did NOT produce an authorized ticket.",
            "Failure: \(sanitized)",
            "Nothing installed or code-signed.",
            "Raw TSS response, nonce, ECID and ticket bytes intentionally omitted."
        ]
        do {
            try lines.joined(separator: "\n").write(
                to: destination, atomically: true, encoding: .utf8)
            return destination
        } catch { return nil }
    }
    private static func loadManifest(_ folder: URL) throws -> [String: Any] {
        let base = folder.appendingPathComponent("Restore", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let data = try Data(contentsOf: base.appendingPathComponent("BuildManifest.plist"))
        guard let manifest = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
              let identities = manifest["BuildIdentities"] as? [[String: Any]],
              let identity = identities.first(where: {
                  let value = (($0["Info"] as? [String: Any])?["Variant"] as? String) ?? ""
                  return value == "research" || value.hasSuffix("Developer Disk Image Cryptex")
              }), let components = identity["Manifest"] as? [String: Any] else {
            throw LycorineTSSError.stopped("No Cryptex1 research BuildIdentity")
        }
        for key in ["Cryptex1,GenericDmg", "Cryptex1,GenericTrustCache",
                    "Cryptex1,CryptexInfoPlist", "Cryptex1,GenericVolume"] {
            guard let item = components[key] as? [String: Any],
                  let digest = item["Digest"] as? Data, digest.count == 48,
                  let info = item["Info"] as? [String: Any],
                  let relative = info["Path"] as? String else {
                throw LycorineTSSError.stopped("Manifest is missing \(key)")
            }
            let url = base.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
            guard url.path.hasPrefix(base.path + "/") else {
                throw LycorineTSSError.stopped("Unsafe Cryptex asset path")
            }
            let asset = try Data(contentsOf: url)
            guard !asset.isEmpty && Data(SHA384.hash(data: asset)) == digest else {
                throw LycorineTSSError.stopped("SHA-384 mismatch for \(key)")
            }
        }
        let tc = components["Cryptex1,GenericTrustCache"] as? [String: Any]
        let meta = tc?["Info"] as? [String: Any]
        guard meta?["Personalize"] as? Bool == true else {
            throw LycorineTSSError.stopped("Research trust cache isn't marked for personalization")
        }
        return identity
    }
    private func readDevice(_ domain: UInt64) throws -> ([String: Any], Data) {
        let instance: [String: Any] = try cryptex_service.shared.withCryptexd { client in
            var object: UnsafeMutableRawPointer?
            try cryptex_service.check(
                cryptexd_read_personalization_identifiers(client, &object), "read chip instance")
            guard let object else { throw LycorineTSSError.stopped("No AppleImage4 identifiers") }
            defer { lyc_node_free(OpaquePointer(object)) }
            var buffer: UnsafeMutablePointer<CChar>?
            var length: UInt32 = 0
            guard lyc_to_xml(object, &buffer, &length) == 0, let buffer else {
                throw LycorineTSSError.stopped("Cannot decode chip instance")
            }
            defer { lyc_mem_free(UnsafeMutableRawPointer(buffer)) }
            let value = try PropertyListSerialization.propertyList(
                from: Data(bytes: buffer, count: Int(length)), format: nil)
            guard let dictionary = value as? [String: Any] else {
                throw LycorineTSSError.stopped("Invalid chip-instance format")
            }
            return dictionary
        }
        let nonce: Data = try cryptex_service.shared.withCryptexd { client in
            var pointer: UnsafeMutablePointer<UInt8>?
            var length: UInt = 0
            try cryptex_service.check(
                cryptexd_cryptex_nonce(client, domain, &pointer, &length), "read Cryptex nonce")
            guard let pointer, length > 0 && length < 4096 else {
                throw LycorineTSSError.stopped("Empty/invalid Cryptex nonce")
            }
            defer { idevice_data_free(pointer, length) }
            return Data(bytes: pointer, count: Int(length))
        }
        return (instance, nonce)
    }
    private static func requestXML(_ id: String, _ identity: [String: Any],
                                   _ chip: [String: Any], _ nonce: Data) throws -> Data {
        guard let components = identity["Manifest"] as? [String: Any],
              let production = chip["img4_chip_cpro"] as? NSNumber else {
            throw LycorineTSSError.stopped("Missing manifest or production mode")
        }
        let chipID = try numeric(chip["img4_chip_chip"], "chip")
        let ecid = try numeric(chip["img4_chip_ecid"], "ECID")
        var udid = Data()
        withUnsafeBytes(of: chipID.bigEndian) { udid.append(contentsOf: $0) }
        withUnsafeBytes(of: ecid.bigEndian) { udid.append(contentsOf: $0) }
        var request: [String: Any] = [
            "@HostPlatformInfo": "mac", "@VersionInfo": "libauthinstall-1033.0.2",
            "@UUID": id, "@Cryptex1,Ticket": true,
            "Cryptex1,ChipID": try numeric(identity["Cryptex1,ChipID"], "ChipID"),
            "Cryptex1,ProductClass": try numeric(identity["Cryptex1,ProductClass"], "ProductClass"),
            "Cryptex1,ProductionMode": production.boolValue,
            "Cryptex1,UDID": udid, "Cryptex1,Nonce": nonce,
            "Cryptex1,UniqueTagList": Data()
        ]
        for key in ["Cryptex1,Type", "Cryptex1,SubType", "Cryptex1,UseProductClass",
                    "Cryptex1,NonceDomain", "Cryptex1,Version", "Cryptex1,PreauthorizationVersion"] {
            guard let v = identity[key] else {
                throw LycorineTSSError.stopped("Missing \(key)")
            }
            request[key] = v
        }
        for (key, raw) in components where key.hasPrefix("Cryptex1,") {
            guard let item = raw as? [String: Any],
                  let info = item["Info"] as? [String: Any],
                  info["Personalize"] as? Bool == true else { continue }
            guard let digest = item["Digest"] as? Data else {
                throw LycorineTSSError.stopped("No digest for \(key)")
            }
            request[key] = ["Digest": digest]
        }
        return try PropertyListSerialization.data(
            fromPropertyList: request, format: .xml, options: 0)
    }
    private static func extractTicket(_ body: Data) throws -> Data {
        guard let text = String(data: body, encoding: .utf8), text.count < 4_000_000 else {
            throw LycorineTSSError.stopped("Empty/oversized TSS reply")
        }
        let header = text.components(separatedBy: "&REQUEST_STRING=").first ?? text
        var fields: [String: String] = [:]
        for pair in header.split(separator: "&") {
            let bits = pair.split(separator: "=", maxSplits: 1)
            if bits.count == 2 { fields[String(bits[0])] = String(bits[1]) }
        }
        guard fields["STATUS"] == "0", fields["MESSAGE"] == "SUCCESS" else {
            throw LycorineTSSError.stopped(
                "Apple TSS rejected the custom image (STATUS \(fields["STATUS"] ?? "unknown"))")
        }
        guard let index = text.range(of: "REQUEST_STRING=")?.upperBound,
              let plist = try PropertyListSerialization.propertyList(
                  from: Data(text[index...].utf8), format: nil) as? [String: Any],
              let ticket = (plist["Cryptex1,Ticket"] ?? plist["ApImg4Ticket"]) as? Data,
              ticket.count > 128 else {
            throw LycorineTSSError.stopped("TSS did not provide an Image4 ticket")
        }
        return ticket
    }
    func requestFresh(_ picked: URL) async throws -> LycorineTSSResult {
        #if targetEnvironment(simulator)
        throw LycorineTSSError.stopped("No hardware-backed Cryptex in Simulator")
        #else
        let access = picked.startAccessingSecurityScopedResource()
        defer { if access { picked.stopAccessingSecurityScopedResource() } }
        let source = picked.standardizedFileURL
        let identity = try Self.loadManifest(source)
        let nonceDomain = try Self.numeric(identity["Cryptex1,NonceDomain"], "NonceDomain")
        let id = UUID().uuidString.uppercased()
        print("(tss) stage=manifest_integrity_pass id=\(id)")
        let (chip, nonce) = try readDevice(nonceDomain)
        print("(tss) stage=nonce_ready id=\(id)")
        let xml = try Self.requestXML(id, identity, chip, nonce)
        var request = URLRequest(url: URL(string: "https://gs.apple.com/TSS/controller?action=2")!)
        request.httpMethod = "POST"
        request.httpBody = xml
        request.timeoutInterval = 30
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("InetURL/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        print("(tss) stage=sent_to_apple id=\(id)")
        let (reply, metadata) = try await URLSession.shared.data(for: request)
        guard let http = metadata as? HTTPURLResponse, http.statusCode == 200 else {
            throw LycorineTSSError.stopped("Apple TSS transport failed")
        }
        let ticket = try Self.extractTicket(reply)
        print("(tss) stage=ticket_received_not_device_verified id=\(id)")
        let root = try Self.baseFolder()
        let signed = root.appendingPathComponent(Self.signedName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: signed.path) else {
            throw LycorineTSSError.stopped("Signed bundle already exists; refusing overwrite")
        }
        try FileManager.default.copyItem(at: source, to: signed)
        do {
            try ticket.write(to: signed.appendingPathComponent("im4m"), options: .atomic)
            let report = root.appendingPathComponent("tss-\(id).txt")
            try [
                "Request: \(id)", "Local asset integrity: SHA-384 verified",
                "Apple HTTPS TSS: returned Image4 ticket",
                "Installed on device: NO", "Device signature acceptance: NOT VERIFIED",
                "ECID, nonce and raw ticket: not logged"
            ].joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
            return LycorineTSSResult(signedBundle: signed, diagnostics: report)
        } catch {
            try? FileManager.default.removeItem(at: signed)
            throw error
        }
        #endif
    }
}
