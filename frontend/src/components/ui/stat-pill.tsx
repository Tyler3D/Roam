interface StatPillProps {
  label: string;
  value: string;
}

export function StatPill({ label, value }: StatPillProps) {
  return (
    <div className="stat-pill">
      <p className="label-mono tracking-[1.5px] mb-1">{label}</p>
      <p className="font-mono text-[13px] text-roam-logan-dark m-0">{value}</p>
    </div>
  );
}
