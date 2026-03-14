import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { formatDuration } from "@/lib/duration";
import { Spinner } from "@/components/ui/spinner";
import { Avatar } from "@/components/ui/avatar-roam";
import { FriendSearch } from "@/components/FriendSearch";
import {
  usePlan,
  useUpdatePlan,
  useSuggestSlots,
  useCreateCalendarEvent,
  useAddPlanMember,
} from "@/api/plans";
import { useMe } from "@/api/users";
import type { Plan } from "@/models/plan";
import type { User } from "@/models/user";

type Slot = { start: string; end: string; label: string };

function formatSlotLabel(iso: string): string {
  try {
    const d = new Date(iso);
    const now = new Date();
    const tomorrow = new Date(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    const dayStr =
      d.toDateString() === now.toDateString()
        ? "Today"
        : d.toDateString() === tomorrow.toDateString()
          ? "Tomorrow"
          : d.toLocaleDateString("en-US", {
              weekday: "short",
              month: "short",
              day: "numeric",
            });
    return `${dayStr} · ${d.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
    })}`;
  } catch {
    return "";
  }
}

export default function PlanOverview() {
  const { planId } = useParams<{ planId: string }>();
  const navigate = useNavigate();
  const { data: plan, isLoading } = usePlan(planId ?? "");
  const { data: me } = useMe();
  const updatePlan = useUpdatePlan();
  const suggestSlots = useSuggestSlots();
  const createCalendar = useCreateCalendarEvent();
  const addMember = useAddPlanMember(planId ?? "");

  const [showSlotPicker, setShowSlotPicker] = useState(false);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleDraft, setTitleDraft] = useState("");
  const [confirmCancel, setConfirmCancel] = useState(false);

  if (!planId) {
    return (
      <div className="page-center">
        <span className="font-mono text-[13px] text-roam-text">invalid plan</span>
      </div>
    );
  }

  if (isLoading || !plan) {
    return (
      <div className="page-center">
        <Spinner />
      </div>
    );
  }

  const isDraft = plan.status === "draft";
  const isConfirmed = plan.status === "confirmed";
  const isCompleted = plan.status === "completed";
  const isCancelled = plan.status === "cancelled";
  const isCreator = me?.id === plan.creatorId;

  function fetchSlots() {
    setShowSlotPicker(true);
    suggestSlots.mutate(planId, {
      onSuccess: (data) => setSlots((data ?? []) as Slot[]),
    });
  }

  function handleConfirmPlan() {
    if (!plan.scheduledAt) return;
    updatePlan.mutate({
      id: planId,
      data: { status: "confirmed" },
    });
  }

  function handleReopenDraft() {
    updatePlan.mutate({
      id: planId,
      data: { status: "draft", scheduledAt: null },
    });
  }

  function handleCancelPlan() {
    updatePlan.mutate(
      { id: planId, data: { status: "cancelled" } },
      {
        onSuccess: () => {
          setConfirmCancel(false);
          if (plan.ideaId) navigate(`/ideas/${plan.ideaId}`);
          else navigate("/app");
        },
      }
    );
  }

  function handleReplan() {
    if (plan.ideaId) navigate(`/ideas/${plan.ideaId}`);
    else navigate("/app");
  }

  function saveTitle() {
    if (titleDraft.trim() && titleDraft !== plan.title) {
      updatePlan.mutate({ id: planId, data: { title: titleDraft.trim() } });
    }
    setEditingTitle(false);
  }

  return (
    <div className="max-w-[480px] mx-auto pt-5 px-4 pb-24">
      <button
        onClick={() => (plan.ideaId ? navigate(`/ideas/${plan.ideaId}`) : navigate("/app"))}
        className="font-mono text-[11px] text-roam-logan-deep mb-4 bg-transparent border-none cursor-pointer"
      >
        ← back
      </button>

      {/* Header */}
      <div className="mb-6">
        {editingTitle && isDraft && isCreator ? (
          <input
            value={titleDraft}
            onChange={(e) => setTitleDraft(e.target.value)}
            onBlur={saveTitle}
            onKeyDown={(e) => e.key === "Enter" && saveTitle()}
            autoFocus
            className="font-display text-[22px] text-roam-text w-full bg-transparent border-b border-roam-logan/30 outline-none"
          />
        ) : (
          <h1
            className="font-display text-[22px] text-roam-text leading-tight m-0"
            onDoubleClick={() => isDraft && isCreator && (setTitleDraft(plan.title), setEditingTitle(true))}
          >
            {plan.title}
          </h1>
        )}
        <div className="flex items-center gap-2 mt-2 flex-wrap">
          <span className="font-mono text-[10px] tracking-[1.5px] uppercase text-roam-text-muted">
            {isDraft && "Draft · Pick a time"}
            {isConfirmed && "Confirmed"}
            {isCompleted && "Completed"}
            {isCancelled && "Cancelled"}
          </span>
          {plan.placeName && (
            <span className="font-mono text-[10px] text-roam-text-mid">📍 {plan.placeName}</span>
          )}
        </div>
      </div>

      {/* Time section */}
      <div className="mb-6">
        <p className="label-mono mb-2">Time</p>
        {isDraft ? (
          <>
            {!plan.scheduledAt ? (
              <>
                <p className="font-mono text-[11px] text-roam-text-muted mb-2">No time set</p>
                {!showSlotPicker ? (
                  <button
                    onClick={fetchSlots}
                    disabled={suggestSlots.isPending}
                    className="font-mono text-[11px] px-3 py-2 rounded-lg border border-roam-logan/20 text-roam-text-mid hover:border-roam-logan/40"
                  >
                    {suggestSlots.isPending ? "loading..." : "Suggest times →"}
                  </button>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {slots.map((slot) => (
                      <button
                        key={slot.start}
                        onClick={() =>
                          updatePlan.mutate({
                            id: planId,
                            data: { scheduledAt: slot.start },
                          })
                        }
                        disabled={updatePlan.isPending}
                        className="font-mono text-[10px] px-3 py-2 rounded-lg border border-roam-logan/20 text-roam-text-mid hover:border-roam-logan/40"
                      >
                        {slot.label}
                      </button>
                    ))}
                  </div>
                )}
              </>
            ) : (
              <div className="flex items-center gap-2">
                <span className="font-mono text-[11px] text-roam-text">
                  {formatSlotLabel(plan.scheduledAt)}
                </span>
                <button
                  onClick={fetchSlots}
                  disabled={suggestSlots.isPending}
                  className="font-mono text-[10px] text-roam-logan-deep"
                >
                  Change
                </button>
              </div>
            )}
            {plan.scheduledAt && (
              <button
                onClick={handleConfirmPlan}
                disabled={updatePlan.isPending}
                className="btn-primary mt-3 font-mono text-[11px] px-4 py-2 rounded-lg"
              >
                Confirm Plan
              </button>
            )}
          </>
        ) : (isConfirmed || isCompleted) && plan.scheduledAt ? (
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-mono text-[11px] text-roam-text">
              {formatSlotLabel(plan.scheduledAt)}
            </span>
            {isConfirmed && (
              <button
                onClick={() =>
                  createCalendar.mutate(
                    {
                      planId,
                      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                    },
                    {
                      onSuccess: (res: { eventLink?: string; gcalLink?: string }) => {
                        const url = res.eventLink ?? res.gcalLink;
                        if (url) window.open(url, "_blank");
                      },
                    }
                  )
                }
                disabled={createCalendar.isPending}
                className="font-mono text-[10px] px-3 py-2 rounded-lg border border-roam-logan/20 text-roam-text-mid hover:border-roam-logan/40"
              >
                {createCalendar.isPending ? "..." : "📅 Add to Calendar"}
              </button>
            )}
          </div>
        ) : isCancelled && plan.scheduledAt ? (
          <span className="font-mono text-[11px] text-roam-text-muted">
            {formatSlotLabel(plan.scheduledAt)}
          </span>
        ) : null}
      </div>

      {/* Members */}
      <div className="mb-6">
        <p className="label-mono mb-2">Members</p>
        <div className="flex flex-wrap gap-2 mb-2">
          {plan.members?.map((m) => (
            <div
              key={m.id}
              className={`member-chip ${m.rsvpStatus === "accepted" ? "bg-roam-green/60 border border-roam-green-deep/[0.22]" : "bg-roam-lavender/50 border border-roam-logan/20"}`}
            >
              <Avatar name={m.firstName ?? ""} size={22} />
              <span className="font-mono text-[10px] text-roam-text-mid">
                {m.firstName} {m.lastName}
              </span>
              <span
                className={`font-mono text-[8px] ${m.rsvpStatus === "accepted" ? "text-roam-green-deep" : "text-roam-text-muted"}`}
              >
                {m.rsvpStatus}
              </span>
            </div>
          ))}
        </div>
        {isDraft && isCreator && (
          <FriendSearch
            onSelect={(u: User) => addMember.mutate(u.id)}
            excludeIds={plan.members?.map((m) => String(m.userId)) ?? []}
            placeholder="search to add..."
          />
        )}
      </div>

      {/* Tasks placeholder - no API yet */}
      {(isDraft || isConfirmed || isCompleted) && (
        <div className="mb-6">
          <p className="label-mono mb-2">Tasks</p>
          <p className="font-mono text-[11px] text-roam-text-muted">No tasks yet</p>
        </div>
      )}

      {/* Actions */}
      <div className="pt-4 border-t border-roam-logan/10 space-y-2">
        {isConfirmed && isCreator && (
          <button
            onClick={handleReopenDraft}
            disabled={updatePlan.isPending}
            className="font-mono text-[11px] text-roam-logan-deep bg-transparent border-none cursor-pointer block"
          >
            Reopen as Draft
          </button>
        )}
        {(isDraft || isConfirmed || isCompleted) && isCreator && (
          <>
            {!confirmCancel ? (
              <button
                onClick={() => setConfirmCancel(true)}
                className="font-mono text-[11px] text-roam-error bg-transparent border-none cursor-pointer block"
              >
                Cancel Plan
              </button>
            ) : (
              <div className="flex items-center gap-2">
                <span className="font-mono text-[11px] text-roam-text-muted">Cancel this plan?</span>
                <button
                  onClick={handleCancelPlan}
                  className="font-mono text-[11px] text-roam-error"
                >
                  Yes
                </button>
                <button
                  onClick={() => setConfirmCancel(false)}
                  className="font-mono text-[11px] text-roam-text-muted"
                >
                  No
                </button>
              </div>
            )}
          </>
        )}
        {isCancelled && (
          <button
            onClick={handleReplan}
            className="btn-primary font-mono text-[11px] px-4 py-2 rounded-lg"
          >
            Replan from idea →
          </button>
        )}
        {isCompleted && plan.rating == null && isCreator && (
          <div className="pt-2">
            <p className="label-mono mb-2">Rate this plan</p>
            <div className="flex gap-1">
              {[1, 2, 3, 4, 5].map((star) => (
                <button
                  key={star}
                  onClick={() =>
                    updatePlan.mutate({
                      id: planId,
                      data: { rating: star },
                    })
                  }
                  className="font-mono text-[18px] text-roam-logan-deep"
                >
                  ★
                </button>
              ))}
            </div>
          </div>
        )}
        {isCompleted && plan.rating != null && (
          <p className="font-mono text-[11px] text-roam-text-muted">
            Rated {plan.rating} / 5
          </p>
        )}
      </div>
    </div>
  );
}
