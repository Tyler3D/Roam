import { getIdToken } from "firebase/auth";
import { firebaseAuth } from "@/auth/firebase";
import { ROAM_API_BASE } from "@/utils/util";

async function getHeaders(): Promise<Record<string, string>> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  const user = firebaseAuth.currentUser;
  if (user) {
    const token = await getIdToken(user, true);
    headers["Authorization"] = `Bearer ${token}`;
  }
  return headers;
}

export async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const headers = await getHeaders();
  const res = await fetch(`${ROAM_API_BASE}${path}`, {
    ...options,
    headers: { ...headers, ...(options?.headers || {}) },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({ detail: "Request failed" }));
    throw { status: res.status, message: body?.detail || "Request failed" };
  }
  if (res.status === 204) return null as T;
  return res.json();
}

export async function requestNoAuth<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${ROAM_API_BASE}${path}`, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options?.headers || {}) },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({ detail: "Request failed" }));
    throw { status: res.status, message: body?.detail || "Request failed" };
  }
  if (res.status === 204) return null as T;
  return res.json();
}

