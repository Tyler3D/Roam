import Foundation

/// Password rules aligned with frontend (Signup.tsx + lib/password.ts): length > 8, uppercase, lowercase, number.
struct PasswordValidation {
    var minLength: Bool { password.count > 8 }
    var hasUppercase: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
    var hasLowercase: Bool { password.range(of: "[a-z]", options: .regularExpression) != nil }
    var hasNumber: Bool { password.range(of: "[0-9]", options: .regularExpression) != nil }

    var allPassed: Bool { minLength && hasUppercase && hasLowercase && hasNumber }

    let password: String

    init(password: String) {
        self.password = password
    }

    /// Returns a user-facing message if validation fails; nil if all rules pass.
    static func message(for password: String) -> String? {
        let v = PasswordValidation(password: password)
        if v.password.isEmpty { return nil }
        if !v.minLength { return "Password must be longer than 8 characters." }
        if !v.hasLowercase { return "Password must include a lowercase letter." }
        if !v.hasUppercase { return "Password must include an uppercase letter." }
        if !v.hasNumber { return "Password must include a number." }
        return nil
    }
}
