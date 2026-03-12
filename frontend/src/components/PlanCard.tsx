import { useState } from "react";
import { formatDuration } from "@/lib/duration";
import { Avatar } from "@/components/ui/avatar-roam";
import { StatPill } from "@/components/ui/stat-pill";
import type { Plan } from "@/models/plan";

interface Props {
  plan: Plan;
}

function formatSlotLabel(iso: string): string {
  try {
    const d = new Date(iso);
    const now = new Date();
    const tomorrow = new Date(now); tomorrow.setDate(tomorrow.getDate() + 1);
    const dayStr = d.toDateString() === now.toDateString() ? "Today"
      : d.toDateString() === tomorrow.toDateString() ? "Tomorrow"
      : d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
    return `${dayStr} · ${d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}`;
  } catch { return ""; }
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
  } catch { return null; }
}

export default function PlanCard({ plan }: Props) {
  const [expanded, setExpanded] = useState(false);
  const [copied, setCopied] = useState(false);

  const dateParts = plan.scheduledAt ? getDateParts(plan.scheduledAt) : null;
  const isConfirmed = plan.status === "confirmed" || plan.status === "completed";

  function copyShareLink() {
    const url = `${window.location.origin}/share/schedule?uid=${plan.shareCode}`;
    navigator.clipboard.writeText(url).then(() => { setCopied(true); setTimeout(() => setCopied(false), 4000); });
  }

  return (
    <div className="card-surface">
      <button onClick={() => setExpanded(!expanded)} className="w-full bg-transparent border-none cursor-pointer text-left p-0 flex">
        <div className="w-14 shrink-0 flex flex-col items-center justify-center py-4">
          {dateParts ? (
            <>
              <span className="font-mono text-[26px] font-medium leading-none text-roam-logan-dark">{dateParts.day}</span>
              <span className="label-mono mt-[3px] tracking-[2px]">{dateParts.month}</span>
            </>
          ) : (
            <span className="font-mono text-xl text-roam-lav-deep leading-none">—</span>
          )}
        </div>

        <div className={`w-[3px] shrink-0 self-stretch rounded-sm my-2.5 ml-1 mr-2.5 ${isConfirmed ? "bg-[#72B97A]" : "bg-roam-logan-deep"}`} />

        <div className="flex-1 py-3.5 pr-4 min-w-0">
          <p className="font-display text-[17px] text-roam-text leading-tight m-0">{plan.title}</p>
          <div className="flex items-center gap-2 mt-[5px] flex-wrap">
            {plan.placeName && <span className="font-mono text-[10px] text-roam-text-mid">📍 {plan.placeName}</span>}
            {plan.scheduledAt && <span className="font-mono text-[10px] text-roam-text-muted">📅 {formatSlotLabel(plan.scheduledAt)}</span>}
            {isConfirmed && <span className="font-mono text-[8px] tracking-[1.5px] uppercase bg-roam-green text-roam-green-deep px-2 py-[3px] rounded-full">✓ confirmed</span>}
          </div>
        </div>
      </button>

      {expanded && (
        <div className="border-t border-roam-logan/[0.12] py-4 px-5 pb-[18px]">
          <div className="flex gap-2.5 flex-wrap mb-3.5">
            <StatPill label="Duration" value={`~${formatDuration(plan.estimatedMinutes)}`} />
            <StatPill label="Party" value={`${plan.covers} ${plan.covers === 1 ? "person" : "people"}`} />
          </div>

          {plan.members.length > 0 && (
            <div className="mb-3.5">
              <p className="label-mono mb-2">Members</p>
              <div className="flex flex-wrap gap-2">
                {plan.members.map((m) => {
                  const accepted = m.rsvpStatus === "accepted";
                  return (
                    <div key={m.id} className={`member-chip ${accepted ? "bg-roam-green/60 border border-roam-green-deep/[0.22]" : "bg-roam-lavender/50 border border-roam-logan/20"}`}>
                      <Avatar name={m.firstName ?? "?"} size={22} />
                      <span className="font-mono text-[10px] text-roam-text-mid">{m.firstName} {m.lastName}</span>
                      <span className={`font-mono text-[8px] ${accepted ? "text-roam-green-deep" : "text-roam-text-muted"}`}>{m.rsvpStatus}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <div className="pt-2.5 border-t border-roam-logan/10 flex items-center justify-between">
            <span className="font-mono text-[9px] tracking-[1.5px] uppercase text-roam-logan">
              {plan.members.length > 1 ? "👥 group" : "🙋 solo"}
            </span>
            <button onClick={copyShareLink} className={copied
              ? "font-mono text-[9px] tracking-[1.5px] uppercase rounded-[9px] py-2 px-3.5 cursor-pointer bg-[#72B97A]/20 text-roam-green-deep border border-roam-green-deep/30"
              : "btn-primary"
            }>
              {copied ? "✓ copied" : "share link"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
