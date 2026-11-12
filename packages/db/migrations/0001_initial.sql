CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY, name text NOT NULL CHECK (char_length(name) BETWEEN 2 AND 24), created_at bigint NOT NULL
);
CREATE TABLE IF NOT EXISTS matches (
  id uuid PRIMARY KEY, host_id uuid NOT NULL REFERENCES profiles(id), guest_id uuid REFERENCES profiles(id),
  mode text NOT NULL CHECK (mode IN ('solo','challenge')), game_id text NOT NULL, rules_version integer NOT NULL,
  invite_token text UNIQUE, expires_at bigint NOT NULL, created_at bigint NOT NULL,
  CHECK (host_id IS DISTINCT FROM guest_id)
);
CREATE TABLE IF NOT EXISTS rounds (
  match_id uuid NOT NULL REFERENCES matches(id), number integer NOT NULL CHECK(number BETWEEN 1 AND 5), seed text NOT NULL,
  PRIMARY KEY(match_id, number)
);
CREATE TABLE IF NOT EXISTS attempts (
  match_id uuid NOT NULL, round integer NOT NULL, player_id uuid NOT NULL REFERENCES profiles(id),
  started_at bigint NOT NULL, display_until bigint NOT NULL, deadline bigint NOT NULL,
  submitted_at bigint, submission_id uuid, answer integer, score integer, correct boolean, timed_out boolean,
  PRIMARY KEY(match_id, round, player_id), FOREIGN KEY(match_id, round) REFERENCES rounds(match_id, number),
  CHECK (started_at <= display_until AND display_until < deadline),
  CHECK (score IS NULL OR score BETWEEN 0 AND 1500)
);
CREATE UNIQUE INDEX IF NOT EXISTS attempt_submission_id ON attempts(player_id, submission_id);
CREATE INDEX IF NOT EXISTS matches_host ON matches(host_id);
CREATE INDEX IF NOT EXISTS matches_guest ON matches(guest_id);
-- Server-only tables: browser clients must use the Fastify API, never direct Supabase table access.
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE attempts ENABLE ROW LEVEL SECURITY;
