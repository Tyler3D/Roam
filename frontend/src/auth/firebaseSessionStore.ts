import { onAuthStateChanged, type User } from "firebase/auth";

import { firebaseAuth } from "@/auth/firebase";

/** [firebaseUser, initialAuthEventFired] — until the flag is true, null user is still “loading”. */
export type FirebaseSessionSnapshot = readonly [User | null, boolean];

let snapshot: FirebaseSessionSnapshot = [null, false];

const listeners = new Set<() => void>();

function emit() {
  for (const l of listeners) l();
}

function setSnapshot(next: FirebaseSessionSnapshot) {
  snapshot = next;
  emit();
}

onAuthStateChanged(firebaseAuth, (user) => {
  console.log("[roam-auth] onAuthStateChanged", user?.uid ?? "null");
  setSnapshot([user, true]);
});

export function subscribeToFirebaseSession(onStoreChange: () => void) {
  listeners.add(onStoreChange);
  return () => {
    listeners.delete(onStoreChange);
  };
}

export function getFirebaseSessionSnapshot(): FirebaseSessionSnapshot {
  return snapshot;
}

export function getServerFirebaseSessionSnapshot(): FirebaseSessionSnapshot {
  return [null, false];
}

/** Call after `reload()`; Firebase may not emit again, so push `currentUser` into the snapshot. */
export function syncFirebaseSessionFromCurrentUser() {
  setSnapshot([firebaseAuth.currentUser, true]);
}
