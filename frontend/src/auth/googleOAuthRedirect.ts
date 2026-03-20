import type { UserCredential } from "firebase/auth";
import { getRedirectResult, GoogleAuthProvider } from "firebase/auth";
import { useQuery } from "@tanstack/react-query";

import { sendOAuthTokenToBackend } from "@/api/auth";
import { firebaseAuth } from "@/auth/firebase";

export type GoogleOAuthPayload = {
  accessToken: string;
  expiresAt: string | null;
};

/** Reads Google access token + expiry from a popup or redirect sign-in result. */
export function readGoogleOAuthFromUserCredential(
  result: UserCredential,
): GoogleOAuthPayload | null {
  const credential = GoogleAuthProvider.credentialFromResult(result);
  const accessToken = credential?.accessToken;
  if (!accessToken) return null;
  const sts = (result.user as { stsTokenManager?: { expirationTime?: number } })
    ?.stsTokenManager;
  const expiresAt = sts?.expirationTime
    ? new Date(sts.expirationTime).toISOString()
    : null;
  return { accessToken, expiresAt };
}

/**
 * After `signInWithRedirect`, completes the flow and sends the calendar OAuth token to your API.
 * Must run under `QueryClientProvider` (see `App` → `AuthProvider` order).
 */
export function useProcessGoogleOAuthRedirect() {
  useQuery({
    queryKey: ["auth", "googleRedirectResult"],
    queryFn: async () => {
      console.log("[roam-auth] calling getRedirectResult");
      const result = await getRedirectResult(firebaseAuth);
      console.log(
        "[roam-auth] getRedirectResult done",
        result?.user?.uid ?? "no user",
      );
      if (result) {
        const payload = readGoogleOAuthFromUserCredential(result);
        if (payload) {
          try {
            await sendOAuthTokenToBackend(payload);
          } catch {
            // Calendar scope token is best-effort
          }
        }
      }
      return result?.user?.uid ?? null;
    },
    staleTime: Infinity,
    gcTime: Infinity,
    retry: false,
  });
}
