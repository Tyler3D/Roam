import { useNavigate } from "react-router-dom";
import { formatDuration } from "@/lib/duration";
import type { Plan } from "@/models/plan";

interface Props {
  plan: Plan;
}

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

function getDateParts(iso: string) {
  try {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    return {
      day: d.getDate(),
      month: d.toLocaleDateString("en-US", { month: "short" }).toUpperCase(),
      time: d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }),
    };
  } catch {
    return null;
  }
}

export default function PlanCard({ plan }: Props) {
  const navigate = useNavigate();
  const dateParts = plan.scheduledAt ? getDateParts(plan.scheduledAt) : null;
  const isConfirmed = plan.status === "confirmed" || plan.status === "completed";

  return (
    <button
      onClick={() => navigate(`/plans/${plan.id}`)}
      className="card-surface w-full bg-transparent border-none cursor-pointer text-left p-0 flex"
    >
      <div className="w-14 shrink-0 flex flex-col items-center justify-center py-4">
        {dateParts ? (
          <>
            <span className="font-mono text-[26px] font-medium leading-none text-roam-logan-dark">
              {dateParts.day}
            </span>
            <span className="label-mono mt-[3px] tracking-[2px]">{dateParts.month}</span>
          </>
        ) : (
          <span className="font-mono text-xl text-roam-lav-deep leading-none">—</span>
        )}
      </div>

      <div
        className={`w-[3px] shrink-0 self-stretch rounded-sm my-2.5 ml-1 mr-2.5 ${
          isConfirmed ? "bg-[#72B97A]" : "bg-roam-logan-deep"
        }`}
      />

      <div className="flex-1 py-3.5 pr-4 min-w-0">
        <p className="font-display text-[17px] text-roam-text leading-tight m-0">{plan.title}</p>
        <div className="flex items-center gap-2 mt-[5px] flex-wrap">
          {plan.placeName && (
            <span className="font-mono text-[10px] text-roam-text-mid">📍 {plan.placeName}</span>
          )}
          {plan.scheduledAt ? (
            <span className="font-mono text-[10px] text-roam-text-muted">
              📅 {formatSlotLabel(plan.scheduledAt)}
            </span>
          ) : (
            <span className="font-mono text-[10px] text-roam-logan">Pick a time →</span>
          )}
          {isConfirmed && (
            <span className="font-mono text-[8px] tracking-[1.5px] uppercase bg-roam-green text-roam-green-deep px-2 py-[3px] rounded-full">
              ✓ confirmed
            </span>
          )}
          <span className="font-mono text-[10px] text-roam-text-muted">
            ~{formatDuration(plan.estimatedMinutes)}
          </span>
        </div>
      </div>
    </button>
  );
}
