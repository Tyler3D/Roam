import { useEffect, useState } from "react";
import { Link } from "react-router-dom";

export default function UserCount() {
  const [count, setCount] = useState<number | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    fetch("/api/user-count")
      .then((res) => res.json())
      .then((data) => setCount(data.count))
      .catch(() => setError(true));
  }, []);

  return (
    <div className="min-h-screen bg-roam-bg flex flex-col items-center justify-center px-6">
      <div className="flex items-center gap-2.5 mb-12">
        <img src="/icon.png" alt="Roam" className="w-7 h-7 rounded-[7px] shadow-btn" />
        <span className="font-display italic text-xl text-roam-text leading-none">Roam</span>
      </div>

      {error ? (
        <p className="font-mono text-sm text-roam-text-muted">couldn't load count</p>
      ) : count === null ? (
        <p className="font-mono text-sm text-roam-text-muted">loading…</p>
      ) : (
        <div className="text-center">
          <p className="font-mono text-[11px] text-roam-text-muted tracking-[0.5px] uppercase mb-3">
            explorers on Roam
          </p>
          <p className="font-display italic text-8xl text-roam-text leading-none">
            {count.toLocaleString()}
          </p>
        </div>
      )}

      <Link
        to="/"
        className="mt-16 font-mono text-[11px] text-roam-text-muted tracking-[0.5px] hover:text-roam-text transition-colors"
      >
        ← back to roam
      </Link>
    </div>
  );
}
