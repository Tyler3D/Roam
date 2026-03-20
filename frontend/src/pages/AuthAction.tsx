import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { applyActionCode, confirmPasswordReset } from "firebase/auth";

import { useAuth } from "@/auth";
import { firebaseAuth } from "@/auth/firebase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getPasswordValidationMessage, validatePassword } from "@/lib/password";
import { Check } from "lucide-react";

export default function AuthAction() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { refreshUser, verifyBackendUser, isUserVerified } = useAuth();
  const [status, setStatus] = useState("Processing request...");
  const [mode, setMode] = useState("");
  const [oobCode, setOobCode] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [actionError, setActionError] = useState("");
  const [resetComplete, setResetComplete] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const runAction = async () => {
      const modeParam = searchParams.get("mode");
      const codeParam = searchParams.get("oobCode");
      setMode(modeParam ?? "");
      setOobCode(codeParam ?? "");
      if (!modeParam || !codeParam) {
        setStatus("Invalid action link. Please request a new email.");
        return;
      }

      if (modeParam === "resetPassword") {
        setStatus("Set a new password to finish resetting.");
        return;
      }

      if (modeParam !== "verifyEmail") {
        setStatus("Unsupported action. Please sign in again.");
        return;
      }

      try {
        await applyActionCode(firebaseAuth, codeParam);
        const refreshedUser = await refreshUser();
        if (!refreshedUser) {
          setStatus("Email verified. Please sign in to continue.");
          return;
        }
        if (!isUserVerified(refreshedUser)) {
          setStatus("Email verified. Please sign in again.");
          return;
        }
        await verifyBackendUser();
        navigate("/app");
      } catch {
        setStatus("Verification failed. Please request a new email.");
      }
    };

    runAction();
  }, [navigate, refreshUser, searchParams, verifyBackendUser, isUserVerified]);

  const handlePasswordReset = async (event: React.FormEvent) => {
    event.preventDefault();
    setActionError("");
    if (!oobCode) {
      setActionError("Invalid reset link. Please request a new email.");
      return;
    }
    if (!newPassword.trim()) {
      setActionError("Please enter a new password.");
      return;
    }
    const passwordError = getPasswordValidationMessage(newPassword);
    if (passwordError) {
      setActionError(passwordError);
      return;
    }
    setSubmitting(true);
    try {
      await confirmPasswordReset(firebaseAuth, oobCode, newPassword);
      setResetComplete(true);
    } catch {
      setActionError("Unable to reset password. Please request a new link.");
    } finally {
      setSubmitting(false);
    }
  };

  const passwordChecks = validatePassword(newPassword);

  if (mode === "resetPassword") {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-6">
        <div className="w-full max-w-lg rounded-3xl border border-border/60 bg-card p-8 shadow-sm space-y-4">
          <div className="space-y-2">
            <h1 className="text-2xl font-display font-semibold">
              {resetComplete ? "Password updated" : "Set a new password"}
            </h1>
            <p className="text-sm text-muted-foreground">
              {resetComplete
                ? "You can now sign in with your new password."
                : "Enter a new password to finish resetting your account."}
            </p>
          </div>
          {resetComplete ? (
            <Button onClick={() => navigate("/login")}>Go to sign in</Button>
          ) : (
            <form onSubmit={handlePasswordReset} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="password">New password</Label>
                <Input
                  id="password"
                  type="password"
                  value={newPassword}
                  onChange={(event) => setNewPassword(event.target.value)}
                  placeholder="Enter a new password"
                  required
                />
              </div>
              <div className="space-y-2 text-sm text-muted-foreground">
                <div className="flex items-center gap-2">
                  <Check className={passwordChecks.minLength ? "w-4 h-4 text-primary" : "w-4 h-4 text-muted-foreground/40"} />
                  <span>Password must be longer than 8 characters</span>
                </div>
                <div className="flex items-center gap-2">
                  <Check className={passwordChecks.hasLowercase ? "w-4 h-4 text-primary" : "w-4 h-4 text-muted-foreground/40"} />
                  <span>Password must have a lower case letter</span>
                </div>
                <div className="flex items-center gap-2">
                  <Check className={passwordChecks.hasUppercase ? "w-4 h-4 text-primary" : "w-4 h-4 text-muted-foreground/40"} />
                  <span>Password must have an upper case letter</span>
                </div>
              </div>
              {actionError && <p className="text-sm text-destructive">{actionError}</p>}
              <Button type="submit" disabled={submitting}>
                {submitting ? "Saving..." : "Reset password"}
              </Button>
            </form>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-6">
      <div className="w-full max-w-lg rounded-3xl border border-border/60 bg-card p-8 shadow-sm space-y-4">
        <h1 className="text-2xl font-display font-semibold">Completing verification</h1>
        <p className="text-sm text-muted-foreground">{status}</p>
        {status.includes("sign in") && (
          <Button onClick={() => navigate("/login")}>Go to sign in</Button>
        )}
      </div>
    </div>
  );
}

