const environment = import.meta.env.VITE_ENVIRONMENT;

if (environment !== "dev" && environment !== "staging" && environment !== "prod") {
  throw new Error("ENVIRONMENT must be 'dev', 'staging', or 'prod'.");
};

export const IS_DEV: boolean = environment === "dev";

export const ROAM_DOMAIN: string = import.meta.env.VITE_ROAM_DOMAIN;
export const ROAM_API_BASE: string = import.meta.env.VITE_API_BASE_URL;

/** Fire GA4 event if gtag is available */
export function googleAnalyticsTrackEvent(
  eventName: string,
  params?: Record<string, string | number | boolean>
) {
  if (typeof window !== "undefined" && window.gtag) {
    window.gtag("event", eventName, params);
  }
}