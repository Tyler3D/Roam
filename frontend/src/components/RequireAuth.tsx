import { useEffect, useRef, useState } from "react";
import { Navigate } from "react-router-dom";

import { useAuth } from "@/auth/AuthContext";

export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { user, loading, isVerified, syncBackendUser } = useAuth();
  const [backendReady, setBackendReady] = useState<boolean | null>(null);
  const syncStarted = useRef(false);
  const syncRef = useRef(syncBackendUser);
  syncRef.current = syncBackendUser;

  useEffect(() => {
    if (!user || !isVerified) return;
    if (syncStarted.current) return;
    syncStarted.current = true;
    let cancelled = false;
    syncRef.current()
      .then((exists) => {
        if (!cancelled) setBackendReady(exists);
      })
      .catch(() => {
        if (!cancelled) setBackendReady(false);
      });
    return () => {
      cancelled = true;
    };
  }, [user?.uid, isVerified]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-muted-foreground">
        Loading...
      </div>
    );
  }

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  if (!isVerified) {
    return <Navigate to="/verification" replace />;
  }

  if (backendReady === false) {
    return <Navigate to="/choose-username" replace />;
  }

  if (backendReady !== true) {
    return (
      <div className="min-h-screen flex items-center justify-center text-muted-foreground">
        Loading...
      </div>
    );
  }

  return <>{children}</>;
}

