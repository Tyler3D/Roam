CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pinStatus') THEN
    CREATE TYPE "pinStatus" AS ENUM ('saved', 'planned', 'done');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pinSource') THEN
    CREATE TYPE "pinSource" AS ENUM ('manual', 'reelIngest');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'shareRole') THEN
    CREATE TYPE "shareRole" AS ENUM ('collaborator', 'viewer');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activityType') THEN
    CREATE TYPE "activityType" AS ENUM (
      'dinner',
      'walk',
      'DIY',
      'trip',
      'event',
      'cozyNight',
      'chaoticNight'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'effortLevel') THEN
    CREATE TYPE "effortLevel" AS ENUM ('lowEffort', 'planned', 'saturday');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'contextType') THEN
    CREATE TYPE "contextType" AS ENUM ('date', 'friends', 'solo', 'travel');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reelPlatform') THEN
    CREATE TYPE "reelPlatform" AS ENUM ('tiktok', 'instagram');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reelJobStatus') THEN
    CREATE TYPE "reelJobStatus" AS ENUM ('queued', 'processing', 'done', 'failed');
  END IF;
END $$;

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

CREATE TABLE IF NOT EXISTS "datePins" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ownerId" uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "title" text NOT NULL,
  "notes" text,
  "link" text,
  "status" "pinStatus" NOT NULL DEFAULT 'saved',
  "tags" text[],
  "locationName" text,
  "locationLat" double precision,
  "locationLng" double precision,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  "lastViewedAt" timestamptz,
  "source" "pinSource" NOT NULL DEFAULT 'manual',
  "sourceRef" text
);

CREATE TABLE IF NOT EXISTS "pinShares" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "pinId" uuid NOT NULL REFERENCES "datePins"("id") ON DELETE CASCADE,
  "userId" uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "role" "shareRole" NOT NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "pinSharesUniquePinUser" UNIQUE ("pinId", "userId")
);

CREATE TABLE IF NOT EXISTS "mlExtractions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "pinId" uuid NOT NULL REFERENCES "datePins"("id") ON DELETE CASCADE,
  "activityType" "activityType",
  "effortLevel" "effortLevel",
  "context" "contextType",
  "constraints" jsonb,
  "locationSuggestion" jsonb,
  "suggestedTags" text[],
  "confidence" jsonb,
  "rawModelOutput" jsonb,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "reelIngestJobs" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "platform" "reelPlatform" NOT NULL,
  "senderUserId" uuid REFERENCES "users"("id") ON DELETE SET NULL,
  "reelUrl" text NOT NULL,
  "rawPayload" jsonb,
  "status" "reelJobStatus" NOT NULL DEFAULT 'queued',
  "error" text,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "datePinsOwnerIdIdx" ON "datePins" ("ownerId");
CREATE INDEX IF NOT EXISTS "datePinsStatusIdx" ON "datePins" ("status");
CREATE INDEX IF NOT EXISTS "pinSharesUserIdIdx" ON "pinShares" ("userId");

