-- Additive live aggregate. Private state is accessible only through the API.
CREATE TABLE live_rooms (
  id uuid PRIMARY KEY,
  code text NOT NULL UNIQUE,
  state jsonb NOT NULL,
  updated_at bigint NOT NULL
);
ALTER TABLE live_rooms ENABLE ROW LEVEL SECURITY;
