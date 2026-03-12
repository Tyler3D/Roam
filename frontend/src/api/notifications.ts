import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { Notification } from "@/models/notification";

export const notificationKeys = {
  all: ["notifications"] as const,
};

function fetchNotifications() {
  return request<Notification[]>("/api/notifications");
}

function markNotificationRead(id: string) {
  return request<Notification>(`/api/notifications/${id}/read`, { method: "POST" });
}

function markAllNotificationsRead() {
  return request<void>("/api/notifications/read-all", { method: "POST" });
}

export function useNotifications() {
  return useQuery({
    queryKey: notificationKeys.all,
    queryFn: fetchNotifications,
  });
}

export function useUnreadCount() {
  const { data } = useNotifications();
  return data?.filter((n) => !n.isRead).length ?? 0;
}

export function useMarkNotificationRead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: markNotificationRead,
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: notificationKeys.all });
      const prev = qc.getQueryData<Notification[]>(notificationKeys.all);
      qc.setQueryData<Notification[]>(notificationKeys.all, (old) =>
        old?.map((n) => (n.id === id ? { ...n, isRead: true } : n))
      );
      return { prev };
    },
    onError: (_err, _id, ctx) => {
      if (ctx?.prev) qc.setQueryData(notificationKeys.all, ctx.prev);
    },
  });
}

export function useMarkAllNotificationsRead() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: markAllNotificationsRead,
    onMutate: async () => {
      await qc.cancelQueries({ queryKey: notificationKeys.all });
      const prev = qc.getQueryData<Notification[]>(notificationKeys.all);
      qc.setQueryData<Notification[]>(notificationKeys.all, (old) =>
        old?.map((n) => ({ ...n, isRead: true }))
      );
      return { prev };
    },
    onError: (_err, _vars, ctx) => {
      if (ctx?.prev) qc.setQueryData(notificationKeys.all, ctx.prev);
    },
  });
}
