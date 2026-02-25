const environment = import.meta.env.VITE_ENVIRONMENT;

if (environment !== "dev" && environment !== "prod") {
  throw new Error("ENVIRONMENT must be 'dev' or 'prod'.");
};

export const IS_DEV: boolean = environment === "dev";