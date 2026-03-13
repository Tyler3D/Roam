import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request, requestNoAuth } from "@/lib/api";
import type { User, UserUpdate } from "@/models/user";

export const userKeys = {
  me: ["me"] as const,
  search: (q: string) => ["users", "search", q] as const,
  checkUsername: (u: string) => ["users", "check-username", u] as const,
};

function fetchMe() {
  return request<User>("/api/me");
}

function updateMe(data: UserUpdate) {
  return request<User>("/api/me", { method: "PUT", body: JSON.stringify(data) });
}

function searchUsers(q: string) {
  return request<User[]>(`/api/users/search?q=${encodeURIComponent(q)}`);
}

export function useMe(options?: { enabled?: boolean }) {
  return useQuery({
    queryKey: userKeys.me,
    queryFn: fetchMe,
    ...options,
  });
}

export function useUpdateMe() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: updateMe,
    onSuccess: () => qc.invalidateQueries({ queryKey: userKeys.me }),
  });
}

export function useSearchUsers(query: string) {
  return useQuery({
    queryKey: userKeys.search(query),
    queryFn: () => searchUsers(query),
    enabled: query.length >= 2,
  });
}

function checkUsername(username: string) {
  return requestNoAuth<{ available: boolean }>(
    `/api/users/check-username?username=${encodeURIComponent(username)}`
  );
}

export function useCheckUsername(username: string) {
  const trimmed = username.trim();
  return useQuery({
    queryKey: userKeys.checkUsername(trimmed),
    queryFn: () => checkUsername(trimmed),
    enabled: trimmed.length >= 1,
  });
}
