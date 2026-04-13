import FirebaseAuth
import SwiftUI

struct ChooseUsernameView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.apiClient) private var apiClient
    var onSuccess: (() -> Void)?
    @State private var username = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var isAvailable: Bool?
    @State private var isCheckingAvailability = false
    @State private var checkTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
                welcomeCard
                titleBlock
                usernameField
                Spacer(minLength: 0)
                submitButton
                progressDots
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .background(RoamColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.light)
            .onChange(of: username) { _, _ in
                isAvailable = nil
                errorText = nil
                checkTask?.cancel()
                guard usernameLooksValid else {
                    isCheckingAvailability = false
                    return
                }
                isCheckingAvailability = true
                checkTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    do {
                        let available = try await apiClient.checkUsernameAvailable(username: trimmedUsername)
                        guard !Task.isCancelled else { return }
                        isAvailable = available
                    } catch {
                        guard !Task.isCancelled else { return }
                    }
                    isCheckingAvailability = false
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(RoamColors.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(RoamColors.reviewBorder, lineWidth: 1.5)
                RoamNeedleLogoView(size: 28)
            }
            .frame(width: 44, height: 44)

            Text("Almost done")
                .font(RoamFont.mono(12, weight: .medium))
                .foregroundStyle(RoamColors.textMid)
                .textCase(.uppercase)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 32)
    }

    private var welcomeCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [RoamColors.reviewAccent, Color(red: 160 / 255, green: 110 / 255, blue: 240 / 255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Text(welcomeInitials)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(welcomeDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                Text(welcomeEmail)
                    .font(.system(size: 12))
                    .foregroundStyle(RoamColors.textMid)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Signed in")
                .font(RoamFont.mono(10, weight: .semibold))
                .foregroundStyle(RoamColors.reviewSuccess)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoamColors.reviewSuccessBg)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .textCase(.uppercase)
        }
        .padding(14)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(RoamColors.lavender, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.bottom, 24)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick a username")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(RoamColors.text)
            Text("This is how friends will find you on Roam. You can change it later.")
                .font(.system(size: 14))
                .foregroundStyle(RoamColors.textMid)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 28)
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username")
                .font(RoamFont.mono(12, weight: .semibold))
                .foregroundStyle(RoamColors.textMid)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                Text("@")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .frame(width: 28, alignment: .leading)
                TextField("username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(RoamColors.text)
                    .focused($fieldFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(fieldFocused ? RoamColors.reviewAccent : RoamColors.reviewBorder, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamColors.error)
            } else if isCheckingAvailability {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Checking availability...")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMid)
                }
            } else if usernameLooksValid, let isAvailable {
                if isAvailable {
                    Text("@\(trimmedUsername) is available")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.reviewSuccess)
                } else {
                    Text("@\(trimmedUsername) is already taken")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.error)
                }
            }
        }
        .padding(.bottom, 20)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Get started")
                }
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .background(RoamColors.reviewAccent)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: RoamColors.reviewAccent.opacity(0.35), radius: 16, x: 0, y: 4)
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.45)
        .padding(.bottom, 8)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(RoamColors.reviewSuccess)
                .frame(width: 8, height: 8)
            Capsule()
                .fill(RoamColors.reviewAccent)
                .frame(width: 20, height: 8)
        }
        .padding(.top, 16)
        .padding(.bottom, 28)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespaces)
    }

    private var usernameLooksValid: Bool {
        guard trimmedUsername.count >= 3 else { return false }
        return trimmedUsername.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        usernameLooksValid && !isLoading && isAvailable == true && !isCheckingAvailability
    }

    private var welcomeDisplayName: String {
        if let name = authManager.user?.displayName, !name.isEmpty { return name }
        if let email = authManager.user?.email, let local = email.split(separator: "@").first {
            return String(local)
        }
        return "You"
    }

    private var welcomeEmail: String {
        authManager.user?.email ?? "—"
    }

    private var welcomeInitials: String {
        if let name = authManager.user?.displayName, !name.isEmpty {
            let parts = name.split(separator: " ").filter { !$0.isEmpty }
            let first = parts.first?.first.map(String.init) ?? ""
            let second = parts.dropFirst().first?.first.map(String.init) ?? ""
            let s = (first + second).uppercased()
            return s.isEmpty ? "?" : s
        }
        if let email = authManager.user?.email, let c = email.first {
            return String(c).uppercased()
        }
        return "?"
    }

    private func submit() async {
        let trimmed = trimmedUsername
        guard !trimmed.isEmpty else { return }
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
