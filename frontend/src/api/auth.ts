import { useMutation } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { User as BackendUser, UserCreate } from "@/models/user";

function createBackendUser(payload: UserCreate) {
  return request<BackendUser>("/api/users", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

async function syncBackendUser(): Promise<boolean> {
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

export function useCreateBackendUser() {
  return useMutation({ mutationFn: createBackendUser });
}

export function useSyncBackendUser() {
  return useMutation({ mutationFn: syncBackendUser });
}

export function useVerifyBackendUser() {
  return useMutation({ mutationFn: () => verifyBackendUser() });
}
