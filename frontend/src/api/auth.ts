import { useMutation } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { User as BackendUser, UserCreate } from "@/models/user";

export const backendUserGateQueryKey = (uid: string | undefined) =>
  ["backendUserGate", uid] as const;

function createBackendUser(payload: UserCreate) {
  return request<BackendUser>("/api/users", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export async function fetchBackendUserGate(): Promise<boolean> {
  try {
    await request<BackendUser>("/api/me");
    return true;
  } catch (error) {
    const apiError = error as { status: number; message: string };
    if (apiError.status === 404) return false;
    if (apiError.status === 403) return true;
    throw apiError;
  }
}

function verifyBackendUser() {
  return request<BackendUser>("/api/users/verify", { method: "POST" });
}

export function sendOAuthTokenToBackend(payload: {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: string | null;
}) {
  return request<{ ok: boolean }>("/api/users/oauth-token", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export function useStoreOAuthToken() {
  return useMutation({
    mutationFn: (payload: {
      accessToken: string;
      refreshToken?: string;
      expiresAt?: string | null;
    }) => sendOAuthTokenToBackend(payload),
  });
}

export function useCreateBackendUser() {
  return useMutation({ mutationFn: createBackendUser });
}

export function useVerifyBackendUser() {
  return useMutation({ mutationFn: () => verifyBackendUser() });
}
