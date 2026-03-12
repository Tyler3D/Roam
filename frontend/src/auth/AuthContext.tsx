import { createContext, useContext, useEffect, useMemo, useState } from "react";
import {
  GoogleAuthProvider,
  User,
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  reload,
  sendPasswordResetEmail,
  sendEmailVerification,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
} from "firebase/auth";

import { firebaseAuth } from "@/auth/firebase";
import { ROAM_DOMAIN } from "@/utils/util";
import { useCreateBackendUser, useSyncBackendUser, useVerifyBackendUser } from "@/api/auth";

type AuthContextValue = {
  user: User | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<User>;
  signUp: (email: string, password: string) => Promise<User>;
  signInWithGoogle: () => Promise<User>;
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

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(firebaseAuth, (nextUser) => {
      setUser(nextUser);
      setLoading(false);
    });
    return unsubscribe;
  }, []);

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
        const credential = await signInWithPopup(firebaseAuth, provider);
        return credential.user;
      },
      signOutUser: async () => {
        await signOut(firebaseAuth);
      },
      sendVerificationEmail: async () => {
        if (!firebaseAuth.currentUser) {
          throw new Error("No authenticated user");
        }
        const redirectUrl = `${ROAM_DOMAIN}/verify`;
        console.info("Sending verification email", {
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
    [user, loading, createUser, syncUser, verifyUser],
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
