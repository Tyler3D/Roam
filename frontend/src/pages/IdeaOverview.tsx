import { useParams, useNavigate } from "react-router-dom";
import { useEffect, useState } from "react";
import { formatDuration } from "@/lib/duration";
import { Spinner } from "@/components/ui/spinner";
import { LocationLink } from "@/components/ui/location-link";
import {
  useIdea,
  useSelectPlaceSuggestion,
  usePromoteIdea,
} from "@/api/ideas";
import { usePlans } from "@/api/plans";
import type { Plan } from "@/models/plan";
import {
  getIdeaOrchestrationSteps,
  getIdeaUncertainty,
  hasUnresolvedAmbiguity,
} from "@/lib/orchestration";
import { trackEvent } from "@/lib/telemetry";

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

function statusBadge(status: Plan["status"]): string {
  switch (status) {
    case "draft":
      return "draft";
    case "confirmed":
      return "confirmed";
    case "completed":
      return "completed";
    case "cancelled":
      return "cancelled";
    default:
      return status;
  }
}

export default function IdeaOverview() {
  const { ideaId } = useParams<{ ideaId: string }>();
  const navigate = useNavigate();
  const { data: idea, isLoading } = useIdea(ideaId);
  const { data: plansForIdea = [] } = usePlans(ideaId);
  const selectPlace = useSelectPlaceSuggestion();
  const promoteIdea = usePromoteIdea();
  const [ackAmbiguity, setAckAmbiguity] = useState(false);
  const [inviteesDraft, setInviteesDraft] = useState("");
  const [taskAssignmentsDraft, setTaskAssignmentsDraft] = useState("");
  const [searchQueryDraft, setSearchQueryDraft] = useState("");

  if (!ideaId) {
    return (
      <div className="page-center">
        <span className="font-mono text-[13px] text-roam-text">invalid idea</span>
      </div>
    );
  }

  if (isLoading || !idea) {
    return (
      <div className="page-center">
        <Spinner />
      </div>
    );
  }

  const currentIdea = idea;
  const pr = currentIdea.pipelineResult;
  const minutes = pr?.estimatedMinutes ?? 60;
  const category = pr?.category;
  const tags = (pr?.rawOutput as { tags?: string[] } | undefined)?.tags ?? [];
  const displayTitle = currentIdea.displayName ?? pr?.refinedTitle ?? currentIdea.title;
  const uncertainty = getIdeaUncertainty(currentIdea);
  const requiresConfirmation = hasUnresolvedAmbiguity(currentIdea);
  const steps = getIdeaOrchestrationSteps(currentIdea);
  const raw = (pr?.rawOutput as Record<string, unknown> | undefined) ?? {};
  const proposedInvitees = ((raw.inviteesProposed as string[] | undefined) ?? (raw.invitees as string[] | undefined) ?? []);
  const proposedTaskAssignments =
    (raw.taskAssignmentsProposed as string | undefined) ??
    (raw.taskAssignments as string | undefined) ??
    "";
  const proposedSearchQuery = (raw.searchQuery as string | undefined) ?? "";

  useEffect(() => {
    if (!requiresConfirmation) return;
    setInviteesDraft(proposedInvitees.join(", "));
    setTaskAssignmentsDraft(proposedTaskAssignments);
    setSearchQueryDraft(proposedSearchQuery);
    trackEvent("idea_ambiguity_viewed", { ideaId: currentIdea.id });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentIdea.id, requiresConfirmation]);

  function handlePlanThis() {
    const confirmedInvitees = inviteesDraft
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    promoteIdea.mutate({
      id: currentIdea.id,
      payload: {
        confirmedInvitees,
        confirmedTaskAssignments: taskAssignmentsDraft || null,
        confirmedSearchQuery: searchQueryDraft || null,
        ambiguityAcknowledged: requiresConfirmation ? ackAmbiguity : true,
      },
    }, {
      onSuccess: (plan: Plan) => {
        trackEvent("idea_promoted", {
          ideaId: currentIdea.id,
          hadAmbiguity: requiresConfirmation,
          ambiguityAcknowledged: ackAmbiguity,
        });
        navigate(`/plans/${plan.id}`);
      },
    });
  }

  return (
    <div className="max-w-[480px] mx-auto pt-5 px-4 pb-24">
      <button
        onClick={() => navigate("/app")}
        className="font-mono text-[11px] text-roam-logan-deep mb-4 bg-transparent border-none cursor-pointer"
      >
        ← back
      </button>

      <div className="mb-6">
        <h1 className="font-display text-[22px] text-roam-text leading-tight m-0">
          {displayTitle}
        </h1>
        <div className="flex items-center gap-2 mt-2 flex-wrap">
          {category && (
            <span className="font-mono text-[10px] text-roam-text-muted">
              {category === "food-drink" || category === "restaurant"
                ? "🍽"
                : category === "cafe"
                  ? "☕"
                  : category === "bar"
                    ? "🍸"
                    : category === "nightlife"
                      ? "🪩"
                      : category === "arts-culture"
                        ? "🎨"
                        : category === "outdoors"
                          ? "🌿"
                          : category === "fitness"
                            ? "💪"
                            : "📌"}
            </span>
          )}
          <span className="font-mono text-[10px] text-roam-text-muted">
            ~{formatDuration(minutes)}
          </span>
        </div>
      </div>

      {/* Suggested Places */}
      {steps.length > 0 && (
        <div className="mb-6">
          <p className="label-mono mb-2">Pipeline Steps</p>
          <div className="flex flex-col gap-1.5">
            {steps.map((step) => (
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

      {requiresConfirmation && (
        <div className="mb-6 p-3 rounded-lg border border-roam-error/40 bg-roam-error/5">
          <p className="label-mono mb-2">Confirmation Required</p>
          <p className="font-mono text-[11px] text-roam-text-mid mb-2">
            This interpretation has ambiguous fields. Review before promoting to plan.
          </p>
          {(uncertainty?.reasons ?? []).length > 0 && (
            <div className="font-mono text-[10px] text-roam-text-muted mb-2">
              {(uncertainty?.reasons ?? []).map((reason) => (
                <div key={reason}>- {reason}</div>
              ))}
            </div>
          )}
          <label className="font-mono text-[10px] text-roam-text-mid flex items-center gap-2">
            <input
              type="checkbox"
              checked={ackAmbiguity}
              onChange={(e) => {
                const checked = e.target.checked;
                setAckAmbiguity(checked);
                trackEvent("idea_ambiguity_ack_toggled", {
                  ideaId: currentIdea.id,
                  checked,
                });
              }}
            />
            I reviewed these ambiguities and want to continue
          </label>
          <div className="mt-3 flex flex-col gap-2">
            <label className="font-mono text-[10px] text-roam-text-mid">
              Invitees (comma-separated)
            </label>
            <input
              value={inviteesDraft}
              onChange={(e) => setInviteesDraft(e.target.value)}
              className="font-mono text-[11px] py-2 px-2.5 rounded-lg border border-roam-logan/20 bg-roam-surface"
            />
            <label className="font-mono text-[10px] text-roam-text-mid">Task assignments</label>
            <input
              value={taskAssignmentsDraft}
              onChange={(e) => setTaskAssignmentsDraft(e.target.value)}
              className="font-mono text-[11px] py-2 px-2.5 rounded-lg border border-roam-logan/20 bg-roam-surface"
            />
            <label className="font-mono text-[10px] text-roam-text-mid">Search query</label>
            <input
              value={searchQueryDraft}
              onChange={(e) => setSearchQueryDraft(e.target.value)}
              className="font-mono text-[11px] py-2 px-2.5 rounded-lg border border-roam-logan/20 bg-roam-surface"
            />
          </div>
        </div>
      )}

      <div className="mb-6">
        <p className="label-mono mb-2">Suggested Places</p>
        {pr?.placeSuggestions && pr.placeSuggestions.length > 1 ? (
          <div className="flex flex-col gap-1.5">
            {pr.placeSuggestions.map((s) => (
              <button
                key={s.id}
                onClick={() => selectPlace.mutate({ ideaId: currentIdea.id, suggestionId: s.id })}
                disabled={selectPlace.isPending}
                className={`font-mono text-[11px] text-left px-2.5 py-2 rounded-lg border transition-colors ${
                  s.isSelected
                    ? "border-roam-logan-deep bg-roam-lavender text-roam-logan-deep"
                    : "border-roam-logan/20 text-roam-text-mid hover:border-roam-logan/40"
                }`}
              >
                {s.placeName ?? s.rawName ?? "Unknown"} {s.isSelected ? "◉" : "○"}
              </button>
            ))}
          </div>
        ) : currentIdea.placeName ? (
          <LocationLink placeName={currentIdea.placeName} />
        ) : (
          <p className="font-mono text-[11px] text-roam-text-muted">No place selected</p>
        )}
      </div>

      {tags.length > 0 && (
        <div className="flex gap-1.5 flex-wrap mb-6">
          {tags.map((tag) => (
            <span
              key={tag}
              className="font-mono text-[9px] bg-roam-lavender text-roam-logan-deep px-2.5 py-1 rounded-full"
            >
              {tag}
            </span>
          ))}
        </div>
      )}

      {currentIdea.notes && (
        <div className="mb-6">
          <p className="label-mono mb-1.5">Notes</p>
          <p className="font-notes text-[13px] text-roam-text-mid leading-relaxed m-0">
            {currentIdea.notes}
          </p>
        </div>
      )}

      {currentIdea.sourceUrl && (
        <div className="mb-6">
          <p className="label-mono mb-1.5">Saved From</p>
          <a
            href={currentIdea.sourceUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="font-mono text-[11px] text-roam-logan-deep underline"
          >
            {currentIdea.sourceUrl}
          </a>
        </div>
      )}

      {plansForIdea.length > 0 && (
        <div className="mb-6">
          <p className="label-mono mb-2">Plans from this Idea</p>
          <div className="flex flex-col gap-1.5">
            {plansForIdea.map((p: Plan) => (
              <button
                key={p.id}
                onClick={() => navigate(`/plans/${p.id}`)}
                className="font-mono text-[11px] text-left text-roam-text-mid py-2 px-2.5 rounded-lg border border-roam-logan/20 hover:border-roam-logan/40 transition-colors"
              >
                {p.title}
                {p.scheduledAt ? ` · ${formatSlotLabel(p.scheduledAt)}` : " · No time set"}
                <span className="ml-1.5 font-mono text-[9px] tracking-[1px] uppercase opacity-70">
                  · {statusBadge(p.status)}
                </span>
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="pt-4 border-t border-roam-logan/10">
        <button
          onClick={handlePlanThis}
          disabled={promoteIdea.isPending || (requiresConfirmation && !ackAmbiguity)}
          className="btn-primary w-full rounded-[11px] py-3 px-[18px] text-[11px] tracking-[2px] shadow-[0_2px_12px_rgba(74,64,112,0.2)]"
        >
          {promoteIdea.isPending ? "creating..." : "plan this →"}
        </button>
      </div>
    </div>
  );
}
