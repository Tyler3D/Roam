import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { Plan, PlanUpdate } from "@/models/plan";

export const planKeys = {
  all: ["plans"] as const,
  detail: (id: string) => ["plans", id] as const,
};

function fetchPlans() {
  return request<Plan[]>("/api/plans");
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

function createCalendarEvent(id: string) {
  return request<Record<string, unknown>>(`/api/plans/${id}/calendar`, { method: "POST" });
}

export function usePlans() {
  return useQuery({
    queryKey: planKeys.all,
    queryFn: fetchPlans,
  });
}

export function usePlan(id: string) {
  return useQuery({
    queryKey: planKeys.detail(id),
    queryFn: () => fetchPlan(id),
    enabled: !!id,
  });
}

export function useUpdatePlan() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: PlanUpdate }) =>
      updatePlan(id, data),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: planKeys.all });
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
    mutationFn: createCalendarEvent,
  });
}
