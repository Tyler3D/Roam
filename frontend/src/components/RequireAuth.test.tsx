import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/utils/util", () => ({
  DEV_AUTH_BYPASS_ENABLED: true,
}));

vi.mock("@/auth", () => ({
  useAuth: () => ({
    user: null,
    loading: false,
    isVerified: false,
    signOutUser: vi.fn(),
  }),
}));

vi.mock("@tanstack/react-query", async () => {
  const actual = await vi.importActual<typeof import("@tanstack/react-query")>("@tanstack/react-query");
  return {
    ...actual,
    useQuery: () => ({
      isError: false,
      isPending: false,
      isFetching: false,
      data: true,
      refetch: vi.fn(),
    }),
  };
});

import { RequireAuth } from "./RequireAuth";

describe("RequireAuth", () => {
  it("renders children directly when dev bypass is enabled", () => {
    render(
      <RequireAuth>
        <div>Bypass content</div>
      </RequireAuth>
    );

    expect(screen.getByText("Bypass content")).toBeInTheDocument();
  });
});
