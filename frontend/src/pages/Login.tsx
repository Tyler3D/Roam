import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";

import { useAuth } from "@/auth/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export default function Login() {
  const navigate = useNavigate();
  const { signIn, signInWithGoogle, syncBackendUser, isUserVerified } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError("");
    setLoading(true);
    try {
      const nextUser = await signIn(email, password);
      const hasBackendUser = await syncBackendUser();
      if (!hasBackendUser) {
        navigate("/choose-username");
        return;
      }
      navigate(isUserVerified(nextUser) ? "/app" : "/verification");
    } catch (err) {
      setError("Invalid email or password.");
    } finally {
      setLoading(false);
    }
  };

  const handleGoogleSignIn = async () => {
    setError("");
    setLoading(true);
    try {
      const nextUser = await signInWithGoogle();
      const hasBackendUser = await syncBackendUser();
      if (!hasBackendUser) {
        navigate("/choose-username");
        return;
      }
      navigate(isUserVerified(nextUser) ? "/app" : "/verification");
    } catch (err) {
      setError("Google sign-in failed.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-6">
      <div className="w-full max-w-md rounded-3xl border border-border/60 bg-card p-8 shadow-sm">
        <div className="space-y-2">
          <h1 className="text-2xl font-display font-semibold">Welcome back</h1>
          <p className="text-muted-foreground text-sm">
            Sign in to keep saving date ideas.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
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
              placeholder="••••••••"
              required
            />
          </div>

          {error && <p className="text-sm text-destructive">{error}</p>}

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Signing in..." : "Sign In"}
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
          <Link to="/reset-password" className="text-primary hover:underline">
            Forgot password?
          </Link>
        </p>

        <p className="text-sm text-muted-foreground mt-4">
          New here?{" "}
          <Link to="/signup" className="text-primary hover:underline">
            Create an account
          </Link>
        </p>
      </div>
    </div>
  );
}

