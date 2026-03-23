import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";

const firebaseConfig = {
  // Use non-empty placeholders so local misconfig doesn't crash app bootstrap.
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || "local-dev-placeholder-api-key",
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || "localhost",
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || "local-dev",
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || "local-dev.appspot.com",
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || "000000000000",
  appId: import.meta.env.VITE_FIREBASE_APP_ID || "1:000000000000:web:localdev",
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID || "",
};

const hasMissingFirebaseConfig =
  !import.meta.env.VITE_FIREBASE_API_KEY ||
  !import.meta.env.VITE_FIREBASE_AUTH_DOMAIN ||
  !import.meta.env.VITE_FIREBASE_PROJECT_ID ||
  !import.meta.env.VITE_FIREBASE_APP_ID;

if (hasMissingFirebaseConfig) {
  console.warn(
    "[config] Missing VITE_FIREBASE_* values. App will load, but auth features require valid Firebase config."
  );
}

const firebaseApp = initializeApp(firebaseConfig);
export const firebaseAuth = getAuth(firebaseApp);

/**
 * Firebase Hosting on `*.web.app` + default `*.firebaseapp.com` authDomain breaks
 * signInWithRedirect / getRedirectResult in modern browsers (partitioned storage).
 * Set VITE_FIREBASE_AUTH_DOMAIN to your real site host (e.g. roam-alpha.web.app).
 * @see https://firebase.google.com/docs/auth/web/redirect-best-practices
 */
