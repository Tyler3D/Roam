import { useQuery } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { Place } from "@/models/place";

export const placeKeys = {
  search: (q: string) => ["places", "search", q] as const,
};

function searchPlaces(q: string) {
  return request<Place | null>(`/api/places/search?q=${encodeURIComponent(q)}`);
}

export function useSearchPlaces(query: string) {
  return useQuery({
    queryKey: placeKeys.search(query),
    queryFn: () => searchPlaces(query),
    enabled: query.length >= 2,
  });
}
