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
      'friend_request'
    );
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
  "id"        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"    uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "type"      "notificationType" NOT NULL,
  "planId"    uuid REFERENCES "plans"("id") ON DELETE CASCADE,
  "title"     text NOT NULL,
  "body"      text,
  "isRead"    boolean NOT NULL DEFAULT false,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

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

CREATE TYPE "savedReelStatus" AS ENUM ('processing', 'needs_review', 'promoted', 'failed');

CREATE TABLE IF NOT EXISTS "saved_reels" (
  "id"                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"              uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "jobId"               uuid NOT NULL UNIQUE REFERENCES "reel_ingestion_jobs"("id") ON DELETE CASCADE,
  "thumbnailObjectPath" text,
  "reelUrl"             text NOT NULL,
  "title"               text NOT NULL DEFAULT '',
  "status"              "savedReelStatus" NOT NULL DEFAULT 'processing',
  "createdAt"           timestamptz NOT NULL DEFAULT now(),
  "updatedAt"           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_saved_reels_userId_createdAt"
  ON "saved_reels" ("userId", "createdAt" DESC);

ALTER TABLE "ideas" DROP CONSTRAINT IF EXISTS "ideas_savedReelId_fkey";
ALTER TABLE "ideas" ADD CONSTRAINT "ideas_savedReelId_fkey"
  FOREIGN KEY ("savedReelId") REFERENCES "saved_reels"("id") ON DELETE SET NULL;

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
