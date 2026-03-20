import type { User } from "firebase/auth";

export type AuthContextValue = {
  user: User | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<User>;
  signUp: (email: string, password: string) => Promise<User>;
  signInWithGoogle: () => Promise<void>;
  /** Google sign-in users only: OAuth redirect/popup with Calendar scope (optional; requires verified OAuth app for all users). */
  requestGoogleCalendarAccess: () => Promise<void>;
  signOutUser: () => Promise<void>;
  sendVerificationEmail: () => Promise<void>;
  resetPassword: (email: string) => Promise<void>;
  refreshUser: () => Promise<User | null>;
  ensureBackendUser: (username: string) => Promise<void>;
  verifyBackendUser: () => Promise<void>;
  isVerified: boolean;
  isUserVerified: (inputUser?: User | null) => boolean;
};
