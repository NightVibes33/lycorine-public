//
//  LycorineApp.swift
//  Lycorine
//
//  Created by LL on 9/22/26.
//

import SwiftUI
import UIKit
import IDeviceSwift
import Combine
import UniformTypeIdentifiers

var pipe = Pipe()
var sema = DispatchSemaphore(value: 0)
var isDebugBuild: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}
let fm = FileManager.default

final class LycorineManager: ObservableObject {
    static let shared = LycorineManager()
    @Published var log = ""
    
    init() {}
}

@main
struct LycorineApp: App {
    @StateObject private var mgr = LycorineManager.shared
    
    init() {
        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        LycorineDiagnosticLog.shared.start(reading: pipe)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        print("(diagnostics) launch version=\(version) build=\(build) iOS=\(UIDevice.current.systemVersion)")
        print("(diagnostics) Files: On My iPhone > Lycorine > Lycorine-Logs > latest.log")
        print("(diagnostics) Documents sharing enabled; pairingFile.plist contains sensitive credentials")
        
        #if targetEnvironment(simulator)
        print("(simulator) app preview; device pairing and Cryptexd disabled")
        #else
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        setup_heartbeat()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mgr)
        }
    }
    
    private func setup_heartbeat() {
        let pf = HeartbeatManager.pairingFile()
        print("(launch) checking installed cryptexes...")
        
        guard fm.fileExists(atPath: pf) else {
            print("(launch) no pairing file")
            return
        }
        
        if HeartbeatManager.shared.isRsd {
            print("(launch) RSD mode: direct per-command tunnel; heartbeat is not used")
            print("(launch) Open Settings > Test RSD to verify the active LocalDevVPN tunnel")
            return
        }

        print("(launch) starting legacy Lockdown heartbeat")
        HeartbeatManager.shared.start()

        DispatchQueue.global(qos: .utility).async {
            do {
                let installed = try cryptex_service.shared.list_installed()
                
                if installed.isEmpty {
                    print("(launch) no installed cryptexes reported")
                } else {
                    print("(launch) installed cryptexes (\(installed.count)):")
                    
                    for cryptex in installed {
                        print("- \(cryptex.identifier) \(cryptex.version)")
                    }
                }
            } catch {
                print("(launch) cryptex inventory failed: \(error)")
            }
        }
    }
}

// FixFilePicker
extension UIDocumentPickerViewController {
    @objc func fix_init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool) -> UIDocumentPickerViewController {
        return fix_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}
