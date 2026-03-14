import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { useIdeas } from "@/api/ideas";
import { MapView } from "@/components/MapView";
import { Spinner } from "@/components/ui/spinner";
import { EmptyState } from "@/components/ui/empty-state";
import type { Idea } from "@/models/idea";
import type { DatePin, DatePinType } from "@/types/datePin";

const categoryToType: Record<string, DatePinType> = {
  "food-drink": "restaurant",
  outdoors: "outdoor",
  "arts-culture": "event",
  nightlife: "event",
  fitness: "outdoor",
};

function ideaToDatePin(idea: Idea): DatePin | null {
  const lat = idea.placeLatitude;
  const lng = idea.placeLongitude;
  if (lat == null || lng == null) return null;

  const category = idea.pipelineResult?.category;
  const type = (category && categoryToType[category]) ?? "event";

  const status =
    idea.status === "planned" ? "planned" : "saved";

  return {
    id: idea.id,
    title: idea.displayName ?? idea.title,
    notes: idea.notes || undefined,
    link: idea.sourceUrl || undefined,
    location: {
      name: idea.placeName ?? "",
      lat,
      lng,
    },
    type,
    status,
    createdAt: new Date(idea.createdAt),
  };
}

export default function IdeaMap() {
  const navigate = useNavigate();
  const { data: ideas = [], isLoading } = useIdeas();

  const pins = useMemo(() => {
    return ideas
      .map(ideaToDatePin)
      .filter((pin): pin is DatePin => pin !== null);
  }, [ideas]);

  const handlePinClick = (pin: DatePin) => {
    navigate(`/ideas/${pin.id}`);
  };

  if (isLoading) {
    return (
      <div className="max-w-[480px] mx-auto pt-5 px-4">
        <div className="text-center py-[60px]">
          <Spinner text="loading map..." />
        </div>
      </div>
    );
  }

  return (
    <div className="h-[calc(100dvh-140px)] pt-5 px-4">
      {pins.length === 0 ? (
        <EmptyState
          icon="🗺"
          title="no locations yet"
          subtitle="Add ideas with places to see them on the map"
        />
      ) : (
        <MapView pins={pins} onPinClick={handlePinClick} />
      )}
    </div>
  );
}
