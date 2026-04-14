import { Link } from "react-router-dom";

const steps = [
  {
    n: "01",
    title: "share a reel",
    body: "See a restaurant on Instagram or TikTok? Share it directly into Roam from the share sheet.",
  },
  {
    n: "02",
    title: "AI extracts the place",
    body: "Roam analyzes the video, captions, and thumbnails to identify the exact location and what makes it worth visiting.",
  },
  {
    n: "03",
    title: "pinned on your map",
    body: "The place lands on your personal map with the full context of why you saved it — not just a dot.",
  },
];

const features = [
  {
    icon: "🗺️",
    title: "your personal map",
    body: "Every place you save builds a map that's actually yours, pulled from content you already watch.",
  },
  {
    icon: "👥",
    title: "shared collections",
    body: "Build a map with friends. Each person's saves are color-coded so you know who found what.",
  },
  {
    icon: "✦",
    title: "richer than a bookmark",
    body: "A reel captures the vibe, the dish, the moment. Roam keeps that context attached to the pin.",
  },
  {
    icon: "📍",
    title: "one place, many reels",
    body: "When multiple reels point to the same spot, Roam knows. Popularity measured by content.",
  },
];

export default function Landing() {
  return (
    <div className="min-h-screen bg-roam-bg">
      {/* nav */}
      <nav className="flex items-center justify-between px-6 py-5 max-w-[900px] mx-auto">
        <div className="flex items-center gap-2.5">
          <img src="/icon.png" alt="Roam" className="w-7 h-7 rounded-[7px] shadow-btn" />
          <span className="font-display italic text-xl text-roam-text leading-none">Roam</span>
        </div>
        <div className="flex items-center gap-4">
          <Link to="/login" className="font-mono text-[11px] text-roam-text-muted tracking-[0.5px] hover:text-roam-text transition-colors">
            sign in
          </Link>
          <a
            href="https://docs.google.com/forms/d/e/1FAIpQLSe3TekREK7H1jXSjfjCa4moWW7eLOTHg_gvr0NV8wkNVHJWtQ/viewform?usp=dialog"
            target="_blank"
            rel="noopener noreferrer"
            className="btn-primary"
          >
            get started
          </a>
        </div>
      </nav>

      {/* hero */}
      <section className="dot-grid">
        <div className="max-w-[680px] mx-auto px-6 pt-16 pb-24 text-center">
          <div className="anim mb-6">
            <img src="/icon.png" alt="Roam" className="w-20 h-20 rounded-[22px] shadow-btn mx-auto" />
          </div>
          <h1 className="anim d1 font-display italic text-[52px] leading-[1.05] text-roam-text mb-5">
            your reels,<br />on a map.
          </h1>
          <p className="anim d2 font-mono text-[13px] text-roam-text-muted leading-relaxed max-w-[420px] mx-auto mb-10">
            Roam turns Instagram and TikTok reels into a personal map of places to visit. Share a reel, and AI does the rest.
          </p>
          <div className="anim d3 flex items-center justify-center gap-4">
            <a
              href="https://docs.google.com/forms/d/e/1FAIpQLSe3TekREK7H1jXSjfjCa4moWW7eLOTHg_gvr0NV8wkNVHJWtQ/viewform?usp=dialog"
              target="_blank"
              rel="noopener noreferrer"
              className="btn-primary-lg"
              style={{ width: "auto", padding: "14px 32px" }}
            >
              Request access
            </a>
            <Link to="/login" className="font-mono text-[11px] text-roam-text-muted tracking-[0.5px] hover:text-roam-text transition-colors">
              sign in
            </Link>
          </div>
        </div>
      </section>

      {/* how it works */}
      <section className="bg-white/60 border-y border-roam-logan/10">
        <div className="max-w-[900px] mx-auto px-6 py-16">
          <p className="font-mono text-[10px] text-roam-text-muted tracking-[2px] uppercase text-center mb-10">
            how it works
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            {steps.map((s, i) => (
              <div key={s.n} className={`anim d${i + 1}`}>
                <p className="font-mono text-[10px] text-roam-logan tracking-[2px] mb-3">{s.n}</p>
                <p className="font-mono text-[13px] text-roam-text mb-2">{s.title}</p>
                <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed">{s.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* features */}
      <section className="max-w-[900px] mx-auto px-6 py-16">
        <p className="font-mono text-[10px] text-roam-text-muted tracking-[2px] uppercase text-center mb-10">
          features
        </p>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {features.map((f, i) => (
            <div
              key={f.title}
              className={`anim d${i + 1} bg-roam-surface border border-roam-logan/20 rounded-[16px] p-5 shadow-card flex gap-4`}
            >
              <div className="w-9 h-9 bg-roam-lavender rounded-[10px] flex items-center justify-center text-[18px] shrink-0">
                {f.icon}
              </div>
              <div>
                <p className="font-mono text-[13px] text-roam-text mb-1">{f.title}</p>
                <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed">{f.body}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* cta */}
      <section className="max-w-[680px] mx-auto px-6 pb-24">
        <div className="bg-roam-lavender border border-roam-logan/20 rounded-[20px] p-10 text-center shadow-card">
          <img src="/icon.png" alt="Roam" className="w-12 h-12 rounded-[12px] shadow-btn mx-auto mb-5" />
          <p className="font-display italic text-[30px] text-roam-text leading-tight mb-3">
            stop bookmarking.<br />start mapping.
          </p>
          <p className="font-mono text-[12px] text-roam-text-muted leading-relaxed mb-7 max-w-[320px] mx-auto">
            Roam is invite-only during beta. Sign up to request access.
          </p>
          <a
            href="https://docs.google.com/forms/d/e/1FAIpQLSe3TekREK7H1jXSjfjCa4moWW7eLOTHg_gvr0NV8wkNVHJWtQ/viewform?usp=dialog"
            target="_blank"
            rel="noopener noreferrer"
            className="btn-primary-lg inline-block"
            style={{ width: "auto", padding: "14px 36px" }}
          >
            Request access
          </a>
        </div>
      </section>

      {/* footer */}
      <footer className="border-t border-roam-logan/15 px-6 py-6">
        <div className="max-w-[900px] mx-auto flex items-center justify-between">
          <div className="flex items-center gap-2">
            <img src="/icon.png" alt="Roam" className="w-5 h-5 rounded-[5px]" />
            <span className="font-mono text-[11px] text-roam-text-muted">© 2026 Roam</span>
          </div>
          <div className="flex items-center gap-5">
            <Link to="/privacy" className="font-mono text-[11px] text-roam-text-muted tracking-[0.5px] hover:text-roam-text transition-colors">
              Privacy Policy
            </Link>
            <a href="mailto:tyler.manrique32@gmail.com" className="font-mono text-[11px] text-roam-text-muted tracking-[0.5px] hover:text-roam-text transition-colors">
              Contact
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}
