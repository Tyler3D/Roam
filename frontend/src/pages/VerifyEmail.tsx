import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

import { useAuth } from "@/auth";

export default function VerifyAction() {
  const navigate = useNavigate();
  const { user, refreshUser, verifyBackendUser, isVerified } = useAuth();
  const [status, setStatus] = useState("Checking verification status...");

  useEffect(() => {
    const runCheck = async () => {
      try {
        const refreshedUser = await refreshUser();
        if (!refreshedUser || (!isVerified && !refreshedUser.emailVerified)) {
          setStatus("Email not verified yet. Please check your inbox.");
          navigate("/verification");
          return;
        }
        await verifyBackendUser();
        navigate("/app");
      } catch {
        setStatus("Verification failed. Redirecting...");
        navigate("/verification");
      }
    };
    runCheck();
  }, [refreshUser, verifyBackendUser, isVerified, navigate]);

  if (!user) {
    navigate("/login");
    return null;
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-6">
      <div className="w-full max-w-lg rounded-3xl border border-border/60 bg-card p-8 shadow-sm">
        <p className="text-sm text-muted-foreground">{status}</p>
      </div>
    </div>
  );
}

