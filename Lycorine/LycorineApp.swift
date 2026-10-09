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
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        
        // fix file picker
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        setup_heartbeat()
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
        
        print("(launch) starting heartbeat")
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
