CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- Enums
-- ============================================================
-- planStatus: draft | confirmed | completed | cancelled
-- rsvpStatus: pending | accepted | declined
-- memberRole: organizer | member
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ideaStatus') THEN
    CREATE TYPE "ideaStatus" AS ENUM ('captured', 'suggesting', 'ready', 'planned');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'jobStatus') THEN
    CREATE TYPE "jobStatus" AS ENUM ('processing', 'done', 'failed');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'planStatus') THEN
    CREATE TYPE "planStatus" AS ENUM ('draft', 'confirmed', 'completed', 'cancelled');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rsvpStatus') THEN
    CREATE TYPE "rsvpStatus" AS ENUM ('pending', 'accepted', 'declined');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'memberRole') THEN
    CREATE TYPE "memberRole" AS ENUM ('organizer', 'member');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'friendshipStatus') THEN
    CREATE TYPE "friendshipStatus" AS ENUM ('pending', 'accepted');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notificationType') THEN
    CREATE TYPE "notificationType" AS ENUM (
      'invite_received',
      'rsvp_accepted',
      'rsvp_declined',
      'task_assigned',
      'plan_reminder',
      'rate_prompt',
      'friend_request',
      'added_to_collection'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'savedReelStatus') THEN
    CREATE TYPE "savedReelStatus" AS ENUM ('processing', 'needs_review', 'promoted', 'failed');
  END IF;
END $$;

-- ============================================================
-- Users
-- ============================================================

CREATE TABLE IF NOT EXISTS "users" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "firebaseUid"   text UNIQUE,
  "username"      text UNIQUE,
  "email"         text UNIQUE,
  "firstName"     text NOT NULL DEFAULT '',
  "lastName"      text NOT NULL DEFAULT '',
  "phone"         text,
  "photoUrl"      text,
  "city"          text,
  "interestTags"  jsonb DEFAULT '[]',
  "isActive"      boolean NOT NULL DEFAULT false,
  "isOnboarded"   boolean NOT NULL DEFAULT false,
  "isGuestUser"   boolean NOT NULL DEFAULT false,
  "emailVerified" boolean NOT NULL DEFAULT false,
  "createdAt"     timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- Places (canonical, deduplicated by googlePlaceId)
-- ============================================================

CREATE TABLE IF NOT EXISTS "places" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "googlePlaceId" text UNIQUE,
  "name"          text NOT NULL,
  "address"       text,
  "city"          text,
  "latitude"      double precision,
  "longitude"     double precision,
  "category"      text,
  "openingHours"  jsonb DEFAULT '[]',
  "placeTypes"    text[] DEFAULT '{}',
  "createdAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_places_city"
  ON "places" ("city");

CREATE INDEX IF NOT EXISTS "idx_places_category"
  ON "places" ("category");

-- ============================================================
-- Friendships
-- ============================================================

CREATE TABLE IF NOT EXISTS "friendships" (
  "id"          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "requesterId" uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "addresseeId" uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "status"      "friendshipStatus" NOT NULL DEFAULT 'pending',
  "createdAt"   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "friendships_no_self" CHECK ("requesterId" <> "addresseeId")
);

CREATE UNIQUE INDEX IF NOT EXISTS "unique_friendship_pair"
  ON "friendships" (LEAST("requesterId","addresseeId"), GREATEST("requesterId","addresseeId"));

CREATE INDEX IF NOT EXISTS "idx_friendships_addressee"
  ON "friendships" ("addresseeId");

-- ============================================================
-- Ideas (lightweight capture -- raw user input)
-- ============================================================

CREATE TABLE IF NOT EXISTS "ideas" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"        uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "title"         text NOT NULL,
  "notes"         text DEFAULT '',
  "sourceUrl"     text DEFAULT '',
  "placeId"       uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "displayName"  text,
  "status"        "ideaStatus" NOT NULL DEFAULT 'captured',
  "savedReelId"   uuid,
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_ideas_userId"
  ON "ideas" ("userId", "createdAt" DESC);

CREATE INDEX IF NOT EXISTS "idx_ideas_status"
  ON "ideas" ("status");

CREATE INDEX IF NOT EXISTS "idx_ideas_savedReelId"
  ON "ideas" ("savedReelId", "createdAt" DESC);

-- ============================================================
-- Collections (shared lists + per-user "My saves")
-- ============================================================

CREATE TABLE IF NOT EXISTS "collections" (
  "id"                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "creatorId"          uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "name"               text NOT NULL DEFAULT '',
  "description"        text,
  "isPersonalDefault"  boolean NOT NULL DEFAULT false,
  "createdAt"          timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "idx_collections_one_personal_per_creator"
  ON "collections" ("creatorId")
  WHERE "isPersonalDefault";

CREATE INDEX IF NOT EXISTS "idx_collections_creatorId"
  ON "collections" ("creatorId");

CREATE TABLE IF NOT EXISTS "collection_members" (
  "collectionId"  uuid NOT NULL REFERENCES "collections"("id") ON DELETE CASCADE,
  "userId"        uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "joinedAt"      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("collectionId", "userId")
);

CREATE INDEX IF NOT EXISTS "idx_collection_members_userId"
  ON "collection_members" ("userId");

CREATE TABLE IF NOT EXISTS "collection_ideas" (
  "collectionId"  uuid NOT NULL REFERENCES "collections"("id") ON DELETE CASCADE,
  "ideaId"        uuid NOT NULL REFERENCES "ideas"("id") ON DELETE CASCADE,
  "addedAt"       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("collectionId", "ideaId")
);

CREATE INDEX IF NOT EXISTS "idx_collection_ideas_ideaId"
  ON "collection_ideas" ("ideaId");

-- ============================================================
-- Plans
-- ============================================================

CREATE TABLE IF NOT EXISTS "plans" (
  "id"               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "creatorId"        uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "placeId"          uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "ideaId"           uuid REFERENCES "ideas"("id") ON DELETE SET NULL,
  "title"            text NOT NULL,
  "scheduledAt"      timestamptz,
  "status"           "planStatus" NOT NULL DEFAULT 'draft',
  "shareCode"        text NOT NULL UNIQUE,
  "rawPrompt"        text,
  "estimatedMinutes" integer DEFAULT 60,
  "calendarEventId"  text,
  "partySize"        integer DEFAULT 1,
  "rating"           integer CHECK ("rating" IS NULL OR ("rating" >= 1 AND "rating" <= 5)),
  "taskNotes"        text DEFAULT '',
  "createdAt"        timestamptz NOT NULL DEFAULT now(),
  "updatedAt"        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_plans_creatorId"
  ON "plans" ("creatorId");

CREATE INDEX IF NOT EXISTS "idx_plans_scheduledAt"
  ON "plans" ("scheduledAt");

CREATE INDEX IF NOT EXISTS "idx_plans_placeId"
  ON "plans" ("placeId");

-- ============================================================
-- Plan Members (attendees + RSVP)
-- ============================================================

CREATE TABLE IF NOT EXISTS "plan_members" (
  "id"          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "planId"      uuid NOT NULL REFERENCES "plans"("id") ON DELETE CASCADE,
  "userId"      uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "role"        "memberRole" NOT NULL DEFAULT 'member',
  "rsvpStatus"  "rsvpStatus" NOT NULL DEFAULT 'pending',
  "inviteToken" text,
  "rating"      integer CHECK ("rating" >= 1 AND "rating" <= 5),
  "invitedAt"   timestamptz NOT NULL DEFAULT now(),
  "respondedAt" timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS "unique_plan_user"
  ON "plan_members" ("planId", "userId");

CREATE INDEX IF NOT EXISTS "idx_plan_members_userId"
  ON "plan_members" ("userId");

-- ============================================================
-- Plan Tasks
-- ============================================================

CREATE TABLE IF NOT EXISTS "plan_tasks" (
  "id"          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "planId"      uuid NOT NULL REFERENCES "plans"("id") ON DELETE CASCADE,
  "assigneeId"  uuid NOT NULL REFERENCES "plan_members"("id") ON DELETE CASCADE,
  "description" text NOT NULL,
  "isCompleted" boolean NOT NULL DEFAULT false,
  "createdAt"   timestamptz NOT NULL DEFAULT now(),
  "completedAt" timestamptz
);

CREATE INDEX IF NOT EXISTS "idx_plan_tasks_planId"
  ON "plan_tasks" ("planId");

-- ============================================================
-- Plan Messages (NL command chat log per plan)
-- ============================================================

CREATE TABLE IF NOT EXISTS "plan_messages" (
  "id"       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "planId"   uuid NOT NULL REFERENCES "plans"("id") ON DELETE CASCADE,
  "userId"   uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "content"  text NOT NULL,
  "isSystem" boolean NOT NULL DEFAULT false,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_plan_messages_planId"
  ON "plan_messages" ("planId", "createdAt");

-- ============================================================
-- User OAuth Tokens (encrypted at rest)
-- ============================================================

CREATE TABLE IF NOT EXISTS "user_oauth_tokens" (
  "id"                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"                uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "provider"              text NOT NULL,
  "encryptedAccessToken"  text NOT NULL,
  "encryptedRefreshToken" text,
  "expiresAt"             timestamptz,
  "createdAt"             timestamptz NOT NULL DEFAULT now(),
  "updatedAt"             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "unique_user_oauth_provider" UNIQUE ("userId", "provider")
);

CREATE INDEX IF NOT EXISTS "idx_user_oauth_tokens_userId"
  ON "user_oauth_tokens" ("userId");

-- ============================================================
-- Notifications
-- ============================================================

CREATE TABLE IF NOT EXISTS "notifications" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"        uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "type"          "notificationType" NOT NULL,
  "planId"        uuid REFERENCES "plans"("id") ON DELETE CASCADE,
  "collectionId"  uuid REFERENCES "collections"("id") ON DELETE SET NULL,
  "title"         text NOT NULL,
  "body"          text,
  "isRead"        boolean NOT NULL DEFAULT false,
  "createdAt"     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE "notifications" ADD COLUMN IF NOT EXISTS "collectionId" uuid REFERENCES "collections"("id") ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS "idx_notifications_userId"
  ON "notifications" ("userId", "isRead", "createdAt" DESC);

-- ============================================================
-- Reel Ingestion Jobs (reel -> place discovery pipeline)
-- ============================================================

CREATE TABLE IF NOT EXISTS "reel_ingestion_jobs" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"        uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "reelUrl"       text NOT NULL,
  "shareText"     text,
  "reelTitle"     text,
  "ogDescription" text,
  "ogKeywords"    text,
  "status"        "jobStatus" NOT NULL DEFAULT 'processing',
  "error"         text,
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "unique_user_reel"
  ON "reel_ingestion_jobs" ("userId", "reelUrl");

-- ============================================================
-- Saved reels (server-side grid + GCS thumbnail)
-- ============================================================

CREATE TABLE IF NOT EXISTS "saved_reels" (
  "id"                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"              uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "jobId"               uuid NOT NULL UNIQUE REFERENCES "reel_ingestion_jobs"("id") ON DELETE CASCADE,
  "thumbnailObjectPath" text,
  "reelUrl"             text NOT NULL,
  "title"               text NOT NULL DEFAULT '',
  "status"              "savedReelStatus" NOT NULL DEFAULT 'processing',
  "ingestRetryCount"    integer NOT NULL DEFAULT 0,
  "createdAt"           timestamptz NOT NULL DEFAULT now(),
  "updatedAt"           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE "saved_reels" ADD COLUMN IF NOT EXISTS "ingestRetryCount" integer NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS "idx_saved_reels_userId_createdAt"
  ON "saved_reels" ("userId", "createdAt" DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ideas_savedReelId_fkey'
      AND conrelid = '"ideas"'::regclass
  ) THEN
    ALTER TABLE "ideas" ADD CONSTRAINT "ideas_savedReelId_fkey"
      FOREIGN KEY ("savedReelId") REFERENCES "saved_reels"("id") ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS "reel_ingest_candidates" (
  "id"               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "savedReelId"      uuid NOT NULL REFERENCES "saved_reels"("id") ON DELETE CASCADE,
  "sortIndex"        integer NOT NULL DEFAULT 0,
  "llmRawOutput"     jsonb NOT NULL DEFAULT '{}',
  "resolvedPlaceId"  uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "promotedIdeaId"   uuid REFERENCES "ideas"("id") ON DELETE SET NULL,
  "createdAt"        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_reel_ingest_candidates_savedReelId_sort"
  ON "reel_ingest_candidates" ("savedReelId", "sortIndex");

-- ============================================================
-- Pipeline Results (unified output from scribble + reel pipelines)
-- ============================================================

CREATE TABLE IF NOT EXISTS "pipeline_results" (
  "id"               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "ideaId"           uuid REFERENCES "ideas"("id") ON DELETE CASCADE,
  "jobId"            uuid REFERENCES "reel_ingestion_jobs"("id") ON DELETE SET NULL,
  "source"           text NOT NULL,
  "refinedTitle"     text,
  "category"         text,
  "estimatedMinutes" integer,
  "promptVersion"    text,
  "modelName"        text,
  "rawOutput"        jsonb DEFAULT '{}',
  "createdAt"        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "reel_result_has_idea" CHECK ("jobId" IS NULL OR "ideaId" IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS "idx_pipeline_results_ideaId"
  ON "pipeline_results" ("ideaId");

CREATE INDEX IF NOT EXISTS "idx_pipeline_results_jobId"
  ON "pipeline_results" ("jobId");

-- ============================================================
-- Place Suggestions (1-3 candidates per pipeline result)
-- ============================================================

CREATE TABLE IF NOT EXISTS "place_suggestions" (
  "id"          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "resultId"    uuid NOT NULL REFERENCES "pipeline_results"("id") ON DELETE CASCADE,
  "placeId"     uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "rawName"     text,
  "confidence"  double precision,
  "isSelected"  boolean NOT NULL DEFAULT false,
  "createdAt"   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_place_suggestions_resultId"
  ON "place_suggestions" ("resultId");

CREATE INDEX IF NOT EXISTS "idx_place_suggestions_placeId"
  ON "place_suggestions" ("placeId");

CREATE OR REPLACE VIEW "ideas_with_plan_count" AS
SELECT
  i.*,
  COUNT(p.id)::int AS "planCount"
FROM "ideas" i
LEFT JOIN "plans" p ON p."ideaId" = i.id
GROUP BY i.id;

-- ============================================================
-- Reel Candidate User Places (per-user confirmed place for a candidate)
-- ============================================================

CREATE TABLE IF NOT EXISTS "reel_candidate_user_places" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "candidate_id"  uuid NOT NULL REFERENCES "reel_ingest_candidates"("id") ON DELETE CASCADE,
  "user_id"       uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "place_id"      uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "place_name"    text,
  "place_address" text,
  "latitude"      double precision,
  "longitude"     double precision,
  "maps_query"    text,
  "source"        text NOT NULL DEFAULT 'user' CHECK ("source" IN ('pipeline', 'user')),
  "confirmed_at"  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "uq_rcup_candidate_user" UNIQUE ("candidate_id", "user_id")
);

CREATE INDEX IF NOT EXISTS "idx_rcup_candidate"
  ON "reel_candidate_user_places" ("candidate_id");

CREATE INDEX IF NOT EXISTS "idx_rcup_user"
  ON "reel_candidate_user_places" ("user_id");

-- ============================================================
-- User Feature Flags (per-user flag toggles)
-- ============================================================

CREATE TABLE IF NOT EXISTS "user_feature_flags" (
  "id"          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "user_id"     uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "flag_name"   text NOT NULL,
  "enabled"     boolean NOT NULL DEFAULT true,
  "created_at"  timestamptz NOT NULL DEFAULT now(),
  "updated_at"  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT "uq_uff_user_flag" UNIQUE ("user_id", "flag_name")
);

CREATE INDEX IF NOT EXISTS "idx_uff_user"
  ON "user_feature_flags" ("user_id");

CREATE INDEX IF NOT EXISTS "idx_uff_flag"
  ON "user_feature_flags" ("flag_name");

-- Add notification enum value on existing databases (no-op if already present)
DO $enum_mig$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'notificationType' AND e.enumlabel = 'added_to_collection'
  ) THEN
    ALTER TYPE "notificationType" ADD VALUE 'added_to_collection';
  END IF;
END
$enum_mig$;
