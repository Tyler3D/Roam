import { createContext, useContext, useEffect, useMemo, useState } from "react";
import {
  getRedirectResult,
  GoogleAuthProvider,
  User,
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  reload,
  sendPasswordResetEmail,
  sendEmailVerification,
  signInWithEmailAndPassword,
  signInWithPopup,
  signInWithRedirect,
  signOut,
} from "firebase/auth";

import { firebaseAuth } from "@/auth/firebase";
import { ROAM_DOMAIN } from "@/utils/util";
import { useCreateBackendUser, useStoreOAuthToken, useSyncBackendUser, useVerifyBackendUser } from "@/api/auth";

type AuthContextValue = {
  user: User | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<User>;
  signUp: (email: string, password: string) => Promise<User>;
  signInWithGoogle: () => Promise<void>;
  signOutUser: () => Promise<void>;
  sendVerificationEmail: () => Promise<void>;
  resetPassword: (email: string) => Promise<void>;
  refreshUser: () => Promise<User | null>;
  ensureBackendUser: (username: string) => Promise<void>;
  syncBackendUser: () => Promise<boolean>;
  verifyBackendUser: () => Promise<void>;
  isVerified: boolean;
  isUserVerified: (inputUser?: User | null) => boolean;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

const trustedProviders = new Set(
  (import.meta.env.VITE_TRUSTED_AUTH_PROVIDERS || "google.com,password")
    .split(",")
    .map((value: string) => value.trim())
    .filter(Boolean),
);

const getProviderIds = (inputUser: User | null) =>
  inputUser?.providerData?.map((provider) => provider.providerId) ?? [];

const isTrustedProvider = (inputUser: User | null) =>
  getProviderIds(inputUser).some((provider) => trustedProviders.has(provider));

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  const createUser = useCreateBackendUser();
  const syncUser = useSyncBackendUser();
  const verifyUser = useVerifyBackendUser();
  const storeOAuthToken = useStoreOAuthToken();

  useEffect(() => {
    console.log("[roam-auth] AuthProvider mount", {
      href: window.location.href,
      path: window.location.pathname,
      hash: window.location.hash || "(empty)",
      search: window.location.search || "(empty)",
    });
    let unsubscribe: (() => void) | undefined;
    const setupListener = () => {
      unsubscribe = onAuthStateChanged(firebaseAuth, (nextUser) => {
        console.log("[roam-auth] onAuthStateChanged", nextUser?.uid ?? "null");
        setUser(nextUser);
        setLoading(false);
      });
    };
    console.log("[roam-auth] calling getRedirectResult");
    getRedirectResult(firebaseAuth)
      .then((result) => {
        console.log("[roam-auth] getRedirectResult done", result?.user?.uid ?? "no user");
        if (result) {
          const credential = GoogleAuthProvider.credentialFromResult(result);
          const accessToken = credential?.accessToken;
          if (accessToken) {
            const sts = (result.user as { stsTokenManager?: { expirationTime?: number } })?.stsTokenManager;
            const expiresAt = sts?.expirationTime
              ? new Date(sts.expirationTime).toISOString()
              : null;
            storeOAuthToken.mutate(
              { accessToken, expiresAt },
              { onError: () => {} }
            );
          }
        }
        setupListener();
      })
      .catch((err) => {
        console.warn("[roam-auth] getRedirectResult error", err);
        setupListener();
      });
    return () => unsubscribe?.();
  }, [storeOAuthToken]);

  const isUserVerified = (inputUser: User | null = user) => {
    return Boolean(
      inputUser && (inputUser.emailVerified || isTrustedProvider(inputUser)),
    );
  };

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      loading,
      isVerified: isUserVerified(user),
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
        // signInWithRedirect is broken on localhost (Firebase bug: HTTPS/HTTP mismatch).
        // Use popup for local dev; redirect for production. COOP header allows popups.
        if (import.meta.env.DEV) {
          console.log("[roam-auth] signInWithPopup (local dev)");
          const result = await signInWithPopup(firebaseAuth, provider);
          const credential = GoogleAuthProvider.credentialFromResult(result);
          const accessToken = credential?.accessToken;
          if (accessToken) {
            const sts = (result.user as { stsTokenManager?: { expirationTime?: number } })?.stsTokenManager;
            const expiresAt = sts?.expirationTime
              ? new Date(sts.expirationTime).toISOString()
              : null;
            storeOAuthToken.mutate(
              { accessToken, expiresAt },
              { onError: () => {} }
            );
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
        setUser(firebaseAuth.currentUser);
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
      },
      syncBackendUser: async () => {
        return await syncUser.mutateAsync();
      },
      verifyBackendUser: async () => {
        await verifyUser.mutateAsync();
      },
    }),
    [user, loading, createUser, syncUser, verifyUser, storeOAuthToken],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
