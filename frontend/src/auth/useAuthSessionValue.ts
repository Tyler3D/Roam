import { useMemo } from "react";
import {
  createUserWithEmailAndPassword,
  GoogleAuthProvider,
  reload,
  sendEmailVerification,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signInWithPopup,
  signInWithRedirect,
  signOut,
  type User,
} from "firebase/auth";
import { useQueryClient } from "@tanstack/react-query";

import {
  useCreateBackendUser,
  useStoreOAuthToken,
  useVerifyBackendUser,
} from "@/api/auth";
import { firebaseAuth } from "@/auth/firebase";
import { syncFirebaseSessionFromCurrentUser } from "@/auth/firebaseSessionStore";
import { readGoogleOAuthFromUserCredential } from "@/auth/googleOAuthRedirect";
import { userMeetsVerificationPolicy } from "@/auth/verificationPolicy";
import type { AuthContextValue } from "@/auth/types";
import { ROAM_DOMAIN } from "@/utils/util";

/** Builds the object passed to `AuthSessionContext.Provider` (sign-in, profile, backend hooks). */
export function useAuthSessionValue(
  user: User | null,
  loading: boolean,
): AuthContextValue {
  const queryClient = useQueryClient();
  const createUser = useCreateBackendUser();
  const verifyUser = useVerifyBackendUser();
  const storeOAuthToken = useStoreOAuthToken();

  return useMemo<AuthContextValue>(() => {
    const isUserVerified = (inputUser?: User | null) =>
      userMeetsVerificationPolicy(inputUser ?? user);

    return {
      user,
      loading,
      isVerified: userMeetsVerificationPolicy(user),
      isUserVerified,
      signIn: async (email: string, password: string) => {
        const credential = await signInWithEmailAndPassword(
          firebaseAuth,
          email,
          password,
        );
        return credential.user;
      },
      signUp: async (email: string, password: string) => {
        const credential = await createUserWithEmailAndPassword(
          firebaseAuth,
          email,
          password,
        );
        return credential.user;
      },
      signInWithGoogle: async () => {
        const provider = new GoogleAuthProvider();
        provider.addScope("https://www.googleapis.com/auth/calendar.events");
        if (import.meta.env.DEV) {
          console.log("[roam-auth] signInWithPopup (local dev)");
          const result = await signInWithPopup(firebaseAuth, provider);
          const payload = readGoogleOAuthFromUserCredential(result);
          if (payload) {
            storeOAuthToken.mutate(payload, { onError: () => {} });
          }
        } else {
          console.log("[roam-auth] signInWithRedirect");
          await signInWithRedirect(firebaseAuth, provider);
        }
      },
      signOutUser: async () => {
        await signOut(firebaseAuth);
      },
      sendVerificationEmail: async () => {
        if (!firebaseAuth.currentUser) {
          throw new Error("No authenticated user");
        }
        const redirectUrl = `${ROAM_DOMAIN}/verify`;
        console.log("Sending verification email", {
          redirectUrl,
          handleCodeInApp: true,
        });
        await sendEmailVerification(firebaseAuth.currentUser, {
          url: redirectUrl,
          handleCodeInApp: true,
        });
      },
      resetPassword: async (email: string) => {
        const redirectUrl = `${ROAM_DOMAIN}/login`;
        await sendPasswordResetEmail(firebaseAuth, email, {
          url: redirectUrl,
          handleCodeInApp: true,
        });
      },
      refreshUser: async () => {
        if (!firebaseAuth.currentUser) {
          return null;
        }
        await reload(firebaseAuth.currentUser);
        syncFirebaseSessionFromCurrentUser();
        return firebaseAuth.currentUser;
      },
      ensureBackendUser: async (username: string) => {
        const trimmedUsername = username.trim();
        if (!trimmedUsername) {
          throw new Error("Username is required");
        }
        const currentUser = firebaseAuth.currentUser;
        const nameParts = (currentUser?.displayName ?? "").split(" ");
        await createUser.mutateAsync({
          username: trimmedUsername,
          email: currentUser?.email ?? undefined,
          firstName: nameParts[0] ?? "",
          lastName: nameParts.slice(1).join(" ") || "",
          photoUrl: currentUser?.photoURL ?? undefined,
        });
        await queryClient.invalidateQueries({ queryKey: ["backendUserGate"] });
      },
      verifyBackendUser: async () => {
        await verifyUser.mutateAsync();
      },
    };
  }, [user, loading, createUser, verifyUser, storeOAuthToken, queryClient]);
}
