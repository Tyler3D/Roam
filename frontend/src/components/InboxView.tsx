import { useNotifications, useMarkNotificationRead, useMarkAllNotificationsRead } from "@/api/notifications";
import { EmptyState } from "@/components/ui/empty-state";
import type { Notification } from "@/models/notification";

const typeIcons: Record<string, string> = {
  invite_received: "💌",
  rsvp_accepted: "✅",
  rsvp_declined: "❌",
  task_assigned: "📋",
  plan_reminder: "⏰",
  rate_prompt: "⭐",
  friend_request: "🤝",
};

function timeAgo(iso: string): string {
  try {
    const diff = Date.now() - new Date(iso).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return "just now";
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  } catch { return ""; }
}

export default function InboxView() {
  const { data: notifications = [], isLoading } = useNotifications();
  const markRead = useMarkNotificationRead();
  const markAllRead = useMarkAllNotificationsRead();

  if (isLoading) {
    return (
      <div className="max-w-[480px] mx-auto pt-5 px-4">
        <div className="anim text-center py-20">
          <span className="font-mono text-[11px] text-roam-text-muted">loading...</span>
        </div>
      </div>
    );
  }

  if (notifications.length === 0) {
    return (
      <div className="max-w-[480px] mx-auto pt-5 px-4">
        <EmptyState icon="📭" title="all clear" subtitle="new activity will show up here" />
      </div>
    );
  }

  const unreadCount = notifications.filter((n) => !n.isRead).length;

  return (
    <div className="max-w-[480px] mx-auto pt-5 px-4">
      {unreadCount > 0 && (
        <div className="flex justify-end mb-2.5">
          <button onClick={() => markAllRead.mutate()} className="font-mono text-[9px] tracking-[1.5px] uppercase text-roam-logan-deep bg-transparent border-none cursor-pointer py-1">
            mark all read
          </button>
        </div>
      )}
      <div className="flex flex-col gap-1.5">
        {notifications.map((n: Notification, i: number) => (
          <button
            key={n.id}
            onClick={() => !n.isRead && markRead.mutate(n.id)}
            className={`anim d${Math.min(i + 1, 6)} rounded-[14px] py-3.5 px-4 flex items-start gap-3 text-left w-full border ${
              n.isRead
                ? "bg-white/80 border-roam-logan/[0.12] cursor-default"
                : "bg-roam-surface border-roam-logan/25 cursor-pointer"
            }`}
          >
            <div className="w-8 h-8 rounded-[10px] bg-roam-lavender flex items-center justify-center shrink-0 text-base">
              {typeIcons[n.type] || "📬"}
            </div>
            <div className="flex-1 min-w-0">
              <p className={`font-mono text-[11px] m-0 leading-snug ${n.isRead ? "text-roam-text-mid" : "text-roam-text"}`}>{n.title}</p>
              {n.body && <p className="font-mono text-[10px] text-roam-text-muted mt-1 mb-0">{n.body}</p>}
            </div>
            <div className="flex items-center gap-1.5 shrink-0">
              {!n.isRead && <div className="w-1.5 h-1.5 rounded-full bg-roam-logan-deep" />}
              <span className="font-mono text-[9px] text-roam-logan whitespace-nowrap">{timeAgo(n.createdAt)}</span>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
