export const validatePassword = (password: string) => ({
    minLength: password.length >= 8,
    hasLowercase: /[a-z]/.test(password),
    hasUppercase: /[A-Z]/.test(password),
});

export const getPasswordValidationMessage = (password: string) => {
    const checks = validatePassword(password);
    if (!checks.minLength) {
        return "Password must be at least 8 characters.";
    }
    if (!checks.hasLowercase) {
        return "Password must include a lowercase letter.";
    }
    if (!checks.hasUppercase) {
        return "Password must include an uppercase letter.";
    }
    return null;
};

