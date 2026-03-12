interface SpinnerProps {
  text?: string;
  size?: number;
  className?: string;
}

export function Spinner({ text = "loading...", size = 14, className }: SpinnerProps) {
  return (
    <div className={`inline-flex items-center gap-2 font-mono text-[11px] text-roam-text-muted ${className ?? ""}`}>
      <svg className="animate-spin" style={{ width: size, height: size }} viewBox="0 0 24 24" fill="none">
        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
      {text}
    </div>
  );
}
