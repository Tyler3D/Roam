import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { request } from "@/lib/api";
import { planKeys } from "./plans";

export type Task = {
  id: string;
  planId: string;
  assigneeId: string;
  assigneeFirstName: string;
  description: string;
  isCompleted: boolean;
  createdAt: string;
  completedAt: string | null;
};

function fetchTasks(planId: string) {
  return request<Task[]>(`/api/tasks/${planId}`);
}

function createTask(planId: string, data: { description: string; assigneeId: string }) {
  return request<Task>(`/api/tasks/${planId}`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

function updateTask(
  planId: string,
  taskId: string,
  data: { isCompleted: boolean }
) {
  return request<Task>(`/api/tasks/${planId}/${taskId}`, {
    method: "PATCH",
    body: JSON.stringify(data),
  });
}

function deleteTask(planId: string, taskId: string) {
  return request<void>(`/api/tasks/${planId}/${taskId}`, {
    method: "DELETE",
  });
}

export const taskKeys = {
  list: (planId: string) => ["tasks", planId] as const,
};

export function useTasks(planId: string | undefined) {
  return useQuery({
    queryKey: taskKeys.list(planId ?? ""),
    queryFn: () => fetchTasks(planId!),
    enabled: !!planId,
  });
}

export function useCreateTask(planId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (data: { description: string; assigneeId: string }) =>
      createTask(planId, data),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: planKeys.all });
      qc.invalidateQueries({ queryKey: planKeys.drafts });
      qc.invalidateQueries({ queryKey: planKeys.detail(planId) });
      qc.invalidateQueries({ queryKey: taskKeys.list(planId) });
    },
  });
}

export function useUpdateTask(planId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ taskId, isCompleted }: { taskId: string; isCompleted: boolean }) =>
      updateTask(planId, taskId, { isCompleted }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: planKeys.all });
      qc.invalidateQueries({ queryKey: planKeys.drafts });
      qc.invalidateQueries({ queryKey: planKeys.detail(planId) });
      qc.invalidateQueries({ queryKey: taskKeys.list(planId) });
    },
  });
}

export function useDeleteTask(planId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (taskId: string) => deleteTask(planId, taskId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: planKeys.all });
      qc.invalidateQueries({ queryKey: planKeys.drafts });
      qc.invalidateQueries({ queryKey: planKeys.detail(planId) });
      qc.invalidateQueries({ queryKey: taskKeys.list(planId) });
    },
  });
}
