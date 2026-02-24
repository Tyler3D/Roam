import SwiftUI

struct ChooseUsernameView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.apiClient) private var apiClient
    var onSuccess: (() -> Void)?
    @State private var username = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Choose a username")
                        .font(.title2.bold())
                    Text("This will be your unique handle on Roam.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField("username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    if let errorText {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Continue")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ThemeColors.primary)
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    .padding(.horizontal)
                }
                .padding(.top, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() async {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let apiClient else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            try await apiClient.ensureBackendUser(username: trimmed)
            onSuccess?()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    ChooseUsernameView()
        .environment(AuthManager())
        .environment(\.apiClient, APIClient(authManager: AuthManager(), appConfig: AppConfig()))
}
