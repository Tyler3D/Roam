import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import type { Idea } from "@/models/idea";
import type { Plan } from "@/models/plan";

export const ideaKeys = {
  all: ["ideas"] as const,
};

function fetchIdeas() {
  return request<Idea[]>("/api/ideas");
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

function promoteIdea(id: string) {
  return request<Plan>(`/api/ideas/${id}/plan`, { method: "POST" });
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
    mutationFn: promoteIdea,
    onSuccess: (_plan, id) => {
      qc.setQueryData<Idea[]>(ideaKeys.all, (old) =>
        old?.filter((i) => i.id !== id)
      );
      qc.invalidateQueries({ queryKey: ["plans"] });
    },
  });
}
