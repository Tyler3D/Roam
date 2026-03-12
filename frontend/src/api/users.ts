import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { User, UserUpdate } from "@/models/user";

export const userKeys = {
  me: ["me"] as const,
  search: (q: string) => ["users", "search", q] as const,
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
    enabled: query.length >= 1,
  });
}
