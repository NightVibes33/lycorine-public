import SwiftUI
import IDevice
import IDeviceSwift
import UniformTypeIdentifiers
import UIKit

/// The LocalDevVPN/loopback RSD endpoint can differ by VPN implementation.
/// These are transport settings, not iOS firmware or exploit-version restrictions.
enum LycorineRSD {
    static var host: String {
        let value = UserDefaults.standard.string(forKey: "lycorine.rsd.host")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value! : HeartbeatManager.shared.ipAddress
    }
    static var port: UInt16 {
        let selected = UserDefaults.standard.integer(forKey: "lycorine.rsd.port")
        return (1...65535).contains(selected) ? UInt16(selected) : HeartbeatManager.shared.port_rsd
    }

    static func pairingValid(at path: String = HeartbeatManager.pairingFile()) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        var handle: OpaquePointer?
        let err = rp_pairing_file_read(path, &handle)
        if let err { idevice_error_free(err) }
        if let handle { rp_pairing_file_free(handle) }
        return err == nil && handle != nil
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var shouldUninstall: Bool
    @State private var showImporter = false
    @State private var hasPairingFile = false
    @State private var pairingStatus = "Not checked"
    @State private var rsdStatus = "Not tested"
    @State private var testing = false
    @AppStorage("lycorine.rsd.host") private var rsdHost = "10.7.0.1"
    @AppStorage("lycorine.rsd.port") private var rsdPort = 49152

    var body: some View {
        NavigationStack {
            Form {
                Section("RSD / LocalDevVPN") {
                    TextField("VPN tunnel IPv4", text: $rsdHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("RSD port", value: $rsdPort, format: .number)
                        .keyboardType(.numberPad)
                    Text("Defaults: 10.7.0.1:49152. Change these only to match your active tunnel. A pairing file does not start a VPN.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(testing ? "Testing RSD..." : "Test RSD / Cryptexd connection") {
                        testing = true
                        rsdStatus = "Connecting to \(LycorineRSD.host):\(LycorineRSD.port)…"
                        DispatchQueue.global(qos: .userInitiated).async {
                            let result: String
                            do {
                                let inventory = try cryptex_service.shared.list_installed()
                                result = "Connected to cryptexd. \(inventory.count) installed cryptex(es) reported. This does not establish signing authorization."
                            } catch {
                                result = error.localizedDescription
                            }
                            DispatchQueue.main.async {
                                rsdStatus = result
                                testing = false
                            }
                        }
                    }.disabled(testing || !hasPairingFile || !(1...65535).contains(rsdPort))
                    Text(rsdStatus)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Section("Pairing") {
                    Text(pairingStatus).font(.caption)
                    if hasPairingFile {
                        Button("Remove Pairing File", role: .destructive) {
                            try? FileManager.default.removeItem(atPath: HeartbeatManager.pairingFile())
                            refreshPairing()
                            rsdStatus = "Pairing removed"
                        }
                    }
                    Button(hasPairingFile ? "Replace Pairing File" : "Import Pairing File") {
                        showImporter = true
                    }
                    Text("Import a remote-pairing record for this device, not an unrelated device's pairing file. Credentials are parsed locally and never printed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Installation") {
                    Toggle("Remove Jailbreak", isOn: $shouldUninstall)
                    Text("A normal RSD connection cannot restore Apple's patched TSS vulnerability. A signed cryptex is required for privileged installation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { refreshPairing() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.xmlPropertyList, .propertyList, .mobiledevicepairing]) { result in
            switch result {
            case .failure(let error):
                pairingStatus = "Import failed: \(error.localizedDescription)"
            case .success(let fileURL):
                let access = fileURL.startAccessingSecurityScopedResource()
                defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
                let dest = URL(fileURLWithPath: HeartbeatManager.pairingFile())
                let stage = dest.deletingLastPathComponent()
                    .appendingPathComponent(".lycorine-pairing-\(UUID().uuidString).plist")
                do {
                    try FileManager.default.copyItem(at: fileURL, to: stage)
                    guard LycorineRSD.pairingValid(at: stage.path) else {
                        throw cryptex_err(msg: "Not a valid RSD pairing record. Your previous pairing file was preserved.")
                    }
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.moveItem(at: stage, to: dest)
                    refreshPairing()
                    rsdStatus = "Imported pairing; run Test RSD to verify the tunnel."
                } catch {
                    pairingStatus = "Pairing import failed: \(error.localizedDescription)"
                    hasPairingFile = LycorineRSD.pairingValid()
                }
                try? FileManager.default.removeItem(at: stage)
            }
        }
    }

    private func refreshPairing() {
        hasPairingFile = LycorineRSD.pairingValid()
        pairingStatus = hasPairingFile
            ? "Pairing record parses correctly; device/tunnel acceptance not yet verified."
            : (FileManager.default.fileExists(atPath: HeartbeatManager.pairingFile())
                ? "Pairing record exists, but RSD parsing failed. Replace it."
                : "No pairing record imported.")
    }
}
