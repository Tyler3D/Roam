CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- Enums
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'jobStatus') THEN
    CREATE TYPE "jobStatus" AS ENUM ('processing', 'done', 'failed');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'visitStatus') THEN
    CREATE TYPE "visitStatus" AS ENUM ('want', 'been');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pinSource') THEN
    CREATE TYPE "pinSource" AS ENUM ('reel', 'manual');
  END IF;
END $$;

-- ============================================================
-- Users (unchanged)
-- ============================================================

CREATE TABLE IF NOT EXISTS "users" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "firebaseUid" text NOT NULL UNIQUE,
  "username" text NOT NULL UNIQUE,
  "email" text NOT NULL UNIQUE,
  "displayName" text,
  "photoUrl" text,
  "isActive" boolean NOT NULL DEFAULT false,
  "emailVerified" boolean NOT NULL DEFAULT false,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- Ingestion Jobs
-- ============================================================

CREATE TABLE IF NOT EXISTS "ingestion_jobs" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "reelUrl" text NOT NULL,
  "shareText" text,
  "lpTitle" text,
  "ogDescription" text,
  "ogKeywords" text,
  "status" "jobStatus" NOT NULL DEFAULT 'processing',
  "error" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "unique_user_reel"
  ON "ingestion_jobs" ("userId", "reelUrl");

-- ============================================================
-- Extractions (LLM-generated place suggestions per job)
-- ============================================================

CREATE TABLE IF NOT EXISTS "extractions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "jobId" uuid NOT NULL REFERENCES "ingestion_jobs"("id") ON DELETE CASCADE,
  "placeName" text,
  "placeAddress" text,
  "category" text,
  "latitude" double precision,
  "longitude" double precision,
  "googlePlaceId" text,
  "confidence" double precision,
  "rawLlmOutput" jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_extractions_jobId"
  ON "extractions" ("jobId");

-- ============================================================
-- Activity Pins (user-confirmed places)
-- ============================================================

CREATE TABLE IF NOT EXISTS "activity_pins" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId" uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "extractionId" uuid REFERENCES "extractions"("id") ON DELETE SET NULL,
  "title" text NOT NULL,
  "category" text,
  "placeName" text,
  "placeAddress" text,
  "latitude" double precision,
  "longitude" double precision,
  "googlePlaceId" text,
  "rating" integer CHECK ("rating" >= 1 AND "rating" <= 5),
  "visitStatus" "visitStatus" NOT NULL DEFAULT 'want',
  "notes" text,
  "thumbnailUrl" text,
  "reelUrl" text,
  "source" "pinSource" NOT NULL DEFAULT 'reel',
  "lastInteractedAt" timestamptz,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_activity_pins_userId"
  ON "activity_pins" ("userId");

CREATE INDEX IF NOT EXISTS "idx_activity_pins_category"
  ON "activity_pins" ("category");
