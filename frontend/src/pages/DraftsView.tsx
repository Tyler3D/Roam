import { useNavigate } from "react-router-dom";
import { usePlansDrafts } from "@/api/plans";
import { Spinner } from "@/components/ui/spinner";
import { EmptyState } from "@/components/ui/empty-state";
import PlanCard from "@/components/PlanCard";
import type { Plan } from "@/models/plan";

export default function DraftsView() {
  const { data: drafts = [], isLoading } = usePlansDrafts();

  if (isLoading) {
    return (
      <div className="text-center py-[60px]">
        <Spinner text="loading drafts..." />
      </div>
    );
  }

  if (drafts.length === 0) {
    return (
      <div className="max-w-[480px] mx-auto pt-5 px-4">
        <EmptyState
          icon="◈"
          title="no drafts"
          subtitle="tap an idea to start planning"
        />
      </div>
    );
  }

  return (
    <div className="max-w-[480px] mx-auto pt-5 px-4">
      <div className="flex flex-col gap-2.5">
        {(drafts as Plan[]).map((plan, i) => (
          <div key={plan.id} className={`anim d${Math.min(i + 1, 6)}`}>
            <PlanCard plan={plan} />
          </div>
        ))}
      </div>
    </div>
  );
}
