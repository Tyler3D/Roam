import { useState, useEffect, useRef, useMemo } from "react";
import { useAuth } from "@/auth/AuthContext";
import { useIdeas, useCreateIdea, useDeleteIdea, useInterpretIdea, usePromoteIdea } from "@/api/ideas";
import { useUnreadCount } from "@/api/notifications";
import { useSearchFriendsAndUsers } from "@/api/friends";
import { extractMentionQuery, replaceMention, type MentionResult } from "@/lib/mentions";
import { Avatar } from "@/components/ui/avatar-roam";
import { Spinner } from "@/components/ui/spinner";
import { EmptyState } from "@/components/ui/empty-state";
import type { User } from "@/models/user";

import TopBar from "./TopBar";
import IdeaCard from "./IdeaCard";
import PlansView from "./PlansView";
import InboxView from "./InboxView";
import ProfileView from "./ProfileView";

type Tab = "home" | "plans" | "inbox" | "profile";

const TABS: { id: Tab; symbol: string; label: string }[] = [
  { id: "home",    symbol: "◌", label: "home" },
  { id: "plans",   symbol: "⊟", label: "plans" },
  { id: "inbox",   symbol: "◎", label: "inbox" },
  { id: "profile", symbol: "⊕", label: "profile" },
];

export default function Dashboard() {
  const { user } = useAuth();
  const [input, setInput] = useState("");
  const [enrichingIds, setEnrichingIds] = useState<Set<string>>(new Set());
  const [activeTab, setActiveTab] = useState<Tab>("home");
  const inputRef = useRef<HTMLInputElement>(null);

  const { data: ideas = [], isLoading } = useIdeas();
  const createIdea = useCreateIdea();
  const deleteIdea = useDeleteIdea();
  const interpretIdea = useInterpretIdea();
  const promoteIdea = usePromoteIdea();
  const unreadCount = useUnreadCount();

  const [debouncedMentionQuery, setDebouncedMentionQuery] = useState("");
  const mentionTimer = useRef<ReturnType<typeof setTimeout>>();

  const rawMentionQuery = extractMentionQuery(input);

  useEffect(() => {
    if (rawMentionQuery && rawMentionQuery.length >= 1) {
      if (mentionTimer.current) clearTimeout(mentionTimer.current);
      mentionTimer.current = setTimeout(() => {
        setDebouncedMentionQuery(rawMentionQuery);
      }, 200);
    } else {
      setDebouncedMentionQuery("");
      if (mentionTimer.current) clearTimeout(mentionTimer.current);
    }
    return () => { if (mentionTimer.current) clearTimeout(mentionTimer.current); };
  }, [rawMentionQuery]);

  const { data: mentionResults } = useSearchFriendsAndUsers(debouncedMentionQuery);

  const mentionDropdown: MentionResult[] = useMemo(() => {
    if (!mentionResults) return [];
    const friends = (mentionResults.friends ?? []).map((u: User) => ({
      id: u.id, firstName: u.firstName, lastName: u.lastName, isFriend: true,
    }));
    const others = (mentionResults.others ?? []).map((u: User) => ({
      id: u.id, firstName: u.firstName, lastName: u.lastName, isFriend: false,
    }));
    return [...friends, ...others].slice(0, 6);
  }, [mentionResults]);

  function enrichIdea(id: string) {
    setEnrichingIds((prev) => new Set(prev).add(id));
    interpretIdea.mutate(id, {
      onSettled: () => {
        setEnrichingIds((prev) => { const next = new Set(prev); next.delete(id); return next; });
      },
    });
  }

  function handleCreate() {
    const title = input.trim();
    if (!title) return;
    setInput("");
    setDebouncedMentionQuery("");
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
      onSuccess: () => setActiveTab("plans"),
    });
  }

  function selectContact(mention: MentionResult) {
    setInput(replaceMention(input, mention.firstName));
    setDebouncedMentionQuery("");
    inputRef.current?.focus();
  }

  const contentPb = activeTab === "home" ? 148 : 72;
  const userName = user?.displayName ?? "";
  const userImage = user?.photoURL ?? null;

  return (
    <div className="dot-grid h-dvh flex flex-col bg-roam-bg">
      <TopBar userName={userName} userImage={userImage} notificationCount={unreadCount} onNotificationClick={() => setActiveTab("inbox")} />

      <div className="flex-1 overflow-y-auto" style={{ paddingBottom: contentPb }}>
        <div className="max-w-[480px] mx-auto pt-5 px-4">
          {activeTab === "home" && (
            <>
              {isLoading ? (
                <div className="text-center py-[60px]"><Spinner /></div>
              ) : ideas.length === 0 ? (
                <EmptyState icon="🧭" title="no ideas yet" subtitle="type something below — roam finds the place & time" />
              ) : (
                <div className="flex flex-col gap-2.5">
                  {ideas.map((idea, i) => (
                    <div key={idea.id} className={`anim d${Math.min(i + 1, 6)}`}>
                      <IdeaCard idea={idea} onDelete={handleDelete} onPlanThis={handlePlanThis} enriching={enrichingIds.has(idea.id)} />
                    </div>
                  ))}
                </div>
              )}
            </>
          )}

          {activeTab === "plans" && <PlansView />}
          {activeTab === "inbox" && <InboxView />}
          {activeTab === "profile" && <ProfileView />}
        </div>
      </div>

      {activeTab === "home" && (
        <div className="glass-bar bottom-[60px] border-t px-4 py-2.5 z-40">
          <div className="max-w-[480px] mx-auto relative">
            {mentionDropdown.length > 0 && (
              <div className="absolute bottom-[calc(100%+6px)] left-0 right-0 bg-white/[0.98] border border-roam-logan/30 rounded-xl shadow-dropdown overflow-hidden z-50">
                {mentionDropdown.map((mention, idx) => (
                  <button key={mention.id} onMouseDown={(e) => { e.preventDefault(); selectContact(mention); }}
                    className={`flex items-center gap-2.5 w-full py-2.5 px-3.5 bg-transparent border-none cursor-pointer text-left hover:bg-roam-lavender/40 ${idx < mentionDropdown.length - 1 ? "border-b border-roam-logan/10" : ""}`}
                  >
                    <Avatar name={mention.firstName} size={28} />
                    <div>
                      <span className="font-mono text-xs text-roam-text">{mention.firstName} {mention.lastName}</span>
                      {mention.isFriend && <span className="font-mono text-[9px] text-roam-logan ml-1.5">friend</span>}
                    </div>
                  </button>
                ))}
              </div>
            )}

            <input ref={inputRef} value={input} onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && mentionDropdown.length === 0) handleCreate(); if (e.key === "Escape") setDebouncedMentionQuery(""); }}
              placeholder="what do you want to do?"
              className="w-full rounded-[13px] border border-roam-logan/25 bg-roam-surface font-notes text-[17px] text-roam-text outline-none shadow-card box-border focus:border-roam-logan-deep/40 focus:shadow-dropdown"
              style={{ padding: input ? "13px 80px 13px 18px" : "13px 18px" }}
            />
            {input && (
              <button onClick={handleCreate} className="btn-primary absolute right-2 top-1/2 -translate-y-1/2 text-[8px] tracking-[2px] shadow-none">
                add →
              </button>
            )}
          </div>
        </div>
      )}

      <div className="glass-bar bottom-0 h-[60px] border-t flex items-stretch z-50" style={{ background: "rgba(245,243,250,0.95)" }}>
        {TABS.map((tab) => {
          const isActive = activeTab === tab.id;
          return (
            <button key={tab.id} onClick={() => setActiveTab(tab.id)} className="flex-1 flex flex-col items-center justify-center gap-[3px] bg-transparent border-none cursor-pointer relative">
              {isActive && <div className="absolute top-1.5 w-1 h-1 rounded-full bg-roam-logan-deep" />}
              <span className={`font-mono text-[22px] leading-none ${isActive ? "text-roam-logan-deep" : "text-roam-logan"}`}>{tab.symbol}</span>
              <span className={`font-mono text-[11px] tracking-[1px] uppercase ${isActive ? "text-roam-logan-deep" : "text-roam-lav-deep"}`}>{tab.label}</span>
              {tab.id === "inbox" && unreadCount > 0 && (
                <div className="absolute top-2 right-[calc(50%-14px)] w-[7px] h-[7px] rounded-full bg-roam-notif-dot border-[1.5px] border-roam-bg/95" />
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
