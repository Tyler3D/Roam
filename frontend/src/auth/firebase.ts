import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID,
};

const firebaseApp = initializeApp(firebaseConfig);
export const firebaseAuth = getAuth(firebaseApp);

/**
 * Firebase Hosting on `*.web.app` + default `*.firebaseapp.com` authDomain breaks
 * signInWithRedirect / getRedirectResult in modern browsers (partitioned storage).
 * Set VITE_FIREBASE_AUTH_DOMAIN to your real site host (e.g. roam-alpha.web.app).
 * @see https://firebase.google.com/docs/auth/web/redirect-best-practices
 */
if (typeof window !== "undefined") {
  console.log("[roam-auth] firebaseConfig", firebaseConfig);
}

