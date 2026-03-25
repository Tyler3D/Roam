import { useDeferredValue, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useIdeas, useCreateIdea, useDeleteIdea, useInterpretIdea, usePromoteIdea } from "@/api/ideas";
import { usePlans } from "@/api/plans";
import { useSearchFriendsAndUsers } from "@/api/friends";
import { extractMentionQuery, replaceMention, type MentionResult } from "@/lib/mentions";
import { Avatar } from "@/components/ui/avatar-roam";
import { Spinner } from "@/components/ui/spinner";
import { EmptyState } from "@/components/ui/empty-state";
import IdeaCard from "@/components/IdeaCard";
import type { Plan } from "@/models/plan";
import type { User } from "@/models/user";

function formatNextUpLabel(plan: Plan): string {
  if (!plan.scheduledAt) return plan.title;
  try {
    const d = new Date(plan.scheduledAt);
    const dayStr = d.toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
    });
    const timeStr = d.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
    });
    return `${plan.placeName ? plan.placeName + " · " : ""}${dayStr} · ${timeStr}`;
  } catch {
    return plan.title;
  }
}

export default function IdeasView() {
  const navigate = useNavigate();
  const [input, setInput] = useState("");
  const [enrichingIds, setEnrichingIds] = useState<Set<string>>(new Set());
  const inputRef = useRef<HTMLInputElement>(null);

  const {
    data: ideas = [],
    isLoading,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
  } = useIdeas();
  const { data: plans = [] } = usePlans();

  const nextUp = useMemo(() => {
    const now = new Date();
    const confirmed = (plans as Plan[])
      .filter(
        (p) =>
          p.status === "confirmed" &&
          p.scheduledAt &&
          new Date(p.scheduledAt) >= now
      )
      .sort((a, b) => new Date(a.scheduledAt!).getTime() - new Date(b.scheduledAt!).getTime());
    return confirmed[0] ?? null;
  }, [plans]);
  const createIdea = useCreateIdea();
  const deleteIdea = useDeleteIdea();
  const interpretIdea = useInterpretIdea();
  const promoteIdea = usePromoteIdea();

  const rawMentionQuery = extractMentionQuery(input);
  const deferredMentionQuery = useDeferredValue(rawMentionQuery ?? "");

  const { data: mentionResults } = useSearchFriendsAndUsers(
    deferredMentionQuery.length >= 1 ? deferredMentionQuery : ""
  );

  const mentionDropdown: MentionResult[] = useMemo(() => {
    if (!mentionResults) return [];
    return mentionResults.friends
      .map((u: User) => ({
        id: u.id,
        firstName: u.firstName,
        lastName: u.lastName,
        isFriend: true,
      }))
      .slice(0, 6);
  }, [mentionResults]);

  function enrichIdea(id: string) {
    setEnrichingIds((prev) => new Set(prev).add(id));
    interpretIdea.mutate(id, {
      onSettled: () => {
        setEnrichingIds((prev) => {
          const next = new Set(prev);
          next.delete(id);
          return next;
        });
      },
    });
  }

  function handleCreate() {
    const title = input.trim();
    if (!title) return;
    setInput("");
    createIdea.mutate(title, {
      onSuccess: (idea) => enrichIdea(idea.id),
    });
    inputRef.current?.focus();
  }

  function handleDelete(id: string) {
    deleteIdea.mutate(id);
  }

  function handlePlanThis(id: string) {
    promoteIdea.mutate(id, {
      onSuccess: () => navigate("/app/plans"),
    });
  }

  function selectContact(mention: MentionResult) {
    setInput(replaceMention(input, mention.firstName));
    inputRef.current?.focus();
  }

  return (
    <div className="max-w-[480px] mx-auto pt-5 px-4 pb-36">
      {isLoading ? (
        <div className="text-center py-[60px]">
          <Spinner />
        </div>
      ) : (
        <>
          {nextUp && (
            <div className="mb-6">
              <p className="label-mono mb-2">Next Up</p>
              <button
                onClick={() => navigate(`/plans/${nextUp.id}`)}
                className="w-full text-left font-mono text-[11px] py-3 px-4 rounded-xl border border-roam-logan/20 bg-roam-surface hover:border-roam-logan/40 transition-colors"
              >
                → {formatNextUpLabel(nextUp)}
              </button>
            </div>
          )}

          {ideas.length === 0 ? (
            <EmptyState
              icon="🧭"
              title="capture your first idea"
              subtitle="what do you want to do?"
            />
          ) : (
            <>
              <p className="label-mono mb-2">Your Ideas</p>
            <div className="flex flex-col gap-2.5">
              {ideas.map((idea, i) => (
            <div key={idea.id} className={`anim d${Math.min(i + 1, 6)}`}>
              <IdeaCard
                idea={idea}
                onDelete={handleDelete}
                onPlanThis={handlePlanThis}
                enriching={enrichingIds.has(idea.id)}
              />
            </div>
          ))}
              {hasNextPage && (
                <button
                  type="button"
                  className="font-mono text-[10px] tracking-[1px] uppercase text-roam-logan-deep border border-roam-logan/25 rounded-xl py-2.5 px-4 bg-white/80 hover:bg-roam-lavender/30 disabled:opacity-50"
                  onClick={() => fetchNextPage()}
                  disabled={isFetchingNextPage}
                >
                  {isFetchingNextPage ? "loading…" : "load more"}
                </button>
              )}
            </div>
            </>
          )}
        </>
      )}

      <div className="glass-bar bottom-[60px] border-t px-4 py-2.5 z-40 -mx-4">
        <div className="max-w-[480px] mx-auto relative">
          {rawMentionQuery !== null && (
            <div className="absolute bottom-[calc(100%+6px)] left-0 right-0 bg-white/[0.98] border border-roam-logan/30 rounded-xl shadow-dropdown overflow-hidden z-50">
              {mentionDropdown.map((mention, idx) => (
                <button
                  key={mention.id}
                  onMouseDown={(e) => {
                    e.preventDefault();
                    selectContact(mention);
                  }}
                  className={`flex items-center gap-2.5 w-full py-2.5 px-3.5 bg-transparent border-none cursor-pointer text-left hover:bg-roam-lavender/40 ${
                    idx < mentionDropdown.length - 1 ? "border-b border-roam-logan/10" : ""
                  }`}
                >
                  <Avatar name={mention.firstName} size={28} />
                  <div>
                    <span className="font-mono text-xs text-roam-text">
                      {mention.firstName} {mention.lastName}
                    </span>
                  </div>
                </button>
              ))}
              <div className="py-2.5 px-3.5 border-t border-roam-logan/10">
                <p className="font-mono text-[9px] text-roam-text-muted">
                  Type a full username if you want to add them as a friend and invite at the same time
                </p>
              </div>
            </div>
          )}

          <input
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && mentionDropdown.length === 0) handleCreate();
              if (e.key === "Escape") setInput((v) => v.replace(/@\w*$/, ""));
            }}
            placeholder="what do you want to do?"
            className="w-full rounded-[13px] border border-roam-logan/25 bg-roam-surface font-notes text-[17px] text-roam-text outline-none shadow-card box-border focus:border-roam-logan-deep/40 focus:shadow-dropdown"
            style={{ padding: input ? "13px 80px 13px 18px" : "13px 18px" }}
          />
          {input && (
            <button
              onClick={handleCreate}
              className="btn-primary absolute right-2 top-1/2 -translate-y-1/2 text-[8px] tracking-[2px] shadow-none"
            >
              add →
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
