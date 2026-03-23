const rawEnvironment = import.meta.env.VITE_ENVIRONMENT;
const environment = rawEnvironment === "dev" || rawEnvironment === "prod" ? rawEnvironment : "dev";

if (rawEnvironment !== "dev" && rawEnvironment !== "prod") {
  console.warn(
    "[config] VITE_ENVIRONMENT missing/invalid. Expected 'dev' or 'prod'; defaulting to 'dev'."
  );
}

export const IS_DEV: boolean = environment === "dev";
export const ROAM_DOMAIN: string = import.meta.env.VITE_ROAM_DOMAIN || "localhost:3000";
export const ROAM_API_BASE: string = import.meta.env.VITE_API_BASE_URL || "http://127.0.0.1:8000";
export const DEV_AUTH_BYPASS_ENABLED: boolean =
  import.meta.env.VITE_DEV_AUTH_BYPASS === "true";
export const DEV_AUTH_BYPASS_SECRET: string = import.meta.env.VITE_DEV_AUTH_BYPASS_SECRET || "";

/** Fire GA4 event if gtag is available */
export function googleAnalyticsTrackEvent(
  eventName: string,
  params?: Record<string, string | number | boolean>
) {
  if (typeof window !== "undefined" && window.gtag) {
    window.gtag("event", eventName, params);
  }
}