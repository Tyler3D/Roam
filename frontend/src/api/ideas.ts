import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { Idea } from "@/models/idea";
import type { Plan } from "@/models/plan";

export const ideaKeys = {
  all: ["ideas"] as const,
  detail: (id: string) => ["ideas", id] as const,
};

function fetchIdeas() {
  return request<Idea[]>("/api/ideas");
}

function fetchIdea(id: string) {
  return request<Idea>(`/api/ideas/${id}`);
}

function updateIdea(id: string, data: Partial<Record<string, unknown>>) {
  return request<Idea>(`/api/ideas/${id}`, {
    method: "PATCH",
    body: JSON.stringify(data),
  });
}

function createIdea(title: string) {
  return request<Idea>("/api/ideas", { method: "POST", body: JSON.stringify({ title }) });
}

function deleteIdea(id: string) {
  return request<void>(`/api/ideas/${id}`, { method: "DELETE" });
}

function interpretIdea(id: string) {
  return request<Idea>(`/api/ideas/${id}/interpret`, { method: "POST" });
}

export type PromoteIdeaPayload = {
  confirmedInvitees?: string[];
  confirmedTaskAssignments?: string | null;
  confirmedSearchQuery?: string | null;
  ambiguityAcknowledged?: boolean;
};

function promoteIdea(id: string, payload?: PromoteIdeaPayload) {
  return request<Plan>(`/api/ideas/${id}/plan`, {
    method: "POST",
    body: JSON.stringify(payload ?? {}),
  });
}

function selectPlaceSuggestion(ideaId: string, suggestionId: string) {
  return request<Idea>(`/api/ideas/${ideaId}/place-suggestions/${suggestionId}`, { method: "PATCH" });
}

export function useIdeas() {
  return useQuery({
    queryKey: ideaKeys.all,
    queryFn: fetchIdeas,
  });
}

export function useCreateIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: createIdea,
    onSuccess: (newIdea) => {
      qc.setQueryData<Idea[]>(ideaKeys.all, (old) =>
        old ? [newIdea, ...old] : [newIdea]
      );
    },
  });
}

export function useDeleteIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: deleteIdea,
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: ideaKeys.all });
      const prev = qc.getQueryData<Idea[]>(ideaKeys.all);
      qc.setQueryData<Idea[]>(ideaKeys.all, (old) =>
        old?.filter((i) => i.id !== id)
      );
      return { prev };
    },
    onError: (_err, _id, ctx) => {
      if (ctx?.prev) qc.setQueryData(ideaKeys.all, ctx.prev);
    },
  });
}

export function useInterpretIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: interpretIdea,
    onSuccess: (enriched) => {
      qc.setQueryData<Idea[]>(ideaKeys.all, (old) =>
        old?.map((i) => (i.id === enriched.id ? enriched : i))
      );
    },
  });
}

export function usePromoteIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, payload }: { id: string; payload?: PromoteIdeaPayload }) =>
      promoteIdea(id, payload),
    onSuccess: (_plan, vars) => {
      qc.setQueryData<Idea[]>(ideaKeys.all, (old) =>
        old?.filter((i) => i.id !== vars.id)
      );
      qc.invalidateQueries({ queryKey: ["plans"] });
    },
  });
}

export function useSelectPlaceSuggestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ ideaId, suggestionId }: { ideaId: string; suggestionId: string }) =>
      selectPlaceSuggestion(ideaId, suggestionId),
    onSuccess: (updated) => {
      qc.setQueryData<Idea[]>(ideaKeys.all, (old) =>
        old?.map((i) => (i.id === updated.id ? updated : i))
      );
      qc.setQueryData(ideaKeys.detail(updated.id), updated);
    },
  });
}

export function useIdea(id: string | undefined) {
  return useQuery({
    queryKey: ideaKeys.detail(id ?? ""),
    queryFn: () => fetchIdea(id!),
    enabled: !!id,
  });
}

export function useUpdateIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<Record<string, unknown>> }) =>
      updateIdea(id, data),
    onSuccess: (updated) => {
      qc.setQueryData<Idea[]>(ideaKeys.all, (old) =>
        old?.map((i) => (i.id === updated.id ? updated : i))
      );
      qc.setQueryData(ideaKeys.detail(updated.id), updated);
    },
  });
}

