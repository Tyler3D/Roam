import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
  type InfiniteData,
  type QueryClient,
} from "@tanstack/react-query";
import { useMemo } from "react";
import { request } from "@/lib/api";
import type { Idea, IdeaPageRead } from "@/models/idea";
import type { Plan } from "@/models/plan";

export const ideaKeys = {
  all: ["ideas"] as const,
  /** Full idea list for map (single queryFn that walks cursor pages). */
  mapAll: ["ideas", "mapAll"] as const,
  detail: (id: string) => ["ideas", id] as const,
};

function fetchIdeasPage(cursor: string | undefined): Promise<IdeaPageRead> {
  const params = new URLSearchParams();
  params.set("limit", "30");
  if (cursor) params.set("cursor", cursor);
  if (!cursor) params.set("include_total", "true");
  return request<IdeaPageRead>(`/api/ideas?${params.toString()}`);
}

function fetchIdeasPageNoTotal(cursor: string | undefined): Promise<IdeaPageRead> {
  const params = new URLSearchParams();
  params.set("limit", "30");
  if (cursor) params.set("cursor", cursor);
  return request<IdeaPageRead>(`/api/ideas?${params.toString()}`);
}

const MAX_MAP_IDEA_PAGES = 100;

async function fetchAllIdeasForMap(): Promise<Idea[]> {
  const out: Idea[] = [];
  let cursor: string | undefined;
  for (let p = 0; p < MAX_MAP_IDEA_PAGES; p++) {
    const page = await fetchIdeasPageNoTotal(cursor);
    out.push(...(page.items ?? []));
    if (!page.hasMore || !page.nextCursor) break;
    cursor = page.nextCursor;
  }
  return out;
}

function invalidateIdeasMapAll(qc: QueryClient) {
  void qc.invalidateQueries({ queryKey: ideaKeys.mapAll });
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

function promoteIdea(id: string) {
  return request<Plan>(`/api/ideas/${id}/plan`, { method: "POST" });
}

function selectPlaceSuggestion(ideaId: string, suggestionId: string) {
  return request<Idea>(`/api/ideas/${ideaId}/place-suggestions/${suggestionId}`, { method: "PATCH" });
}

export function useIdeas() {
  const infinite = useInfiniteQuery({
    queryKey: ideaKeys.all,
    queryFn: ({ pageParam }) => fetchIdeasPage(pageParam as string | undefined),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) =>
      last.hasMore && last.nextCursor ? last.nextCursor : undefined,
  });
  const ideas = useMemo(
    () => infinite.data?.pages.flatMap((p) => p.items ?? []) ?? [],
    [infinite.data]
  );
  return {
    ...infinite,
    ideas,
    /** @deprecated Prefer `ideas`; kept for `const { data: ideas } = useIdeas()` */
    data: ideas,
  };
}

/** All ideas for map pins: one `queryFn` that follows cursors (no `useEffect`). */
export function useIdeasForMap() {
  return useQuery({
    queryKey: ideaKeys.mapAll,
    queryFn: fetchAllIdeasForMap,
  });
}

export function useCreateIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: createIdea,
    onSuccess: (newIdea) => {
      qc.setQueryData<InfiniteData<IdeaPageRead>>(ideaKeys.all, (old) => {
        if (!old?.pages.length) {
          return {
            pages: [
              {
                items: [newIdea],
                hasMore: false,
                nextCursor: null,
                totalCount: 1,
              },
            ],
            pageParams: [undefined],
          };
        }
        const pages = [...old.pages];
        const first = pages[0];
        pages[0] = {
          ...first,
          items: [newIdea, ...(first.items ?? [])],
          totalCount:
            first.totalCount != null ? first.totalCount + 1 : first.totalCount,
        };
        return { ...old, pages };
      });
      invalidateIdeasMapAll(qc);
    },
  });
}

export function useDeleteIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: deleteIdea,
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: ideaKeys.all });
      const prev = qc.getQueryData<InfiniteData<IdeaPageRead>>(ideaKeys.all);
      qc.setQueryData<InfiniteData<IdeaPageRead>>(ideaKeys.all, (old) => {
        if (!old) return old;
        return {
          ...old,
          pages: old.pages.map((p, idx) => ({
            ...p,
            items: (p.items ?? []).filter((i) => i.id !== id),
            totalCount:
              idx === 0 && p.totalCount != null
                ? Math.max(0, p.totalCount - 1)
                : p.totalCount,
          })),
        };
      });
      return { prev };
    },
    onError: (_err, _id, ctx) => {
      if (ctx?.prev) qc.setQueryData(ideaKeys.all, ctx.prev);
    },
    onSettled: () => {
      invalidateIdeasMapAll(qc);
    },
  });
}

export function useInterpretIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: interpretIdea,
    onSuccess: (enriched) => {
      qc.setQueryData<InfiniteData<IdeaPageRead>>(ideaKeys.all, (old) => {
        if (!old) return old;
        return {
          ...old,
          pages: old.pages.map((p) => ({
            ...p,
            items: (p.items ?? []).map((i) =>
              i.id === enriched.id ? enriched : i
            ),
          })),
        };
      });
      invalidateIdeasMapAll(qc);
    },
  });
}

export function usePromoteIdea() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: promoteIdea,
    onSuccess: (_plan, id) => {
      qc.setQueryData<InfiniteData<IdeaPageRead>>(ideaKeys.all, (old) => {
        if (!old) return old;
        return {
          ...old,
          pages: old.pages.map((p, idx) => ({
            ...p,
            items: (p.items ?? []).filter((i) => i.id !== id),
            totalCount:
              idx === 0 && p.totalCount != null
                ? Math.max(0, p.totalCount - 1)
                : p.totalCount,
          })),
        };
      });
      qc.invalidateQueries({ queryKey: ["plans"] });
      invalidateIdeasMapAll(qc);
    },
  });
}

export function useSelectPlaceSuggestion() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ ideaId, suggestionId }: { ideaId: string; suggestionId: string }) =>
      selectPlaceSuggestion(ideaId, suggestionId),
    onSuccess: (updated) => {
      qc.setQueryData<InfiniteData<IdeaPageRead>>(ideaKeys.all, (old) => {
        if (!old) return old;
        return {
          ...old,
          pages: old.pages.map((p) => ({
            ...p,
            items: (p.items ?? []).map((i) =>
              i.id === updated.id ? updated : i
            ),
          })),
        };
      });
      qc.setQueryData(ideaKeys.detail(updated.id), updated);
      invalidateIdeasMapAll(qc);
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
      qc.setQueryData<InfiniteData<IdeaPageRead>>(ideaKeys.all, (old) => {
        if (!old) return old;
        return {
          ...old,
          pages: old.pages.map((p) => ({
            ...p,
            items: (p.items ?? []).map((i) =>
              i.id === updated.id ? updated : i
            ),
          })),
        };
      });
      qc.setQueryData(ideaKeys.detail(updated.id), updated);
      invalidateIdeasMapAll(qc);
    },
  });
}
