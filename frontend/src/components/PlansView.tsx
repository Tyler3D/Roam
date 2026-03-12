import { usePlans } from "@/api/plans";
import { Spinner } from "@/components/ui/spinner";
import { EmptyState } from "@/components/ui/empty-state";
import type { Plan } from "@/models/plan";
import PlanCard from "./PlanCard";

export default function PlansView() {
  const { data: plans = [], isLoading } = usePlans();

  const now = new Date();
  const upcoming = plans.filter((p) => !p.scheduledAt || new Date(p.scheduledAt) >= now);
  const past = plans.filter((p) => p.scheduledAt && new Date(p.scheduledAt) < now);

  if (isLoading) {
    return <div className="text-center py-[60px]"><Spinner text="loading plans..." /></div>;
  }

  if (plans.length === 0) {
    return <EmptyState icon="📋" title="no plans yet" subtitle="promote an idea to create your first plan" />;
  }

  return (
    <div>
      {upcoming.length > 0 && (
        <>
          <p className="label-mono mb-3">upcoming</p>
          <div className="flex flex-col gap-2.5 mb-6">
            {upcoming.map((plan: Plan, i: number) => (
              <div key={plan.id} className={`anim d${Math.min(i + 1, 6)}`}>
                <PlanCard plan={plan} />
              </div>
            ))}
          </div>
        </>
      )}
      {past.length > 0 && (
        <>
          <p className="label-mono mb-3">past</p>
          <div className="flex flex-col gap-2.5">
            {past.map((plan: Plan, i: number) => (
              <div key={plan.id} className={`anim d${Math.min(i + 1, 6)}`}>
                <PlanCard plan={plan} />
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
