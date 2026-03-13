import { useState } from "react";
import { formatDuration } from "@/lib/duration";
import { Spinner } from "@/components/ui/spinner";
import { LocationLink } from "@/components/ui/location-link";
import { useSelectPlaceSuggestion } from "@/api/ideas";
import type { Idea } from "@/models/idea";

interface Props {
  idea: Idea;
  onDelete: (id: string) => void;
  onPlanThis: (id: string) => void;
  enriching?: boolean;
}

export default function IdeaCard({ idea, onDelete, onPlanThis, enriching }: Props) {
  const [expanded, setExpanded] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const selectPlace = useSelectPlaceSuggestion();

  const pr = idea.pipelineResult;
  const minutes = pr?.estimatedMinutes ?? 60;
  const category = pr?.category;
  const tags = (pr?.rawOutput as { tags?: string[] } | undefined)?.tags ?? [];

  return (
    <div className={`card-surface relative transition-shadow duration-200 ${expanded ? "shadow-card-hover" : ""}`}>
      <div className="relative">
        <button onClick={() => setExpanded(!expanded)} className="w-full bg-transparent border-none cursor-pointer text-left p-0 flex">
          <div className="w-14 shrink-0 flex flex-col items-center justify-center py-4">
            {category ? (
              <span className="text-[22px]">
                {category === "food-drink" ? "🍽" : category === "arts-culture" ? "🎨" : category === "outdoors" ? "🌿" : category === "nightlife" ? "🍸" : category === "fitness" ? "💪" : "📌"}
              </span>
            ) : (
              <span className="font-mono text-xl text-roam-lav-deep leading-none">—</span>
            )}
          </div>

          <div className="w-[3px] shrink-0 self-stretch bg-roam-logan-deep rounded-sm my-2.5 ml-1 mr-2.5" />

          <div className="flex-1 py-3.5 pr-10 min-w-0">
            <p className="font-display text-[17px] text-roam-text leading-tight m-0">
              {idea.displayName ?? pr?.refinedTitle ?? idea.title}
            </p>

            {enriching ? (
              <div className="mt-1.5">
                <Spinner text="finding place & time..." size={11} className="gap-1.5 text-[10px]" />
              </div>
            ) : (
              <div className="flex items-center gap-2 mt-[5px] flex-wrap">
                {idea.planCount > 0 && (
                  <>
                    <span className="font-mono text-[10px] text-roam-lav-deep">Planned {idea.planCount}×</span>
                    <span className="text-roam-lav-deep text-[10px]">·</span>
                  </>
                )}
                {idea.placeName && (
                  <>
                    <span className="font-mono text-[10px] text-roam-text-mid">📍 {idea.placeName}</span>
                    <span className="text-roam-lav-deep text-[10px]">·</span>
                  </>
                )}
                <span className="font-mono text-[10px] text-roam-text-muted">~{formatDuration(minutes)}</span>
              </div>
            )}
          </div>
        </button>

        {!confirmDelete ? (
          <button
            onClick={(e) => { e.stopPropagation(); setConfirmDelete(true); }}
            className="group-hover-delete absolute right-3 top-1/2 -translate-y-1/2 bg-transparent border-none cursor-pointer p-1.5 rounded-lg text-roam-lav-deep opacity-0 transition-opacity duration-150 hover:!text-roam-error hover:!opacity-100 focus:!opacity-100"
          >
            <svg viewBox="0 0 20 20" fill="currentColor" className="w-[15px] h-[15px]"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clipRule="evenodd" /></svg>
          </button>
        ) : (
          <div onClick={(e) => e.stopPropagation()} className="absolute right-2.5 top-1/2 -translate-y-1/2 flex items-center gap-1.5 bg-white border border-roam-error/25 rounded-[10px] px-2.5 py-1.5 shadow-[0_2px_12px_rgba(229,115,115,0.12)]">
            <span className="font-mono text-[9px] text-roam-error">delete?</span>
            <button onClick={() => onDelete(idea.id)} className="font-mono text-[9px] font-bold text-[#D32F2F] bg-transparent border-none cursor-pointer">yes</button>
            <button onClick={() => setConfirmDelete(false)} className="font-mono text-[9px] text-roam-text-muted bg-transparent border-none cursor-pointer">no</button>
          </div>
        )}
      </div>

      {expanded && (
        <div className="border-t border-roam-logan/[0.12] py-4 px-5 pb-[18px]">
          {pr?.placeSuggestions && pr.placeSuggestions.length > 1 ? (
            <div className="mb-3.5">
              <p className="label-mono mb-1.5">Choose location</p>
              <div className="flex flex-col gap-1.5">
                {pr.placeSuggestions.map((s) => (
                  <button
                    key={s.id}
                    onClick={() => selectPlace.mutate({ ideaId: idea.id, suggestionId: s.id })}
                    disabled={selectPlace.isPending}
                    className={`font-mono text-[11px] text-left px-2.5 py-2 rounded-lg border transition-colors ${
                      s.isSelected
                        ? "border-roam-logan-deep bg-roam-lavender text-roam-logan-deep"
                        : "border-roam-logan/20 text-roam-text-mid hover:border-roam-logan/40"
                    }`}
                  >
                    {s.placeName ?? s.rawName ?? "Unknown"} {s.isSelected ? "✓" : ""}
                  </button>
                ))}
              </div>
            </div>
          ) : idea.placeName ? (
            <div className="mb-3.5">
              <p className="label-mono mb-1.5">Location</p>
              <LocationLink placeName={idea.placeName} />
            </div>
          ) : null}

          {tags.length > 0 && (
            <div className="flex gap-1.5 flex-wrap mb-3.5">
              {tags.map((tag) => (
                <span key={tag} className="font-mono text-[9px] bg-roam-lavender text-roam-logan-deep px-2.5 py-1 rounded-full">{tag}</span>
              ))}
            </div>
          )}

          {idea.notes && (
            <div className="mb-3.5">
              <p className="label-mono mb-1.5">Notes</p>
              <p className="font-notes text-[13px] text-roam-text-mid leading-relaxed m-0">{idea.notes}</p>
            </div>
          )}

          <div className="pt-2.5 border-t border-roam-logan/10 flex justify-end">
            <button onClick={() => onPlanThis(idea.id)} className="btn-primary rounded-[11px] py-3 px-[18px] text-[9px] tracking-[2px] shadow-[0_2px_12px_rgba(74,64,112,0.2)]">
              plan this →
            </button>
          </div>
        </div>
      )}

      <style>{`div:hover .group-hover-delete { opacity: 1 !important; }`}</style>
    </div>
  );
}
