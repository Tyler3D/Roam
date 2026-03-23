import { describe, expect, it } from "vitest";
import { hasUnresolvedAmbiguity } from "./orchestration";

describe("orchestration helpers", () => {
  it("detects unresolved ambiguity from pipeline uncertainty", () => {
    const idea = {
      pipelineResult: {
        rawOutput: {
          uncertainty: {
            requiresConfirmation: true,
          },
        },
      },
    } as never;

    expect(hasUnresolvedAmbiguity(idea)).toBe(true);
  });
});
