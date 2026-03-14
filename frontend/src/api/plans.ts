import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { Plan, PlanUpdate } from "@/models/plan";

export const planKeys = {
  all: ["plans"] as const,
  drafts: ["plans", "drafts"] as const,
  detail: (id: string) => ["plans", id] as const,
};

function fetchPlans(ideaId?: string, status?: string) {
  const params = new URLSearchParams();
  if (ideaId) params.set("ideaId", ideaId);
  if (status) params.set("status", status);
  const qs = params.toString() ? `?${params.toString()}` : "";
  return request<Plan[]>(`/api/plans${qs}`);
}

function fetchPlan(id: string) {
  return request<Plan>(`/api/plans/${id}`);
}

function updatePlan(id: string, data: PlanUpdate) {
  return request<Plan>(`/api/plans/${id}`, { method: "PATCH", body: JSON.stringify(data) });
}

function suggestSlots(id: string) {
  return request<Record<string, unknown>[]>(`/api/plans/${id}/suggest-slots`, { method: "POST" });
}

function createCalendarEvent(planId: string, timezone?: string) {
  const qs = timezone ? `?timezone=${encodeURIComponent(timezone)}` : "";
  return request<Record<string, unknown>>(`/api/plans/${planId}/calendar${qs}`, { method: "POST" });
}

function addPlanMember(planId: string, userId: string) {
  return request<Plan>(`/api/plans/${planId}/members`, {
    method: "POST",
    body: JSON.stringify({ userId }),
  });
}

export function usePlans(ideaId?: string, status?: string) {
  return useQuery({
    queryKey: status === "draft"
      ? planKeys.drafts
      : ideaId
        ? [...planKeys.all, ideaId] as const
        : planKeys.all,
    queryFn: () => fetchPlans(ideaId, status),
  });
}

export function usePlansDrafts() {
  return usePlans(undefined, "draft");
}

export function usePlan(id: string | undefined) {
  return useQuery({
    queryKey: planKeys.detail(id ?? ""),
    queryFn: () => fetchPlan(id!),
    enabled: !!id,
  });
}

export function useUpdatePlan() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: PlanUpdate }) =>
      updatePlan(id, data),
    onSuccess: (_, { id }) => {
      qc.invalidateQueries({ queryKey: planKeys.all });
      qc.invalidateQueries({ queryKey: planKeys.drafts });
      qc.invalidateQueries({ queryKey: planKeys.detail(id) });
    },
  });
}

export function useSuggestSlots() {
  return useMutation({
    mutationFn: suggestSlots,
  });
}

export function useCreateCalendarEvent() {
  return useMutation({
    mutationFn: ({ planId, timezone }: { planId: string; timezone?: string }) =>
      createCalendarEvent(planId, timezone ?? Intl.DateTimeFormat().resolvedOptions().timeZone),
  });
}

export function useAddPlanMember(planId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (userId: string) => addPlanMember(planId, userId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: planKeys.all });
      qc.invalidateQueries({ queryKey: planKeys.drafts });
      qc.invalidateQueries({ queryKey: planKeys.detail(planId) });
    },
  });
}
