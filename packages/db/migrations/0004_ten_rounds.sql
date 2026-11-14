-- Additive: retain all existing rounds and widen only the permitted round range.
ALTER TABLE rounds DROP CONSTRAINT IF EXISTS rounds_number_check;
ALTER TABLE rounds ADD CONSTRAINT rounds_number_check CHECK (number BETWEEN 1 AND 10);
