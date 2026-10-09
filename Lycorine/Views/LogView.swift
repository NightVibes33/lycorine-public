import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The log reader is started in LycorineApp, not in this view.
struct LogView: View {
    @StateObject private var mgr = LycorineManager.shared
    @State private var logDocument: LycorineLogExport?
    @State private var isExportingLog = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(mgr.log.isEmpty ? "Waiting for diagnostic output…" : mgr.log)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top)
                Color.clear.frame(height: 1).id("bottom")
            }
            .onAppear { proxy.scrollTo("bottom") }
            .onChange(of: mgr.log.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = mgr.log
                } label: {
                    Label("Copy Displayed Logs", systemImage: "doc.on.doc")
                }
                Button {
                    do {
                        logDocument = try LycorineLogExport.snapshot()
                        isExportingLog = true
                    } catch {
                        print("(log.export) snapshot failed: \(error.localizedDescription)")
                    }
                } label: {
                    Label("Save Full Log to Files", systemImage: "square.and.arrow.down")
                }
            }
            .fileExporter(isPresented: $isExportingLog,
                          document: logDocument,
                          contentType: .plainText,
                          defaultFilename: "Lycorine-Debug") { result in
                if case .failure(let error) = result {
                    print("(log.export) saving failed: \(error.localizedDescription)")
                }
                logDocument = nil
            }
        }
    }
}
