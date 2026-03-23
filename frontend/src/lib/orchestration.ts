import type { Idea } from "@/models/idea";

export type OrchestrationStep = {
  name: string;
  status: string;
  durationMs?: number;
  errorCode?: string;
};

export type UncertaintyFlags = {
  queryTooGeneric?: boolean;
  inviteesAmbiguous?: boolean;
  taskAssignmentsAmbiguous?: boolean;
  datetimeUncertain?: boolean;
};

export type UncertaintyState = {
  requiresConfirmation?: boolean;
  confidence?: number;
  flags?: UncertaintyFlags;
  reasons?: string[];
};

type RawOutputShape = {
  steps?: OrchestrationStep[];
  uncertainty?: UncertaintyState;
};

export function getIdeaRawOutput(idea: Idea): RawOutputShape {
  return (idea.pipelineResult?.rawOutput as RawOutputShape | undefined) ?? {};
}

export function getIdeaUncertainty(idea: Idea): UncertaintyState | null {
  const uncertainty = getIdeaRawOutput(idea).uncertainty;
  return uncertainty ?? null;
}

export function getIdeaOrchestrationSteps(idea: Idea): OrchestrationStep[] {
  return getIdeaRawOutput(idea).steps ?? [];
}

export function hasUnresolvedAmbiguity(idea: Idea): boolean {
  const uncertainty = getIdeaUncertainty(idea);
  return Boolean(uncertainty?.requiresConfirmation);
}
