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
                    Picker("Mode", selection: Binding(
                        get: { appConfig.currentMode },
                        set: { appConfig.currentMode = $0 }
                    )) {
                        ForEach(AppMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("App mode")
                }

                Section {
                    LabeledContent("Effective URL", value: appConfig.effectiveBaseURLDisplay)
                        .lineLimit(2)
                } header: {
                    Text("Current")
                }

                if appConfig.currentMode == .staging {
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
