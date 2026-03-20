/**
 * App auth: import `AuthProvider` and `useAuth` from `@/auth` only.
 * Internals live alongside this file (firebase session store, Google redirect, etc.).
 */
export { AuthProvider } from "@/auth/AuthProvider";
export { useAuth } from "@/auth/sessionContext";
export type { AuthContextValue } from "@/auth/types";
