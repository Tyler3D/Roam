type TelemetryPayload = Record<string, unknown>;

export function trackEvent(event: string, payload: TelemetryPayload = {}) {
  if (typeof window !== "undefined") {
    window.dispatchEvent(
      new CustomEvent("roam:telemetry", {
        detail: { event, payload, ts: Date.now() },
      })
    );
  }
  // Temporary local sink while formal analytics plumbing is added.
  console.info("[roam-telemetry]", event, payload);
}
