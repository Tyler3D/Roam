import { useState } from "react";
import { usePlans } from "@/api/plans";
import { Spinner } from "@/components/ui/spinner";
import { EmptyState } from "@/components/ui/empty-state";
import PlanCard from "@/components/PlanCard";
import type { Plan } from "@/models/plan";

type TabId = "upcoming" | "past" | "calendar";

export default function PlansView() {
  const { data: plans = [], isLoading } = usePlans();

  const now = new Date();
  const upcoming = plans
    .filter(
      (p) =>
        p.status === "confirmed" &&
        p.scheduledAt &&
        new Date(p.scheduledAt) >= now
    )
    .sort((a, b) => new Date(a.scheduledAt!).getTime() - new Date(b.scheduledAt!).getTime());
  const past = plans
    .filter(
      (p) =>
        (p.status === "confirmed" || p.status === "completed") &&
        p.scheduledAt &&
        new Date(p.scheduledAt) < now
    )
    .sort((a, b) => new Date(b.scheduledAt!).getTime() - new Date(a.scheduledAt!).getTime());

  const [activeTab, setActiveTab] = useState<TabId>("upcoming");

  if (isLoading) {
    return (
      <div className="text-center py-[60px]">
        <Spinner text="loading plans..." />
      </div>
    );
  }

  if (plans.length === 0) {
    return (
      <div className="max-w-[480px] mx-auto pt-5 px-4">
        <EmptyState
          icon="📋"
          title="no plans yet"
          subtitle="promote an idea to create your first plan"
        />
      </div>
    );
  }

  const tabs: { id: TabId; label: string; count: number }[] = [
    { id: "upcoming", label: "Upcoming", count: upcoming.length },
    { id: "past", label: "Past", count: past.length },
    { id: "calendar", label: "Calendar", count: 0 },
  ];

  const list =
    activeTab === "upcoming"
      ? upcoming
      : activeTab === "past"
        ? past
        : [];

  return (
    <div className="max-w-[480px] mx-auto pt-5 px-4">
      <div className="flex gap-2 mb-4 overflow-x-auto pb-1">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`shrink-0 font-mono text-[10px] tracking-[1.5px] uppercase px-3 py-2 rounded-lg border transition-colors ${
              activeTab === tab.id
                ? "border-roam-logan-deep bg-roam-lavender text-roam-logan-deep"
                : "border-roam-logan/20 text-roam-text-mid hover:border-roam-logan/40"
            }`}
          >
            {tab.label}
            {tab.count > 0 && tab.id !== "calendar" && (
              <span className="ml-1.5 opacity-70">· {tab.count}</span>
            )}
          </button>
        ))}
      </div>

      {activeTab === "calendar" ? (
        <p className="font-mono text-[11px] text-roam-text-muted">
          Calendar view coming soon
        </p>
      ) : list.length === 0 ? (
        <p className="font-mono text-[11px] text-roam-text-muted">
          No {activeTab} plans
        </p>
      ) : (
        <div className="flex flex-col gap-2.5">
          {list.map((plan: Plan, i: number) => (
            <div key={plan.id} className={`anim d${Math.min(i + 1, 6)}`}>
              <PlanCard plan={plan} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
