import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { Friendship, FriendSearchResult } from "@/models/friendship";

export const friendKeys = {
  all: ["friends"] as const,
  requests: ["friends", "requests"] as const,
  search: (q: string) => ["friends", "search", q] as const,
};

function fetchFriends() {
  return request<Friendship[]>("/api/friends");
}

function fetchFriendRequests() {
  return request<Friendship[]>("/api/friends/requests");
}

function sendFriendRequest(targetUserId: string) {
  return request<Friendship>("/api/friends/request", {
    method: "POST",
    body: JSON.stringify({ targetUserId }),
  });
}

function acceptFriendRequest(friendshipId: string) {
  return request<Friendship>(`/api/friends/${friendshipId}/accept`, { method: "POST" });
}

function removeFriendship(friendshipId: string) {
  return request<void>(`/api/friends/${friendshipId}`, { method: "DELETE" });
}

function searchFriendsAndUsers(q: string) {
  return request<FriendSearchResult>(
    `/api/friends/search?q=${encodeURIComponent(q)}`
  );
}

export function useFriends() {
  return useQuery({
    queryKey: friendKeys.all,
    queryFn: fetchFriends,
  });
}

export function useFriendRequests() {
  return useQuery({
    queryKey: friendKeys.requests,
    queryFn: fetchFriendRequests,
  });
}

export function useSendFriendRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: sendFriendRequest,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: friendKeys.all });
    },
  });
}

export function useAcceptFriendRequest() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: acceptFriendRequest,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: friendKeys.all });
      qc.invalidateQueries({ queryKey: friendKeys.requests });
    },
  });
}

export function useRemoveFriendship() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: removeFriendship,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: friendKeys.all });
    },
  });
}

export function useSearchFriendsAndUsers(query: string) {
  return useQuery({
    queryKey: friendKeys.search(query),
    queryFn: () => searchFriendsAndUsers(query),
    enabled: query.length >= 1,
  });
}
