import { afterEach, describe, expect, it, vi } from "vitest";

describe("api request headers", () => {
  afterEach(() => {
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("adds dev bypass header when enabled", async () => {
    vi.doMock("@/utils/util", () => ({
      ROAM_API_BASE: "http://127.0.0.1:8000",
      DEV_AUTH_BYPASS_ENABLED: true,
      DEV_AUTH_BYPASS_SECRET: "local-dev-secret",
    }));
    vi.doMock("@/auth/firebase", () => ({
      firebaseAuth: { currentUser: null },
    }));
    vi.doMock("firebase/auth", () => ({
      getIdToken: vi.fn(),
    }));

    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({ ok: true }),
    }));
    vi.stubGlobal("fetch", fetchMock);

    const { request } = await import("./api");
    await request("/api/me");

    const call = fetchMock.mock.calls[0];
    const init = call[1] as RequestInit;
    const headers = init.headers as Record<string, string>;
    expect(headers["X-Dev-Auth-Bypass"]).toBe("local-dev-secret");
  });
});
