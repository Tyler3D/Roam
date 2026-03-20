import { createContext, useContext } from "react";

import type { AuthContextValue } from "@/auth/types";

/** React context for Firebase user + auth helpers (see `AuthProvider`). */
export const AuthSessionContext = createContext<AuthContextValue | undefined>(
  undefined,
);

export function useAuth(): AuthContextValue {
  const context = useContext(AuthSessionContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
