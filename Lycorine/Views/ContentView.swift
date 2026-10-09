import SwiftUI
import IDevice

struct ContentView: View {
    @StateObject private var install = InstallStatusModel()
    
    @State private var showLogs = false
    @State private var showSettings = false
    @State private var showApps = false
    @State private var showCredits = false
    @AppStorage("shouldUninstall") private var shouldUninstall = false
    
    @State private var isJailbroken = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                VStack(spacing: 0) {
                    Text("Lycorine")
                        .font(.largeTitle.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("iOS 26.0 - Latest (arm64e)")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 15)
                
                VStack {
                    if showLogs {
                        LogsSection
                    } else if showCredits {
                        CreditsSection
                    } else {
                        LogsSection
                        SettingsSection
                        AppsSection
                        CreditsSection
                    }
                }
                .modifier(SectionPlatter())
                
                VStack {
                    if isJailbroken {
                        Button {
                            
                        } label: {
                            ButtonLabel("Jailbroken", symbol: "checkmark")
                        }
                        .buttonStyle(TranslucentButtonStyle())
                        .disabled(true)
                    } else if shouldUninstall && (isJailbroken || isDebugBuild) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                showLogs = true
                            }
                            
                            do_uninstall()
                        } label: {
                            if install.isWorking {
                                ButtonLabel("Uninstalling...", symbol: "showMeProgressPlease")
                            } else {
                                ButtonLabel("Uninstall", symbol: "trash")
                            }
                        }
                        .buttonStyle(TranslucentButtonStyle())
                        .disabled(install.isWorking)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                showLogs = true
                            }
                            
                            do_install()
                        } label: {
                            if install.isWorking {
                                ButtonLabel("Jailbreaking...", symbol: "showMeProgressPlease")
                            } else {
                                ButtonLabel("Jailbreak", symbol: "lock.open")
                            }
                        }
                        .buttonStyle(TranslucentButtonStyle())
                        .disabled(install.isWorking)
                    }
                }
            }
            .padding(.horizontal, 35)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showSettings) {
                SettingsView(shouldUninstall: $shouldUninstall)
            }
            .sheet(isPresented: $showApps) {
                AppsView()
            }
            .onAppear(perform: { // i'm sorry there's probably a better way to do this
                do {
                    let installedCryptexes = try cryptex_service.shared.list_installed()
                    isJailbroken = installedCryptexes.contains(where: { $0.identifier == "com.saccharine.lycorine.recovery"})
                    
                    if isJailbroken {
                        print("(app) cryptex is installed, assuming jailbroken")
                    } else {
                        print("(app) cryptex is not installed, assuming not jailbroken")
                    }
                } catch {
                    print("(app) failed to detect jailbreak status")
                }
                
                if isDebugBuild {
                    // REMOVE IN PROD!!!!!
                    // how about... -Skadz 2026-10-03
                    isJailbroken = false
                    print("(app) overrode jailbreak state to false")
                }
            })
        }
    }
    
    private var LogsSection: some View {
        Group {
            NavigationDropdown(text: "Logs", icon: "terminal", toggle: $showLogs)
            
            if showLogs {
                LogView()
                    .modifier(TerminalPlatter())
            }
        }
    }
    
    private var SettingsSection: some View {
        Group {
            NavigationDropdown(text: "Settings", icon: "gear", toggle: $showSettings)
        }
    }
    
    private var AppsSection: some View {
        Group {
            NavigationDropdown(text: "Injection", icon: "syringe", toggle: $showApps)
        }
    }
    
    private var CreditsSection: some View {
        Group {
            NavigationDropdown(text: "Credits", icon: "star", toggle: $showCredits)
            
            if showCredits {
                CreditsView()
            }
        }
    }
    
    // MARK: functions
    private func do_install() {
        install.begin(action: .install)
        print("(install) starting install…")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let bundle = try cryptex_service.load_sealed_img()
                print("(install) loaded \(bundle.id) \(bundle.version) from bundle")
                
                let installed = try cryptex_service.shared.install_sealed_img(bundle)
                print("(install) cryptex installed: \(installed.identifier) \(installed.version)")
                
                let request = try InstallInbox.queue(.install)
                print("(install) queued bootstrap install \(request.id)")
                
                DispatchQueue.main.sync { install.watch(request) }
                DispatchQueue.main.async { install.operationComplete() }
            } catch {
                DispatchQueue.main.async { install.failed(error) }
            }
        }
    }

    private func do_uninstall() {
        install.begin(action: .uninstall)
        print("starting uninstall…")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let request = try InstallInbox.queue(.uninstall)
                print("queued bootstrap uninstall \(request.id)")
                DispatchQueue.main.sync { install.watch(request) }
                DispatchQueue.main.async { install.operationComplete() }
            } catch {
                DispatchQueue.main.async { install.failed(error) }
            }
        }
    }

    private func clearPastActions() {
        do {
            let removed = try InstallInbox.clearCompleted()
            print("cleared past actions (\(removed) files)")
        } catch {
            print("clear past actions failed: \(error)")
        }
    }
}
