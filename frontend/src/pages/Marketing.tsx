import { useRef, useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { ChevronDown } from "lucide-react";

function AppleLogo({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden
    >
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09l.01-.01zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
    </svg>
  );
}

/**
 * SCROLL CHOREOGRAPHY
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * Two fixed headlines, driven by getBoundingClientRect() on two track divs.
 *
 * HEADLINE 1 — "Share a reel. Roam does the rest."
 *   track1.top: vh → vh*0.55 — fade in at bottom
 *   track1.top: vh*0.55 → vh*0.3 — hold at bottom
 *   track1.top: vh*0.3 → 0 — rise bottom → center → top + scale up
 *   track1.top: 0 → … — PINNED at top while body scrolls
 *   (exit driven by handoff with H2)
 *
 * HEADLINE 2 — "Beyond the map"
 *   track2 starts immediately after track1's card (no spacer).
 *   track2.top in (vh, vh*0.5] — H2 y = track2.top (scrolls with page, glued to card bottom)
 *   track2.top in (vh*0.5, 0]  — H2 holds at center
 *   track2.top in (0, -handoff] — HANDOFF: H1 slides up+fades, H2 rises center→top
 *   track2.top < -handoff        — H2 pinned at top, body scrolls
 *   track2.bottom < 0            — H2 fades out
 *
 * BODY in track 2:
 *   bodyOffset = vh*0.5 + handoffRange so paragraph is at center when handoff completes.
 *
 * All distances are vh-fractions → screen-size independent.
 * ─────────────────────────────────────────────────────────────────────────────
 */

const MIN_SCALE = 0.78;
const PIN_Y = 44; // px from viewport top when headline is "pinned"
const HEADLINE_H = 80; // approx headline rendered height, for fade mask calc
const HANDOFF_RANGE = 0.4; // vh fraction — how long the handoff takes

function clamp(v: number, lo: number, hi: number) {
  return Math.max(lo, Math.min(hi, v));
}
function lerp(a: number, b: number, t: number) {
  return a + (b - a) * clamp(t, 0, 1);
}

interface HL {
  visible: boolean;
  y: number;
  scale: number;
  opacity: number;
  pinned: boolean;
}

const HIDDEN: HL = {
  visible: false,
  y: 0,
  scale: MIN_SCALE,
  opacity: 0,
  pinned: false,
};

function computeH1(t1: DOMRect, vh: number): HL {
  if (t1.top > vh) return HIDDEN;
  // After handoff takes over, we leave H1 to the combined fn — so just handle entry here
  const centerY = vh * 0.5 - HEADLINE_H / 2;
  if (t1.top >= vh * 0.55) {
    const p = (vh - t1.top) / (vh * 0.45);
    return {
      visible: true,
      y: vh - 100,
      scale: MIN_SCALE,
      opacity: clamp(p * 2, 0, 1),
      pinned: false,
    };
  }
  if (t1.top >= vh * 0.3) {
    return {
      visible: true,
      y: vh - 100,
      scale: MIN_SCALE,
      opacity: 1,
      pinned: false,
    };
  }
  // center → top
  const p = (vh * 0.3 - t1.top) / (vh * 0.3);
  if (p <= 0.5) {
    // bottom → center
    const pp = p / 0.5;
    return {
      visible: true,
      y: lerp(vh - 100, centerY, pp),
      scale: MIN_SCALE,
      opacity: 1,
      pinned: false,
    };
  }
  // center → top
  const pp = (p - 0.5) / 0.5;
  const y = lerp(centerY, PIN_Y, pp);
  const scale = lerp(MIN_SCALE, 1, pp);
  return { visible: true, y, scale, opacity: 1, pinned: pp > 0.97 };
}

function computeBoth(t1: DOMRect, t2: DOMRect, vh: number): { h1: HL; h2: HL } {
  const handoffPx = vh * HANDOFF_RANGE;
  const centerY = vh * 0.5 - HEADLINE_H / 2;

  // ── Everything gone ──────────────────────────────────────────────────────
  if (t2.bottom < 0) return { h1: HIDDEN, h2: HIDDEN };

  // ── Handoff complete ─────────────────────────────────────────────────────
  if (t2.top <= -handoffPx) {
    return {
      h1: HIDDEN,
      h2: { visible: true, y: PIN_Y, scale: 1, opacity: 1, pinned: true },
    };
  }

  // ── Handoff active: t2.top in (-handoffPx, 0] ───────────────────────────
  if (t2.top <= 0) {
    const p = clamp(-t2.top / handoffPx, 0, 1);
    return {
      h1: {
        visible: true,
        y: lerp(PIN_Y, PIN_Y - 90, p),
        scale: 1,
        opacity: lerp(1, 0, p),
        pinned: false,
      },
      h2: {
        visible: true,
        y: lerp(centerY, PIN_Y, p),
        scale: lerp(MIN_SCALE, 1, p),
        opacity: 1, // already fully visible from center-hold phase, no re-fade
        pinned: p > 0.97,
      },
    };
  }

  // ── H2 entry: t2.top in (0, vh] ─────────────────────────────────────────
  // H1: always pinned during this phase (avoid glitch from computeH1's exit check)
  const h1Pinned: HL =
    t1.top <= vh * 0.3
      ? { visible: true, y: PIN_Y, scale: 1, opacity: 1, pinned: true }
      : computeH1(t1, vh);

  // H2 tracks t2.top directly — behaves like in-flow content at card bottom
  if (t2.top > vh) return { h1: h1Pinned, h2: HIDDEN };

  // Fade in as it enters
  const fadeIn = clamp((vh - t2.top) / (vh * 0.15), 0, 1);

  if (t2.top > vh * 0.5) {
    // Scrolls naturally with page — y matches t2.top position
    const y = t2.top - HEADLINE_H / 2;
    return {
      h1: h1Pinned,
      h2: {
        visible: true,
        y,
        scale: MIN_SCALE,
        opacity: fadeIn,
        pinned: false,
      },
    };
  }

  // Hold at center
  return {
    h1: h1Pinned,
    h2: {
      visible: true,
      y: centerY,
      scale: MIN_SCALE,
      opacity: 1,
      pinned: false,
    },
  };
}

export default function Marketing() {
  const visionRef = useRef<HTMLElement>(null);
  const t1Ref = useRef<HTMLDivElement>(null);
  const t2Ref = useRef<HTMLDivElement>(null);

  const [h1, setH1] = useState<HL>(HIDDEN);
  const [h2, setH2] = useState<HL>(HIDDEN);
  const [vh, setVh] = useState(() =>
    typeof window !== "undefined" ? window.innerHeight : 800,
  );

  const tick = useCallback(() => {
    const currentVh = window.innerHeight;
    const r1 = t1Ref.current?.getBoundingClientRect();
    const r2 = t2Ref.current?.getBoundingClientRect();
    if (!r1 || !r2) return;

    if (r2.top > currentVh) {
      setH1(computeH1(r1, currentVh));
      setH2(HIDDEN);
    } else {
      const { h1: nh1, h2: nh2 } = computeBoth(r1, r2, currentVh);
      setH1(nh1);
      setH2(nh2);
    }
  }, []);

  // ── Scroll friction ──────────────────────────────────────────────────────
  // Wheel (desktop): heavier friction for deliberate scroll.
  // Touch (mobile): lighter friction so swiping feels responsive but still dampened.
  useEffect(() => {
    const WHEEL_MULTIPLIER = 0.28; // desktop: more friction
    const TOUCH_MULTIPLIER = 1.0; // mobile: same friction
    const LERP_EASE = 0.09;

    let targetY = window.scrollY;
    let rafId = 0;
    let touchPrevY = 0;

    const maxScroll = () =>
      document.documentElement.scrollHeight - window.innerHeight;

    const scheduleRaf = () => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(function step() {
        const current = window.scrollY;
        const diff = targetY - current;
        if (Math.abs(diff) > 0.5) {
          window.scrollTo(0, current + diff * LERP_EASE);
          rafId = requestAnimationFrame(step);
        } else {
          window.scrollTo(0, targetY);
        }
      });
    };

    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      targetY = Math.max(
        0,
        Math.min(maxScroll(), targetY + e.deltaY * WHEEL_MULTIPLIER),
      );
      scheduleRaf();
    };

    const onTouchStart = (e: TouchEvent) => {
      touchPrevY = e.touches[0].clientY;
      targetY = window.scrollY;
    };

    const onTouchMove = (e: TouchEvent) => {
      e.preventDefault();
      const delta = touchPrevY - e.touches[0].clientY;
      touchPrevY = e.touches[0].clientY;
      targetY = Math.max(
        0,
        Math.min(maxScroll(), targetY + delta * TOUCH_MULTIPLIER),
      );
      scheduleRaf();
    };

    window.addEventListener("wheel", onWheel, { passive: false });
    window.addEventListener("touchstart", onTouchStart, { passive: false });
    window.addEventListener("touchmove", onTouchMove, { passive: false });

    return () => {
      window.removeEventListener("wheel", onWheel);
      window.removeEventListener("touchstart", onTouchStart);
      window.removeEventListener("touchmove", onTouchMove);
      cancelAnimationFrame(rafId);
    };
  }, []);

  useEffect(() => {
    const onResize = () => {
      setVh(window.innerHeight);
      tick();
    };
    tick();
    window.addEventListener("scroll", tick, { passive: true });
    window.addEventListener("resize", onResize, { passive: true });
    return () => {
      window.removeEventListener("scroll", tick);
      window.removeEventListener("resize", onResize);
    };
  }, [tick]);

  // bodyOffset for track2: paragraph is at viewport center when handoff completes
  // handoff complete at t2.top = -handoffPx
  // body viewport pos = t2.top + bodyOffset = center = vh*0.5
  // bodyOffset = vh*0.5 + handoffPx = vh*0.5 + vh*HANDOFF_RANGE = vh*(0.5+HANDOFF_RANGE)
  const bodyOffset = vh * (0.5 + HANDOFF_RANGE);

  return (
    <div className="min-h-screen bg-background flex flex-col">
      {/* ═══════════════════════ HERO ═══════════════════════════════════════ */}
      <div
        className="w-full max-w-4xl mx-auto flex flex-col px-6 text-center flex-shrink-0 box-border"
        style={{ minHeight: "100dvh", height: "100dvh" }}
      >
        <header className="pt-6 md:pt-8 pb-2 md:pb-4 shrink-0">
          <div className="text-xl font-display font-semibold">Roam</div>
        </header>
        <main
          className="flex-1 grid gap-0 min-h-0"
          style={{ gridTemplateRows: "13fr 5fr 4fr" }}
        >
          <div className="flex flex-col items-center justify-center min-h-0 px-2 overflow-y-auto py-2">
            <p className="text-sm font-medium text-primary tracking-wide mb-4 shrink-0">
              A taste engine for real life
            </p>
            <h1 className="text-4xl md:text-5xl lg:text-6xl font-display font-semibold leading-tight text-balance max-w-2xl shrink-0">
              Saves are just the beginning.
            </h1>
            <p className="text-muted-foreground text-lg md:text-xl max-w-xl mt-6 leading-relaxed shrink-0">
              Instead of letting Instagram and TikTok saves disappear into a
              graveyard of good intentions, Roam turns what you are drawn to
              into a living map so your saves become plans.
            </p>
          </div>
          <div className="flex flex-col items-center justify-center py-2 shrink-0 min-h-0">
            <p className="text-muted-foreground text-sm md:text-base mb-2 md:mb-3">
              We're running a private beta. Join the mailing list for early
              access and updates.
            </p>
            <Button
              size="lg"
              className="gap-2 text-base px-8 h-12 shrink-0 bg-black text-white hover:bg-black/90"
              asChild
            >
              <a
                href="https://docs.google.com/forms/d/e/1FAIpQLSe3TekREK7H1jXSjfjCa4moWW7eLOTHg_gvr0NV8wkNVHJWtQ/viewform?usp=dialog"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center"
                aria-label="Join the iOS waitlist"
              >
                <AppleLogo className="h-5 w-5" />
                Join the iOS waitlist
              </a>
            </Button>
          </div>
          <div className="flex flex-col items-center justify-end pb-6 shrink-0 min-h-0 border-t border-border/40 pt-3">
            <p className="text-muted-foreground text-sm mb-2 text-center px-4">
              Scroll below to learn more about our vision
            </p>
            <button
              type="button"
              onClick={() =>
                visionRef.current?.scrollIntoView({ behavior: "smooth" })
              }
              className="flex items-center justify-center p-1 text-muted-foreground hover:text-foreground transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-full"
              aria-label="Scroll to vision"
            >
              <ChevronDown className="h-7 w-7 animate-bounce" aria-hidden />
            </button>
          </div>
        </main>
      </div>

      {/* ═══════════════════════ FIXED HEADLINES ════════════════════════════ */}
      {h1.visible && (
        <div
          className="fixed left-0 right-0 z-30 flex justify-center pointer-events-none"
          style={{
            top: 0,
            transform: `translateY(${h1.y}px) scale(${h1.scale})`,
            transformOrigin: "center top",
            opacity: h1.opacity,
            willChange: "transform, opacity",
          }}
        >
          <h2
            className="font-display font-semibold text-center text-2xl sm:text-3xl md:text-4xl lg:text-5xl max-w-2xl px-6 leading-tight py-3"
            style={{ background: "hsl(var(--background))" }}
          >
            Share a reel. Roam does the rest.
          </h2>
        </div>
      )}
      {h2.visible && (
        <div
          className="fixed left-0 right-0 z-20 flex justify-center pointer-events-none"
          style={{
            top: 0,
            transform: `translateY(${h2.y}px) scale(${h2.scale})`,
            transformOrigin: "center top",
            opacity: h2.opacity,
            willChange: "transform, opacity",
          }}
        >
          <h2
            className="font-display font-semibold text-center text-2xl sm:text-3xl md:text-4xl lg:text-5xl max-w-2xl px-6 leading-tight py-3"
            style={{ background: "hsl(var(--background))" }}
          >
            Beyond the map
          </h2>
        </div>
      )}

      {/* Fade mask: must be BELOW both headlines (z-15 < H2's z-20 < H1's z-30)
          but ABOVE normal body text (z-0). Fades body text near the top so it
          never overlaps the pinned headline.                                   */}
      {(h1.pinned || h2.pinned) && (
        <div
          className="fixed left-0 right-0 pointer-events-none"
          style={{
            top: 0,
            height: `${PIN_Y + HEADLINE_H + 100}px`,
            zIndex: 15,
            background: `linear-gradient(to bottom,
            hsl(var(--background)) 0%,
            hsl(var(--background)) ${PIN_Y + HEADLINE_H}px,
            transparent 100%)`,
          }}
          aria-hidden
        />
      )}

      {/* ═══════════════════════ VISION SECTION ═════════════════════════════ */}
      <section
        ref={visionRef}
        className="bg-background border-t border-border/50"
      >
        {/* ── TRACK 1 ── "Share a reel. Roam does the rest." ─────────────────
            Top spacer vh*0.5 → H1 enters bottom→top exactly as it would with
            a vh*0.5 body offset (matching the previous tuning).
            Body content follows. Track 2 ref is placed at the very end of the
            card so H2 appears as if glued to the card's bottom edge.
        ──────────────────────────────────────────────────────────────────── */}
        <div ref={t1Ref} className="relative">
          {/* Spacer gives H1 travel distance before body appears */}
          <div style={{ height: `${vh * 0.5}px` }} aria-hidden />

          {/* Body */}
          <div className="bg-background">
            <div className="max-w-2xl mx-auto px-6 space-y-5">
              <div style={{ height: `${vh * 0.08}px` }} aria-hidden />

              {/* Card 1 */}
              <div className="rounded-2xl bg-muted/30 border border-border/50 p-6 md:p-8">
                <p className="text-sm font-medium text-muted-foreground mb-3">
                  How it works
                </p>
                <p className="text-foreground text-lg leading-relaxed">
                  Share a reel and Roam extracts all the important details like
                  location and categorizes it. You confirm and rank it among
                  your existing pins. Over time, Roams builds a living map of
                  your taste. What you love. What you want to try. What you have
                  already done.
                </p>
              </div>

              {/* Card 2 */}
              <div className="rounded-2xl bg-muted/30 border border-border/50 p-6 md:p-8">
                <p className="text-sm font-medium text-muted-foreground mb-3">
                  One share becomes one pin
                </p>
                <p className="text-foreground text-lg leading-relaxed">
                  Rate it. Tag it. Revisit it. From a single share, Roam creates
                  a pin you can rate, tag, and revisit. Instead of scrolling
                  Google Maps or hunting through screenshots, you open Roam and
                  see what you're in the mood for, like the best-rated nearby
                  dinner spots, saved hikes within 30 minutes, nightlife you've
                  been meaning to try. Organized by distance and category.
                </p>
              </div>

              {/* Card 3 — "What Roam surfaces" */}
              <div className="rounded-2xl bg-muted/30 border border-border/50 p-6 md:p-8 space-y-4">
                <p className="text-sm font-medium text-muted-foreground">
                  What Roam surfaces
                </p>
                <div className="rounded-xl bg-background/80 border border-border/40 p-4">
                  <p className="text-sm text-muted-foreground">
                    Tonight's pick
                  </p>
                  <p className="text-lg font-medium">Rooftop bar at sunset</p>
                </div>
                <div className="rounded-xl bg-background/80 border border-border/40 p-4">
                  <p className="text-sm text-muted-foreground">Plan ahead</p>
                  <p className="text-lg font-medium">
                    Hike with a view, 25 min away
                  </p>
                </div>
                <div className="rounded-xl bg-background/80 border border-border/40 p-4">
                  <p className="text-sm text-muted-foreground">Rediscover</p>
                  <p className="text-lg font-medium">
                    That restaurant you saved last month
                  </p>
                </div>
              </div>

              {/* Tiny gap so card bottom aligns cleanly with track 2 start */}
              <div style={{ height: "16px" }} aria-hidden />
            </div>
          </div>
        </div>

        {/* ── TRACK 2 ── "Beyond the map" ────────────────────────────────────
            No top spacer — track starts immediately after card so t2.top
            equals the card-bottom viewport position, letting H2 appear
            glued to the bottom of the card.

            Body offset = vh*(0.5 + HANDOFF_RANGE) so first paragraph
            arrives at viewport center exactly when handoff completes.
        ──────────────────────────────────────────────────────────────────── */}
        <div ref={t2Ref} className="relative bg-background">
          {/* Body offset spacer */}
          <div style={{ height: `${bodyOffset}px` }} aria-hidden />

          <div className="max-w-2xl mx-auto px-6 space-y-5 text-center">
            <p className="text-muted-foreground text-lg leading-relaxed">
              We believe in living life with intention. Once Roam understands
              your taste, it resurfaces ideas at the right moment, so your saves
              turn into plans, not projects. Over time, your profile becomes
              more than a map. It becomes an expression of who you are offline.
              Save a dinner. Pin a hike. Live well.
            </p>

            <p className="text-foreground font-medium text-lg leading-relaxed">
              Roam isn't just about saving places. It is about noticing what you
              are drawn to and actually doing the things you have been meaning
              to do.
            </p>

            {/* Bottom padding formula: vh*0.5 - contentHeight/2 ≈ vh*0.5 - 135px
                This ensures at max scroll the paragraph block is centered on screen.
                If content height changes, adjust this fraction accordingly.        */}
            <div style={{ height: `${vh * 0.35}px` }} aria-hidden />
          </div>
        </div>
      </section>
    </div>
  );
}
