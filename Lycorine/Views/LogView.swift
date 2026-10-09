//
//  LogView.swift
//  dirtyZero
//
//  Created by lunginspector on 4/17/26.
//

import SwiftUI

struct LogView: View {
    @StateObject private var mgr = LycorineManager.shared
    
    var body: some View {
        GeometryReader { _ in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    Text(mgr.log)
                        .font(.system(size: 10, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .padding(.top)
                    Spacer()
                        .id(0)
                }
                .onAppear {
                    pipe.fileHandleForReading.readabilityHandler = { fh in
                        let data = fh.availableData

                        if data.isEmpty {
                            fh.readabilityHandler = nil
                            sema.signal()
                            return
                        }

                        guard let text = String(data: data, encoding: .utf8) else {
                            return
                        }
                        
                        let rust_log_fix = text
                            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
                            .replacingOccurrences(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s*"#, with: "", options: .regularExpression)
                            .replacingOccurrences(of: #"(?m)^\s*(?:WARN|INFO|ERROR|DEBUG|TRACE)\s+([a-zA-Z_][a-zA-Z0-9_]*)::(?:[^:]+::)*[^:]+:\s*"#, with: "($1) ", options: .regularExpression)
                            .replacingOccurrences(of: #"(?i)InternalError\("([^"]+)"\)"#, with: "$1", options: .regularExpression)

                        DispatchQueue.main.async {
                            mgr.log.append(rust_log_fix)
                            proxy.scrollTo(0)
                        }
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = mgr.log
                    } label: {
                        Label("Copy Output", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        do {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MM-dd-yyyy-HHmmss"
                            let date = formatter.string(from: Date())
                            
                            let tempURL = URL.temporaryDirectory.appendingPathComponent("Lycorine-Log-\(date)").appendingPathExtension("txt")
                            guard let data = mgr.log.data(using: .utf8) else {
                                throw "failed to create data from log string"
                            }
                            
                            try data.write(to: tempURL)
                            presentShareSheet(with: tempURL)
                        } catch {
                            print("(fm) failed to export logs: \(error.localizedDescription)")
                        }
                    } label: {
                        Label("Export Logs", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
