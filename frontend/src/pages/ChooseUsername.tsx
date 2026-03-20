import { useMemo, useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";

import { useAuth } from "@/auth";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { UsernameInput } from "@/components/UsernameInput";

/** firstNamelastName for Google accounts (e.g. "John Doe" → "johndoe"). Empty for others. */
const buildSuggestedUsername = (
  displayName: string,
  isGoogle: boolean,
) => {
  if (!isGoogle) return "";
  const trimmedName = displayName.trim();
  if (!trimmedName) return "";
  const parts = trimmedName.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) {
    return `${parts[0]}${parts[parts.length - 1]}`.toLowerCase();
  }
  return trimmedName.replace(/\s+/g, "").toLowerCase();
};

export default function ChooseUsername() {
  const navigate = useNavigate();
  const { user, loading: authLoading, ensureBackendUser, isUserVerified, signOutUser } = useAuth();
  const isGoogle = useMemo(
    () => user?.providerData?.some((p) => p.providerId === "google.com") ?? false,
    [user],
  );
  const suggested = useMemo(
    () => buildSuggestedUsername(user?.displayName ?? "", isGoogle),
    [user?.displayName, isGoogle],
  );
  const [username, setUsername] = useState(suggested);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    const trimmed = username.trim();
    if (!trimmed) {
      setError("Please choose a username.");
      return;
    }
    setError("");
    setLoading(true);
    try {
      await ensureBackendUser(trimmed);
      navigate(isUserVerified(user) ? "/app" : "/verification");
    } catch (err: unknown) {
      const status =
        err && typeof err === "object" && "status" in err
          ? (err as { status: number }).status
          : undefined;
      if (status === 429) {
        setError("Too many attempts. Please wait a few minutes and try again.");
      } else if (status === 401) {
        setError("Session expired or invalid. Sign out below and sign in again.");
      } else {
        setError("Unable to save username. Please try again.");
      }
    } finally {
      setLoading(false);
    }
  };

  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-muted-foreground">
        Loading...
      </div>
    );
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-6">
      <div className="w-full max-w-md rounded-3xl border border-border/60 bg-card p-8 shadow-sm">
        <div className="space-y-2">
          <h1 className="text-2xl font-display font-semibold">Pick a username</h1>
          <p className="text-muted-foreground text-sm">
            This will be used to share date ideas with others.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <div className="space-y-2">
            <Label htmlFor="username">Username</Label>
            <UsernameInput
              id="username"
              value={username}
              onChange={setUsername}
              placeholder="yourname"
              required
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Saving..." : "Continue"}
          </Button>
        </form>

        <div className="mt-6 flex justify-center">
          <Button type="button" variant="ghost" size="sm" className="text-muted-foreground" onClick={() => signOutUser()}>
            Sign out
          </Button>
        </div>
      </div>
    </div>
  );
}

