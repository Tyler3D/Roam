CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- Enums
-- ============================================================

DO $$
BEGIN
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
  "tags"          jsonb DEFAULT '[]',
  "isActive"      boolean NOT NULL DEFAULT false,
  "isOnboarded"   boolean NOT NULL DEFAULT false,
  "isExternal"    boolean NOT NULL DEFAULT false,
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
-- Enrichments (AI-derived metadata for ideas and plans)
-- ============================================================

CREATE TABLE IF NOT EXISTS "enrichments" (
  "id"               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "refinedTitle"     text,
  "category"         text,
  "searchQuery"      text,
  "tags"             text[] DEFAULT '{}',
  "estimatedMinutes" integer,
  "preference"       text,
  "aiEnriched"       boolean NOT NULL DEFAULT false,
  "modelName"        text,
  "rawOutput"        jsonb DEFAULT '{}',
  "confidence"       jsonb DEFAULT '{}',
  "createdAt"        timestamptz NOT NULL DEFAULT now()
);

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
  "id"           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"       uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "title"        text NOT NULL,
  "notes"        text DEFAULT '',
  "savedLink"    text DEFAULT '',
  "placeId"      uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "enrichmentId" uuid REFERENCES "enrichments"("id") ON DELETE SET NULL,
  "createdAt"    timestamptz NOT NULL DEFAULT now(),
  "updatedAt"    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_ideas_userId"
  ON "ideas" ("userId", "createdAt" DESC);

-- ============================================================
-- Plans
-- ============================================================

CREATE TABLE IF NOT EXISTS "plans" (
  "id"               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "creatorId"        uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "placeId"          uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "ideaId"           uuid REFERENCES "ideas"("id") ON DELETE SET NULL,
  "enrichmentId"     uuid REFERENCES "enrichments"("id") ON DELETE SET NULL,
  "title"            text NOT NULL,
  "scheduledAt"      timestamptz,
  "status"           "planStatus" NOT NULL DEFAULT 'draft',
  "shareCode"        text NOT NULL UNIQUE,
  "rawPrompt"        text,
  "estimatedMinutes" integer DEFAULT 60,
  "calendarEventId"  text,
  "covers"           integer DEFAULT 2,
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
  "task"        text,
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
-- Ingestion Jobs (reel -> place discovery pipeline)
-- ============================================================

CREATE TABLE IF NOT EXISTS "ingestion_jobs" (
  "id"            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"        uuid NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
  "reelUrl"       text NOT NULL,
  "shareText"     text,
  "lpTitle"       text,
  "ogDescription" text,
  "ogKeywords"    text,
  "status"        "jobStatus" NOT NULL DEFAULT 'processing',
  "error"         text,
  "createdAt"     timestamptz NOT NULL DEFAULT now(),
  "updatedAt"     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS "unique_user_reel"
  ON "ingestion_jobs" ("userId", "reelUrl");

-- ============================================================
-- Extractions (LLM-generated place suggestions per job)
-- ============================================================

CREATE TABLE IF NOT EXISTS "extractions" (
  "id"           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "jobId"        uuid NOT NULL REFERENCES "ingestion_jobs"("id") ON DELETE CASCADE,
  "placeId"      uuid REFERENCES "places"("id") ON DELETE SET NULL,
  "confidence"   double precision,
  "rawLlmOutput" jsonb,
  "createdAt"    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "idx_extractions_jobId"
  ON "extractions" ("jobId");

CREATE INDEX IF NOT EXISTS "idx_extractions_placeId"
  ON "extractions" ("placeId");
