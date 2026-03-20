import { useState } from "react";
import { useSearchParams, useNavigate } from "react-router-dom";
import { useSharedPlan, useRsvp } from "@/api/share";
import { useMe } from "@/api/users";
import { formatDuration } from "@/lib/duration";
import { useAuth } from "@/auth";
import { Avatar } from "@/components/ui/avatar-roam";
import { StatPill } from "@/components/ui/stat-pill";
import { LocationLink } from "@/components/ui/location-link";
import type { PlanMember } from "@/models/plan";
import type { RsvpResponse } from "@/models/share";

function formatDateFull(iso: string) {
  try {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    const now = new Date();
    const tomorrow = new Date(now); tomorrow.setDate(tomorrow.getDate() + 1);
    const isToday = d.toDateString() === now.toDateString();
    const isTomorrow = d.toDateString() === tomorrow.toDateString();
    const dayStr = isToday ? "Today" : isTomorrow ? "Tomorrow"
      : d.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" });
    const timeStr = d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
    return { day: d.getDate(), month: d.toLocaleDateString("en-US", { month: "short" }).toUpperCase(), time: timeStr, full: `${dayStr} · ${timeStr}` };
  } catch { return null; }
}

export default function Schedule() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const shareCode = searchParams.get("uid");

  const { data: plan, isLoading } = useSharedPlan(shareCode);
  const { data: me } = useMe({ enabled: !!user });
  const rsvpMutation = useRsvp(shareCode);

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [rsvpDone, setRsvpDone] = useState(false);
  const [gcalLink, setGcalLink] = useState<string | null>(null);
  const [error, setError] = useState("");

  const isLoggedIn = !!user;

  const alreadyMember = !!(
    user && plan?.members?.some((m: PlanMember) => m.userId === user.uid)
  );

  async function handleGuestRsvp(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    if (!firstName.trim()) { setError("First name is required"); return; }
    if (!phone.trim() && !email.trim()) { setError("Phone or email is required"); return; }
    rsvpMutation.mutate(
      { firstName: firstName.trim(), lastName: lastName.trim(), phone: phone.trim() || null, email: email.trim() || null },
      {
        onSuccess: (result: RsvpResponse) => { setRsvpDone(true); setGcalLink(result.gcalLink ?? null); },
        onError: (err) => setError((err as { message?: string }).message ?? "RSVP failed"),
      },
    );
  }

  function handleLoggedInRsvp() {
    if (!shareCode || !me) return;
    setError("");
    rsvpMutation.mutate(
      { firstName: me.firstName, lastName: me.lastName, email: me.email ?? null, phone: me.phone ?? null },
      {
        onSuccess: (result: RsvpResponse) => { setRsvpDone(true); setGcalLink(result.gcalLink ?? null); },
        onError: (err) => setError((err as { message?: string }).message ?? "RSVP failed"),
      },
    );
  }

  if (!shareCode) {
    return (
      <div className="page-center">
        <span className="font-mono text-[13px] text-roam-text">invalid link</span>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="page-center">
        <span className="font-mono text-[11px] text-roam-text-muted">loading...</span>
      </div>
    );
  }

  if (!plan) {
    return (
      <div className="page-center">
        <span className="font-mono text-[13px] text-roam-text">plan not found</span>
      </div>
    );
  }

  const dateParts = plan.scheduledAt ? formatDateFull(plan.scheduledAt) : null;
  const acceptedMembers = plan.members.filter((m) => m.rsvpStatus === "accepted");
  const showRsvpDone = rsvpDone || alreadyMember;

  return (
    <div className="page-center">
      <div className="anim w-full max-w-[440px]">
        <div className="text-center mb-7">
          <div className="logo-icon">🧭</div>
          <h1 className="font-display italic text-4xl text-roam-text leading-none">roam</h1>
          <p className="font-mono text-[10px] text-roam-text-muted tracking-[1.5px] uppercase mt-2">you're invited to a plan</p>
        </div>

        <div className="anim d1 card-surface shadow-card-hover">
          <div className="bg-gradient-to-br from-roam-logan-deep to-roam-logan-dark p-6 pb-5">
            <div className="flex items-start gap-4">
              {dateParts && (
                <div className="text-center bg-white/15 rounded-xl py-2.5 px-3.5 shrink-0">
                  <div className="font-mono text-[28px] font-medium text-white leading-none">{dateParts.day}</div>
                  <div className="font-mono text-[9px] tracking-[2px] uppercase text-white/65 mt-1">{dateParts.month}</div>
                </div>
              )}
              <div className="flex-1">
                <p className="font-display text-[22px] text-white leading-tight mb-2">{plan.title}</p>
                {dateParts && <p className="font-mono text-[11px] text-white/75">📅 {dateParts.full}</p>}
              </div>
            </div>
          </div>

          <div className="p-6 pt-5">
            {plan.placeName && (
              <div className="mb-4">
                <p className="label-mono mb-1.5">Location</p>
                <LocationLink placeName={plan.placeName} />
              </div>
            )}

            <div className={`flex gap-2.5 flex-wrap ${acceptedMembers.length > 0 ? "mb-4" : ""}`}>
              {plan.estimatedMinutes && (
                <StatPill label="Duration" value={`~${formatDuration(plan.estimatedMinutes)}`} />
              )}
              <StatPill label="Party" value={`${plan.partySize} ${plan.partySize === 1 ? "person" : "people"}`} />
            </div>

            {acceptedMembers.length > 0 && (
              <div>
                <p className="label-mono mb-2">Who's in</p>
                <div className="flex flex-wrap gap-1.5">
                  {acceptedMembers.map((m: PlanMember) => (
                    <div key={m.id} className="member-chip bg-roam-green/60 border border-roam-green-deep/[0.22]">
                      <Avatar name={m.firstName ?? "?"} size={20} />
                      <span className="font-mono text-[10px] text-roam-green-deep">{m.firstName}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        {!showRsvpDone ? (
          isLoggedIn ? (
            <div className="anim d2 mt-5 text-center">
              <p className="font-mono text-[11px] text-roam-text-mid mb-3">
                You're logged in as {user?.displayName || user?.email || "a Roam user"}.
              </p>
              {error && <p className="font-mono text-[11px] text-roam-error mb-2">{error}</p>}
              <button onClick={handleLoggedInRsvp} disabled={rsvpMutation.isPending} className="btn-primary-lg" style={{ opacity: rsvpMutation.isPending ? 0.7 : 1 }}>
                {rsvpMutation.isPending ? "joining..." : "i'm in →"}
              </button>
            </div>
          ) : (
            <form onSubmit={handleGuestRsvp} className="anim d2 mt-5">
              <p className="label-mono mb-2.5">rsvp</p>
              <div className="flex gap-2 mb-2">
                <input value={firstName} onChange={(e) => setFirstName(e.target.value)} placeholder="first name *" required className="input-field flex-1 text-xs py-3 px-3.5" />
                <input value={lastName} onChange={(e) => setLastName(e.target.value)} placeholder="last name" className="input-field flex-1 text-xs py-3 px-3.5" />
              </div>
              <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="phone" type="tel" className="input-field text-xs py-3 px-3.5 mb-2" />
              <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="email" type="email" className="input-field text-xs py-3 px-3.5 mb-3" />
              <p className="font-mono text-[9px] text-roam-text-muted mb-3">phone or email required</p>
              {error && <p className="font-mono text-[11px] text-roam-error mb-2">{error}</p>}
              <button type="submit" disabled={rsvpMutation.isPending} className="btn-primary-lg" style={{ opacity: rsvpMutation.isPending ? 0.7 : 1 }}>
                {rsvpMutation.isPending ? "joining..." : "i'm in →"}
              </button>
            </form>
          )
        ) : (
          <div className="anim d2 mt-5 text-center">
            <div className="bg-roam-green/60 rounded-[14px] p-5 border border-roam-green-deep/[0.22]">
              <p className="font-mono text-sm text-roam-green-deep mb-2">✓ you're in!</p>
              <p className="font-mono text-[11px] text-roam-text-mid m-0">you've been added to the plan</p>
            </div>
            {gcalLink && (
              <a href={gcalLink} target="_blank" rel="noopener noreferrer" className="inline-block mt-3 py-3 px-5 bg-roam-surface border border-roam-logan/25 rounded-[11px] font-mono text-[11px] text-roam-logan-deep no-underline">
                📅 add to calendar
              </a>
            )}
            {isLoggedIn && (
              <button onClick={() => navigate("/app")} type="button" className="block w-full mt-3 py-3 px-5 bg-transparent border border-roam-logan/25 rounded-[11px] font-mono text-[11px] text-roam-logan-deep cursor-pointer">
                ← back to dashboard
              </button>
            )}
          </div>
        )}

        <p className="anim d3 font-mono text-[9px] text-roam-text-muted mt-3.5 tracking-[0.5px] text-center">
          plan your own adventures with roam
        </p>
      </div>
    </div>
  );
}
