import type { User } from "firebase/auth";

const trustedProviders = new Set(
  (import.meta.env.VITE_TRUSTED_AUTH_PROVIDERS || "google.com,password")
    .split(",")
    .map((value: string) => value.trim())
    .filter(Boolean),
);

const getProviderIds = (inputUser: User | null) =>
  inputUser?.providerData?.map((provider) => provider.providerId) ?? [];

export function isTrustedProvider(inputUser: User | null): boolean {
  return getProviderIds(inputUser).some((provider) => trustedProviders.has(provider));
}

/** Email verified, or signed in with a provider we treat as verified (e.g. Google). */
export function userMeetsVerificationPolicy(u: User | null): boolean {
  return Boolean(u && (u.emailVerified || isTrustedProvider(u)));
}
