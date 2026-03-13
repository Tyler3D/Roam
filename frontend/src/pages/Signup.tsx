import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { useAuth } from "@/auth/AuthContext";
import { firebaseAuth } from "@/auth/firebase";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { getPasswordValidationMessage, validatePassword } from "@/lib/password";
import { Check } from "lucide-react";
import { deleteUser } from "firebase/auth";

export default function Signup() {
  const navigate = useNavigate();
  const { user, loading: authLoading, signUp, signInWithGoogle, sendVerificationEmail, ensureBackendUser } = useAuth();
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [verificationSent, setVerificationSent] = useState(false);

  const getErrorInfo = (error: unknown) => {
    if (error && typeof error === "object") {
      const maybeError = error as { status?: number; message?: string; code?: string };
      return {
        status: typeof maybeError.status === "number" ? maybeError.status : null,
        message: typeof maybeError.message === "string" ? maybeError.message : "",
        code: typeof maybeError.code === "string" ? maybeError.code : null,
      };
    }
    return { status: null, message: "", code: null };
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError("");
    setLoading(true);
    try {
      const trimmedUsername = username.trim();
      if (!trimmedUsername) {
        setError("Please choose a username.");
        setLoading(false);
        return;
      }
      const passwordError = getPasswordValidationMessage(password);
      if (passwordError) {
        setError(passwordError);
        setLoading(false);
        return;
      }
      await signUp(trimmedEmail, password);
      await ensureBackendUser(trimmedUsername);
      await sendVerificationEmail();
      setVerificationSent(true);
      navigate("/verification");
    } catch (err) {
      const apiError = getErrorInfo(err);
      if (apiError.code === "auth/email-already-in-use") {
        setError("Email already exists. Try a different email.");
        return;
      }
      if (apiError.status === 409 && apiError.message) {
        const message = apiError.message.toLowerCase();
        if (message.includes("username")) {
          setError("Username already exists. Try something else.");
          const currentUser = firebaseAuth.currentUser;
          if (currentUser) {
            try {
              await deleteUser(currentUser);
            } catch {
              // If deletion fails, leave the error message in place.
            }
          }
          return;
        }
        if (message.includes("email")) {
          setError("Email already exists. Try a different email.");
          return;
        }
      }
      setError("Unable to create account. Try a different email.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (user && !authLoading) navigate("/choose-username");
  }, [user, authLoading, navigate]);

  const handleGoogleSignIn = () => {
    setError("");
    signInWithGoogle();
  };

  const passwordChecks = validatePassword(password);
  const passwordError = getPasswordValidationMessage(password);
  const trimmedUsername = username.trim();
  const trimmedEmail = email.trim();
  const emailIsValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail);
  const canSubmit = !loading && !passwordError && trimmedUsername.length > 0 && emailIsValid;

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-6">
      <div className="w-full max-w-md rounded-3xl border border-border/60 bg-card p-8 shadow-sm">
        <div className="space-y-2">
          <h1 className="text-2xl font-display font-semibold">Create your account</h1>
          <p className="text-muted-foreground text-sm">
            Start capturing date ideas in seconds.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <div className="space-y-2">
            <Label htmlFor="username">Username</Label>
            <Input
              id="username"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              placeholder="yourname"
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="you@example.com"
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="Create a password"
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

          {error && <p className="text-sm text-destructive">{error}</p>}
          {verificationSent && (
            <p className="text-sm text-primary">
              Verification email sent. Please check your inbox.
            </p>
          )}

          <Button type="submit" className="w-full" disabled={!canSubmit}>
            {loading ? "Creating account..." : "Create account"}
          </Button>
        </form>

        <div className="mt-4">
          <Button
            type="button"
            variant="outline"
            className="w-full"
            onClick={handleGoogleSignIn}
            disabled={loading}
          >
            Continue with Google
          </Button>
        </div>

        <p className="text-sm text-muted-foreground mt-6">
          Already have an account?{" "}
          <Link to="/login" className="text-primary hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    </div>
  );
}

