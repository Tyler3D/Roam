import type { components } from "./generated/api";

// Re-export OpenAPI-generated enums (single source of truth from backend schema)
export {
  PlanStatus,
  RsvpStatus,
  MemberRole,
} from "./generated/api";

export type Plan = components["schemas"]["PlanRead"];
export type PlanMember = components["schemas"]["PlanMemberRead"];
export type PlanUpdate = components["schemas"]["PlanUpdate"];
