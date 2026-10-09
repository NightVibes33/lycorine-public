//
//  SettingsView.swift
//  Lycorine
//
//  Created by ruter on 30.09.26.
//

import SwiftUI
import IDeviceSwift
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var shouldUninstall: Bool
    @State private var showImporter = false
    @State private var hasPairingFile = false
    @State private var hasLocalDevVpn = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Remove Jailbreak", isOn: $shouldUninstall)
                    if hasPairingFile {
                        Button("Remove Pairing File", role: .destructive) {
                            let pairingFileURL = URL(fileURLWithPath: HeartbeatManager.pairingFile())
                            if fm.fileExists(atPath: pairingFileURL.path) {
                                try? fm.removeItem(at: pairingFileURL)
                            }
                            
                            hasPairingFile = false
                        }
                    } else {
                        Button("Import Pairing File") {
                            showImporter = true
                        }
                    }
                } header: {
                    HeaderLabel("Installation", symbol: "arrow.down.circle")
                } footer: {
                    if hasPairingFile {
                        Text("Seems like you've got yourself a Feather-looking pairing file indication message!")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .onAppear {
            hasPairingFile = FileManager.default.fileExists(atPath: HeartbeatManager.pairingFile())

            if let url = URL(string: "localdevvpn://") {
                hasLocalDevVpn = UIApplication.shared.canOpenURL(url)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.xmlPropertyList, .propertyList, .mobiledevicepairing]) { result in
            switch result {
            case .success(let fileURL):
                let stopAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if stopAccess {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                let destURL = URL(fileURLWithPath: HeartbeatManager.pairingFile())

                do {
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }

                    try fm.copyItem(at: fileURL, to: destURL)

                    hasPairingFile = true
                } catch {
                    print("(pairing) copy failed:", error)
                    hasPairingFile = false
                }

            case .failure(let error):
                print("(pairing) file import failed:", error)
            }
        }
    }
}
