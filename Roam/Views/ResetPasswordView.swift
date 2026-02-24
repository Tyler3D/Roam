import SwiftUI

struct ResetPasswordView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var status: String?
    @State private var isLoading = false
    @State private var isSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    authCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }
            .background(ThemeColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .preferredColorScheme(.light)
        }
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reset password")
                    .font(.title2.bold())
                Text("Enter your email to receive a reset link.")
                    .font(.subheadline)
                    .foregroundStyle(ThemeColors.mutedForeground)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Email")
                    .font(.subheadline.weight(.medium))
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)
            }

            if let status {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(isSuccess ? ThemeColors.mutedForeground : Color.red)
            }

            Button {
                Task { await sendReset() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send reset link")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ThemeColors.primary)
            .disabled(email.isEmpty || isLoading)

            Text("Back to Sign in")
                .font(.subheadline)
                .foregroundStyle(ThemeColors.primary)
                .onTapGesture { dismiss() }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeColors.card)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(ThemeColors.border, lineWidth: 1)
        )
        .shadow(color: ThemeColors.shadow, radius: 8, x: 0, y: 2)
    }

    private func sendReset() async {
        status = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
            isSuccess = true
            status = "Password reset email sent. Check your inbox."
        } catch {
            isSuccess = false
            status = "Unable to send reset email. Try again."
        }
    }
}

#Preview {
    ResetPasswordView()
        .environment(AuthManager())
}
