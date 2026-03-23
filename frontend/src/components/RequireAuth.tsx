import { useQuery } from "@tanstack/react-query";
import { Navigate } from "react-router-dom";

import { backendUserGateQueryKey, fetchBackendUserGate } from "@/api/auth";
import { useAuth } from "@/auth";
import { Button } from "@/components/ui/button";
import { DEV_AUTH_BYPASS_ENABLED } from "@/utils/util";

function getErrorStatus(error: unknown): number | undefined {
  if (error && typeof error === "object" && "status" in error) {
    const s = (error as { status: unknown }).status;
    return typeof s === "number" ? s : undefined;
  }
  return undefined;
}

export function RequireAuth({ children }: { children: React.ReactNode }) {
  const { user, loading, isVerified, signOutUser } = useAuth();
  const bypassEnabled = DEV_AUTH_BYPASS_ENABLED;

  const gateOpen = Boolean(!bypassEnabled && user && isVerified && !loading);

  const backendGate = useQuery({
    queryKey: backendUserGateQueryKey(user?.uid),
    queryFn: fetchBackendUserGate,
    enabled: gateOpen,
    staleTime: 0,
    retry: false,
  });

  if (bypassEnabled) {
    return <>{children}</>;
  }

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

  if (backendGate.isError) {
    const status = getErrorStatus(backendGate.error);
    if (status === 401) {
      return (
        <div className="min-h-screen flex flex-col items-center justify-center gap-4 px-6 text-center">
          <p className="text-muted-foreground max-w-sm">
            We couldn&apos;t verify your session with the server. Sign out and sign in again, or wait a few
            minutes if you recently hit a rate limit.
          </p>
          <Button type="button" variant="outline" onClick={() => signOutUser()}>
            Sign out
          </Button>
        </div>
      );
    }
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-4 px-6 text-center">
        <p className="text-muted-foreground max-w-sm">
          Couldn&apos;t load your account. Check your connection and try again.
        </p>
        <Button type="button" variant="outline" onClick={() => backendGate.refetch()}>
          Retry
        </Button>
      </div>
    );
  }

  if (backendGate.isPending || backendGate.isFetching) {
    return (
      <div className="min-h-screen flex items-center justify-center text-muted-foreground">
        Loading...
      </div>
    );
  }

  if (backendGate.data === false) {
    return <Navigate to="/choose-username" replace />;
  }

  if (backendGate.data === true) {
    return <>{children}</>;
  }

  return (
    <div className="min-h-screen flex items-center justify-center text-muted-foreground">
      Loading...
    </div>
  );
}
