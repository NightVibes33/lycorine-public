import SwiftUI
import UIKit

/// The log reader is started in LycorineApp, not in this view.
struct LogView: View {
    @StateObject private var mgr = LycorineManager.shared

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
                ShareLink(item: LycorineDiagnosticLog.shared.currentFileURL) {
                    Label("Export Full Persistent Log", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
