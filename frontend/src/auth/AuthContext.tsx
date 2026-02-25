import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import {
  GoogleAuthProvider,
  User,
  createUserWithEmailAndPassword,
  getIdToken,
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

const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";
const trustedProviders = new Set(
  (import.meta.env.VITE_TRUSTED_AUTH_PROVIDERS || "google.com,password")
    .split(",")
    .map((value: string) => value.trim())
    .filter(Boolean),
);

type ApiError = {
  status: number;
  message: string;
};

const readErrorMessage = async (response: Response) => {
  try {
    const data = await response.json();
    return data?.detail || "Request failed";
  } catch {
    return "Request failed";
  }
};

const getProviderIds = (inputUser: User | null) =>
  inputUser?.providerData?.map((provider) => provider.providerId) ?? [];

const isTrustedProvider = (inputUser: User | null) =>
  getProviderIds(inputUser).some((provider) => trustedProviders.has(provider));

const resolveUsername = (inputUser: User | null, usernameOverride?: string) => {
  if (usernameOverride?.trim()) {
    return usernameOverride.trim();
  }
  if (inputUser?.displayName) {
    return inputUser.displayName.replace(/\s+/g, "").toLowerCase();
  }
  if (inputUser?.email) {
    return inputUser.email.split("@")[0];
  }
  return `user-${Date.now()}`;
};

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

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

  const apiFetch = async (path: string, options?: RequestInit) => {
    const currentUser = firebaseAuth.currentUser;
    if (!currentUser) {
      throw new Error("No authenticated user");
    }
    const token = await getIdToken(currentUser, true);
    const response = await fetch(`${apiBaseUrl}${path}`, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
        ...(options?.headers || {}),
      },
    });
    if (!response.ok) {
      const message = await readErrorMessage(response);
      throw { status: response.status, message } as ApiError;
    }
    if (response.status === 204) {
      return null;
    }
    return response.json();
  };

  const ensureBackendUserMutation = useMutation({
    mutationFn: async (username: string) => {
      const trimmedUsername = username.trim();
      if (!trimmedUsername) {
        throw new Error("Username is required");
      }
      const currentUser = firebaseAuth.currentUser;
      const payload = {
        username: trimmedUsername,
        email: currentUser?.email || undefined,
        displayName: currentUser?.displayName || undefined,
        photoUrl: currentUser?.photoURL || undefined,
      };
      await apiFetch("/api/users", {
        method: "POST",
        body: JSON.stringify(payload),
      });
    },
  });

  const syncBackendUserMutation = useMutation({
    mutationFn: async () => {
      try {
        await apiFetch("/api/me");
        return true;
      } catch (error) {
        const apiError = error as ApiError;
        if (apiError.status === 404) {
          return false;
        }
        if (apiError.status === 403) {
          return true;
        }
        throw apiError;
      }
    },
  });

  const verifyBackendUserMutation = useMutation({
    mutationFn: async () => {
      await apiFetch("/api/users/verify", { method: "POST" });
    },
  });

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
        await ensureBackendUserMutation.mutateAsync(username);
      },
      syncBackendUser: async () => {
        return await syncBackendUserMutation.mutateAsync();
      },
      verifyBackendUser: async () => {
        await verifyBackendUserMutation.mutateAsync();
      },
    }),
    [
      user,
      loading,
      ensureBackendUserMutation,
      syncBackendUserMutation,
      verifyBackendUserMutation,
    ],
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
