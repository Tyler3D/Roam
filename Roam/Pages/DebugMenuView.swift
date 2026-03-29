import SwiftUI

#if DEBUG
struct DebugMenuView: View {
    @Environment(AppConfig.self) private var appConfig
    @Environment(\.dismiss) private var dismiss
    @State private var stagingURLText: String = ""
    @State private var pendingEnv: NetworkEnv?
    @State private var showEnvSwitchAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("App mode", selection: Binding(
                        get: { appConfig.appMode },
                        set: { appConfig.appMode = $0 }
                    )) {
                        ForEach(AppMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("App mode")
                } footer: {
                    Text("Main Roam: Ideas, Map, Reels only. Alpha: adds Drafts & Plans tabs. Reel queue only: shared extension inbox.")
                }

                Section {
                    Picker("App Network Env", selection: Binding(
                        get: { appConfig.networkEnv },
                        set: { newEnv in
                            if newEnv != appConfig.networkEnv {
                                pendingEnv = newEnv
                                showEnvSwitchAlert = true
                            }
                        }
                    )) {
                        ForEach(NetworkEnv.allCases) { env in
                            Text(env.displayName).tag(env)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("App Network Env")
                } footer: {
                    Text("Switching environments will sign you out and reconfigure Firebase. Local and production share the production Firebase project; staging uses a separate project.")
                }

                Section {
                    Toggle("Should Roam UI show up on ShareExtension?", isOn: Binding(
                        get: { appConfig.showShareExtensionConfirmationUI },
                        set: { appConfig.showShareExtensionConfirmationUI = $0 }
                    ))
                } footer: {
                    Text("When off, the extension saves the reel and metadata then closes without the confirmation card.")
                }

                Section {
                    LabeledContent("Effective URL", value: appConfig.effectiveBaseURLDisplay)
                        .lineLimit(2)
                } header: {
                    Text("Current")
                }

                if appConfig.networkEnv == .staging {
                    Section {
                        TextField("Staging base URL", text: $stagingURLText)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        Button("Save override") {
                            let trimmed = stagingURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                            appConfig.stagingBaseURLOverride = trimmed.isEmpty ? nil : trimmed
                        }
                    } header: {
                        Text("Staging URL override")
                    } footer: {
                        Text("Leave empty to use default from Info.plist.")
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                stagingURLText = appConfig.stagingBaseURLOverride ?? ""
            }
            .alert("Switch environment?", isPresented: $showEnvSwitchAlert) {
                Button("Switch", role: .destructive) {
                    if let env = pendingEnv {
                        appConfig.networkEnv = env
                        dismiss()
                    }
                    pendingEnv = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingEnv = nil
                }
            } message: {
                if let env = pendingEnv {
                    Text("You will be signed out and switched to \(env.displayName). You'll need to sign in again with credentials for that environment.")
                }
            }
        }
    }
}
#endif
