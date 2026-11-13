-- A NULL answer deadline represents an untimed v3 attempt.
-- Existing v1/v2 deadlines and all attempt data remain unchanged.
ALTER TABLE attempts ALTER COLUMN deadline DROP NOT NULL;
