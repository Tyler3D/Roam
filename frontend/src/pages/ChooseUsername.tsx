import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";

import { useAuth } from "@/auth/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const buildSuggestedUsername = (displayName?: string | null) => {
  if (!displayName) {
    return "";
  }
  const parts = displayName.trim().split(/\s+/);
  if (parts.length >= 2) {
    return `${parts[0]}${parts[1]}`.toLowerCase();
  }
  return displayName.replace(/\s+/g, "").toLowerCase();
};

export default function ChooseUsername() {
  const navigate = useNavigate();
  const { user, ensureBackendUser, isUserVerified } = useAuth();
  const suggested = useMemo(() => buildSuggestedUsername(user?.displayName), [user]);
  const [username, setUsername] = useState(suggested);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    const trimmed = username.trim();
    if (!trimmed) {
      setError("Please choose a username.");
      return;
    }
    setError(null);
    setLoading(true);
    try {
      await ensureBackendUser(trimmed);
      navigate(isUserVerified(user) ? "/app" : "/verification");
    } catch {
      setError("Unable to save username. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  if (!user) {
    navigate("/login");
    return null;
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
            <Input
              id="username"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              placeholder="yourname"
              required
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? "Saving..." : "Continue"}
          </Button>
        </form>
      </div>
    </div>
  );
}

