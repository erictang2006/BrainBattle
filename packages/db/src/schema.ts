import {
  pgTable,
  jsonb,
  uuid,
  text,
  integer,
  bigint,
  boolean,
  primaryKey,
  uniqueIndex,
} from 'drizzle-orm/pg-core';
export const profiles = pgTable('profiles', {
  id: uuid('id').primaryKey(),
  name: text('name').notNull(),
  createdAt: bigint('created_at', { mode: 'number' }).notNull(),
});
export const matches = pgTable('matches', {
  id: uuid('id').primaryKey(),
  hostId: uuid('host_id')
    .notNull()
    .references(() => profiles.id),
  guestId: uuid('guest_id').references(() => profiles.id),
  mode: text('mode').notNull(),
  gameId: text('game_id').notNull(),
  rulesVersion: integer('rules_version').notNull(),
  inviteToken: text('invite_token').unique(),
  expiresAt: bigint('expires_at', { mode: 'number' }).notNull(),
  createdAt: bigint('created_at', { mode: 'number' }).notNull(),
});
export const rounds = pgTable(
  'rounds',
  {
    matchId: uuid('match_id')
      .notNull()
      .references(() => matches.id),
    number: integer('number').notNull(),
    seed: text('seed').notNull(),
  },
  (t) => [primaryKey({ columns: [t.matchId, t.number] })],
);
export const attempts = pgTable(
  'attempts',
  {
    matchId: uuid('match_id')
      .notNull()
      .references(() => matches.id),
    round: integer('round').notNull(),
    playerId: uuid('player_id')
      .notNull()
      .references(() => profiles.id),
    startedAt: bigint('started_at', { mode: 'number' }).notNull(),
    displayUntil: bigint('display_until', { mode: 'number' }).notNull(),
    deadline: bigint('deadline', { mode: 'number' }),
    submittedAt: bigint('submitted_at', { mode: 'number' }),
    submissionId: uuid('submission_id'),
    answer: integer('answer'),
    score: integer('score'),
    correct: boolean('correct'),
    timedOut: boolean('timed_out'),
  },
  (t) => [
    primaryKey({ columns: [t.matchId, t.round, t.playerId] }),
    uniqueIndex('attempt_submission_id').on(t.playerId, t.submissionId),
  ],
);

// Versioned private aggregates are locked transactionally by LiveService.
export const liveRooms = pgTable('live_rooms', {
  id: uuid('id').primaryKey(),
  code: text('code').notNull().unique(),
  state: jsonb('state').notNull(),
  updatedAt: bigint('updated_at', { mode: 'number' }).notNull(),
});
