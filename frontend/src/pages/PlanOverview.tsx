import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
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
import {
  useTasks,
  useCreateTask,
  useUpdateTask,
  useDeleteTask,
} from "@/api/tasks";
import { useIdea } from "@/api/ideas";
import { useMe } from "@/api/users";
import type { User } from "@/models/user";
import { getIdeaOrchestrationSteps, getIdeaUncertainty, hasUnresolvedAmbiguity } from "@/lib/orchestration";

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
  const pid = planId ?? "";
  const { data: plan, isLoading } = usePlan(pid);
  const { data: me } = useMe();
  const { data: idea } = useIdea(plan?.ideaId ?? undefined);
  const updatePlan = useUpdatePlan();
  const suggestSlots = useSuggestSlots();
  const createCalendar = useCreateCalendarEvent();
  const addMember = useAddPlanMember(pid);
  const { data: tasks = [] } = useTasks(pid);
  const createTaskMutation = useCreateTask(pid);
  const updateTaskMutation = useUpdateTask(pid);
  const deleteTaskMutation = useDeleteTask(pid);

  const [showSlotPicker, setShowSlotPicker] = useState(false);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleDraft, setTitleDraft] = useState("");
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [confirmReschedule, setConfirmReschedule] = useState(false);
  const [taskDesc, setTaskDesc] = useState("");
  const [taskAssigneeId, setTaskAssigneeId] = useState("");

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
  const ideaHasAmbiguity = idea ? hasUnresolvedAmbiguity(idea) : false;
  const ideaUncertainty = idea ? getIdeaUncertainty(idea) : null;
  const ideaSteps = idea ? getIdeaOrchestrationSteps(idea) : [];

  function fetchSlots() {
    setShowSlotPicker(true);
    suggestSlots.mutate(pid, {
      onSuccess: (data) => setSlots((data ?? []) as Slot[]),
    });
  }

  function handleConfirmPlan() {
    if (!plan?.scheduledAt) return;
    updatePlan.mutate({
      id: pid,
      data: { status: "confirmed" },
    });
  }

  function handleCancelPlan() {
    const p = plan!;
    updatePlan.mutate(
      { id: pid, data: { status: "cancelled" } },
      {
        onSuccess: (updated) => {
          setConfirmCancel(false);
          setConfirmReschedule(false);
          if (updated.status === "cancelled") {
            if (p.ideaId) navigate(`/ideas/${p.ideaId}`);
            else navigate("/app");
          }
        },
      }
    );
  }

  function handleReplan() {
    const p = plan!;
    if (p.ideaId) navigate(`/ideas/${p.ideaId}`);
    else navigate("/app");
  }

  function saveTitle() {
    const p = plan!;
    if (titleDraft.trim() && titleDraft !== p.title) {
      updatePlan.mutate({ id: pid, data: { title: titleDraft.trim() } });
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

      {ideaSteps.length > 0 && (
        <div className="mb-6">
          <p className="label-mono mb-2">Interpretation Steps</p>
          <div className="flex flex-col gap-1.5">
            {ideaSteps.map((step) => (
              <div
                key={step.name}
                className="font-mono text-[10px] px-2.5 py-2 rounded-lg border border-roam-logan/20 text-roam-text-mid"
              >
                {step.status === "ok" ? "✓" : step.status === "error" ? "!" : "·"} {step.name}{" "}
                {typeof step.durationMs === "number" ? `(${step.durationMs}ms)` : ""}
              </div>
            ))}
          </div>
        </div>
      )}

      {ideaHasAmbiguity && isDraft && (
        <div className="mb-6 p-3 rounded-lg border border-roam-error/40 bg-roam-error/5">
          <p className="label-mono mb-2">Pending Ambiguities</p>
          <p className="font-mono text-[11px] text-roam-text-mid mb-2">
            This plan was created from an idea with unresolved interpretation ambiguity.
          </p>
          {(ideaUncertainty?.reasons ?? []).map((reason) => (
            <div key={reason} className="font-mono text-[10px] text-roam-text-muted">
              - {reason}
            </div>
          ))}
        </div>
      )}

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
                            id: pid,
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
                disabled={updatePlan.isPending || ideaHasAmbiguity}
                className="btn-primary mt-3 font-mono text-[11px] px-4 py-2 rounded-lg"
              >
                {ideaHasAmbiguity ? "Resolve ambiguity on idea first" : "Confirm Plan"}
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
                      planId: pid,
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

      {/* Tasks */}
      {(isDraft || isConfirmed || isCompleted) && (
        <div className="mb-6">
          <p className="label-mono mb-2">Tasks</p>
          {(tasks?.length ?? 0) > 0 ? (
            <div className="flex flex-col gap-1.5 mb-3">
              {tasks.map((task) => {
                const isAssignee = plan.members?.find((m) => m.id === task.assigneeId)?.userId === me?.id;
                const canComplete = isCreator || isAssignee;
                const canDelete = isCreator || isAssignee;
                return (
                  <div
                    key={task.id}
                    className="flex items-center gap-2 py-2 px-3 rounded-lg border border-roam-logan/20 bg-roam-surface"
                  >
                    <button
                      onClick={() =>
                        canComplete &&
                        updateTaskMutation.mutate({
                          taskId: task.id,
                          isCompleted: !task.isCompleted,
                        })
                      }
                      disabled={!canComplete || updateTaskMutation.isPending}
                      className="font-mono text-[14px] shrink-0 bg-transparent border-none cursor-pointer"
                    >
                      {task.isCompleted ? "☑" : "☐"}
                    </button>
                    <span
                      className={`font-mono text-[11px] flex-1 ${task.isCompleted ? "line-through text-roam-text-muted" : "text-roam-text"}`}
                    >
                      {task.description}
                    </span>
                    <span className="font-mono text-[10px] text-roam-text-muted shrink-0">
                      {task.assigneeFirstName}
                    </span>
                    {canDelete && (
                      <button
                        onClick={() => deleteTaskMutation.mutate(task.id)}
                        disabled={deleteTaskMutation.isPending}
                        className="font-mono text-[10px] text-roam-error bg-transparent border-none cursor-pointer shrink-0"
                      >
                        ✕
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          ) : (
            <p className="font-mono text-[11px] text-roam-text-muted mb-3">No tasks yet</p>
          )}
          {(isDraft || isConfirmed) && isCreator && (
            <div className="flex gap-2 flex-wrap">
              <input
                value={taskDesc}
                onChange={(e) => setTaskDesc(e.target.value)}
                placeholder="add a task..."
                className="font-mono text-[11px] flex-1 min-w-[120px] py-2 px-3 rounded-lg border border-roam-logan/20 bg-roam-surface"
              />
              <select
                value={taskAssigneeId}
                onChange={(e) => setTaskAssigneeId(e.target.value)}
                className="font-mono text-[11px] py-2 px-3 rounded-lg border border-roam-logan/20 bg-roam-surface"
              >
                <option value="">assign to</option>
                {plan.members?.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.firstName} {m.lastName}
                  </option>
                ))}
              </select>
              <button
                onClick={() => {
                  if (taskDesc.trim() && taskAssigneeId) {
                    createTaskMutation.mutate({
                      description: taskDesc.trim(),
                      assigneeId: taskAssigneeId,
                    });
                    setTaskDesc("");
                    setTaskAssigneeId("");
                  }
                }}
                disabled={!taskDesc.trim() || !taskAssigneeId || createTaskMutation.isPending}
                className="btn-primary font-mono text-[10px] px-3 py-2 rounded-lg"
              >
                Add
              </button>
            </div>
          )}
        </div>
      )}

      {/* Actions */}
      <div className="pt-4 border-t border-roam-logan/10 space-y-2">
        {(isDraft || isConfirmed || isCompleted) && isCreator && (
          <>
            {isConfirmed && !confirmReschedule && (
              <button
                onClick={() => setConfirmReschedule(true)}
                className="font-mono text-[11px] text-roam-logan-deep bg-transparent border-none cursor-pointer block"
              >
                Reschedule
              </button>
            )}
            {isConfirmed && confirmReschedule && (
              <div className="space-y-2">
                <p className="font-mono text-[11px] text-roam-text-muted">
                  This will notify all members that the plan needs a new time. Continue?
                </p>
                <div className="flex gap-2">
                  <button
                    onClick={handleCancelPlan}
                    className="font-mono text-[11px] text-roam-error"
                  >
                    Yes
                  </button>
                  <button
                    onClick={() => setConfirmReschedule(false)}
                    className="font-mono text-[11px] text-roam-text-muted"
                  >
                    No
                  </button>
                </div>
              </div>
            )}
            {isDraft && !confirmCancel && (
              <button
                onClick={() => setConfirmCancel(true)}
                className="font-mono text-[11px] text-roam-error bg-transparent border-none cursor-pointer block"
              >
                Cancel Plan
              </button>
            )}
            {isDraft && confirmCancel && (
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
            {isCompleted && !confirmCancel && (
              <button
                onClick={() => setConfirmCancel(true)}
                className="font-mono text-[11px] text-roam-error bg-transparent border-none cursor-pointer block"
              >
                Cancel Plan
              </button>
            )}
            {isCompleted && confirmCancel && (
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
                      id: pid,
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
