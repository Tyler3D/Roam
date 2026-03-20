import SwiftUI

#if DEBUG
struct DebugMenuView: View {
    @Environment(AppConfig.self) private var appConfig
    @Environment(\.dismiss) private var dismiss
    @State private var stagingURLText: String = ""

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
                    Text("Main Roam: full tab app. Reel queue only: shared extension inbox. Time estimates: placeholder.")
                }

                Section {
                    Picker("App Network Env", selection: Binding(
                        get: { appConfig.networkEnv },
                        set: { appConfig.networkEnv = $0 }
                    )) {
                        ForEach(NetworkEnv.allCases) { env in
                            Text(env.displayName).tag(env)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("App Network Env")
                } footer: {
                    Text("Mock disables auth. Local/Staging/Production connect to backend.")
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
        }
    }
}
#endif
