import { Navigate } from "react-router-dom";

import { useAuth } from "@/auth/AuthContext";

export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { user, loading, isVerified } = useAuth();

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

  return <>{children}</>;
}

