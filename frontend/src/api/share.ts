import { useQuery, useMutation } from "@tanstack/react-query";
import { requestNoAuth } from "@/lib/api";
import type { Plan } from "@/models/plan";
import type { RsvpRequest, RsvpResponse } from "@/models/share";

export const shareKeys = {
  plan: (shareCode: string) => ["share", shareCode] as const,
};

function fetchSharedPlan(shareCode: string) {
  return requestNoAuth<Plan>(`/api/share/${shareCode}`);
}

function rsvpToSharedPlan(shareCode: string, data: RsvpRequest) {
  return requestNoAuth<RsvpResponse>(`/api/share/${shareCode}/rsvp`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function useSharedPlan(shareCode: string | null) {
  return useQuery({
    queryKey: shareKeys.plan(shareCode ?? ""),
    queryFn: () => fetchSharedPlan(shareCode!),
    enabled: !!shareCode,
  });
}

export function useRsvp(shareCode: string | null) {
  return useMutation({
    mutationFn: (data: RsvpRequest) => rsvpToSharedPlan(shareCode!, data),
  });
}
