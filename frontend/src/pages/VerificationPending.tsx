import { useState } from "react";
import { useNavigate } from "react-router-dom";

import { useAuth } from "@/auth/AuthContext";
import { Button } from "@/components/ui/button";

export default function VerificationPending() {
  const navigate = useNavigate();
  const { user, sendVerificationEmail } = useAuth();
  const [status, setStatus] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleResend = async () => {
    setLoading(true);
    setStatus(null);
    try {
      await sendVerificationEmail();
      setStatus("Verification email sent. Please check your inbox.");
    } catch {
      setStatus("Unable to send verification email. Try again.");
    } finally {
      setLoading(false);
    }
  };

  if (!user) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-6">
        <div className="w-full max-w-lg rounded-3xl border border-border/60 bg-card p-8 shadow-sm space-y-4">
          <h1 className="text-2xl font-display font-semibold">Check your email</h1>
          <p className="text-muted-foreground text-sm">
            Please sign in first, then return here to confirm your email.
          </p>
          <Button onClick={() => navigate("/login")}>Go to sign in</Button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-6">
      <div className="w-full max-w-lg rounded-3xl border border-border/60 bg-card p-8 shadow-sm space-y-6">
        <div className="space-y-2">
          <h1 className="text-2xl font-display font-semibold">Check your email</h1>
          <p className="text-muted-foreground text-sm">
            We sent a verification link to {user.email}. Please click it to continue.
            If you don’t see it, check spam or resend below.
          </p>
        </div>

        {status && <p className="text-sm text-muted-foreground">{status}</p>}

        <Button variant="outline" onClick={handleResend} disabled={loading}>
          Resend email
        </Button>
      </div>
    </div>
  );
}

