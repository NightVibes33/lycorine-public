import SwiftUI
import UIKit

struct AppsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var model = AppsModel()
    @State private var search = ""

    private var visibleApps: [InstalledApp] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.bundleID.localizedCaseInsensitiveContains(search)
        }
    }
    
    private func iconinator(bundleID: String, format: Int = 1, scale: CGFloat = UIScreen.main.scale) -> UIImage {
        if let img = UIImage._applicationIconImage(forBundleIdentifier: bundleID, format: Int32(format), scale: scale) {
            return img
        }
        
        return UIImage(systemName: "app") ?? UIImage()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.isLoading && model.apps.isEmpty {
                        ProgressView("Loading apps…")
                            .frame(maxWidth: .infinity)
                            .listRowInsets(EdgeInsets())
                            .padding(30)
                    } else if visibleApps.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                    
                    appSection("User Apps", type: "User")
                    appSection("System Apps", type: "System")
                } footer: {
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Apps")
            .searchable(text: $search, prompt: "Name or bundle ID")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.refresh()
                    } label: {
                        Label("Refresh", systemImage: "goforward")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(model.isLoading || model.busyAppID != nil)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .task { model.loadIfNeeded() }
        }
    }

    @ViewBuilder
    private func appSection(_ title: String, type: String) -> some View {
        let apps = visibleApps.filter { $0.type == type }
        if !apps.isEmpty {
            Section(title) {
                ForEach(apps) { app in
                    HStack(spacing: 12) {
                        let icon = iconinator(bundleID: app.bundleID)
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(AnyShape(.rect(cornerRadius: 14)))
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                            Text(app.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(app.cloneState.label)
                                .font(.caption2)
                                .foregroundStyle(app.cloneState == .enabled ? .green : .secondary)
                        }
                        
                        Spacer(minLength: 8)
                        
                        if model.busyAppID == app.id {
                            ProgressView()
                        } else {
                            Button(app.cloneState == .enabled ? "Disable" : "Enable") {
                                model.toggle(app)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.busyAppID != nil || model.isLoading)
                        }
                    }
                }
            }
        }
    }
}
