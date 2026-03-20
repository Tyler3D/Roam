import { type ReactNode, useSyncExternalStore } from "react";

import { AuthSessionContext } from "@/auth/sessionContext";
import {
  getFirebaseSessionSnapshot,
  getServerFirebaseSessionSnapshot,
  subscribeToFirebaseSession,
} from "@/auth/firebaseSessionStore";
import { useProcessGoogleOAuthRedirect } from "@/auth/googleOAuthRedirect";
import { useAuthSessionValue } from "@/auth/useAuthSessionValue";

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, authReady] = useSyncExternalStore(
    subscribeToFirebaseSession,
    getFirebaseSessionSnapshot,
    getServerFirebaseSessionSnapshot,
  );
  const loading = !authReady;

  useProcessGoogleOAuthRedirect();
  const value = useAuthSessionValue(user, loading);

  return (
    <AuthSessionContext.Provider value={value}>{children}</AuthSessionContext.Provider>
  );
}
