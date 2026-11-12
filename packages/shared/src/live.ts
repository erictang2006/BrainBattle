import { z } from 'zod';
import type { Puzzle, RoundRules } from './index.js';
export const liveCode = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-HJ-NP-Z2-9]{6}$/);
export const createLiveInput = z
  .object({
    mode: z.enum(['duel', 'party']).default('duel'),
    capacity: z.number().int().min(2).max(8).optional(),
    roundCount: z.union([z.literal(1), z.literal(5)]).default(5),
    format: z.literal('counting-boxes').default('counting-boxes'),
  })
  .strict()
  .superRefine((input, ctx) => {
    const capacity = input.capacity ?? (input.mode === 'party' ? 8 : 2);
    if ((input.mode === 'duel' && capacity !== 2) || (input.mode === 'party' && capacity < 3))
      ctx.addIssue({ code: 'custom', message: '1v1 requires 2 players; parties require 3–8.' });
  });
export const liveCommand = z.discriminatedUnion('action', [
  z.object({ action: z.literal('ready'), ready: z.boolean() }).strict(),
  z.object({ action: z.literal('start') }).strict(),
  z.object({ action: z.literal('leave') }).strict(),
  z.object({ action: z.literal('rematch') }).strict(),
  z
    .object({
      action: z.literal('submit'),
      round: z.number().int().min(1).max(5),
      answer: z.number().int().min(0).max(100).nullable(),
      submissionId: z.uuid(),
    })
    .strict(),
]);
export type LiveCommand = z.infer<typeof liveCommand>;
export type LiveResult = {
  playerId: string;
  score: number;
  correct: boolean;
  timedOut: boolean;
  forfeited: boolean;
  placement?: number;
  points?: number;
};
export type LiveSnapshot = {
  id: string;
  code: string;
  revision: number;
  rulesVersion: number;
  status: 'lobby' | 'running' | 'completed' | 'closed';
  hostId: string;
  mode: 'duel' | 'party';
  capacity: number;
  roundCount: number;
  expiresAt: number;
  serverNow: number;
  players: { id: string; name: string; ready: boolean; connected: boolean; forfeited: boolean }[];
  rematchCode?: string;
  nextAt?: number;
  lineup: { number: number; gameId: string; rules: RoundRules }[];
  standings: {
    playerId: string;
    points: number;
    roundWins: number;
    totalScore: number;
    rank: number;
  }[];
  round?: {
    number: number;
    startsAt: number;
    displayUntil: number;
    deadline: number;
    rules: RoundRules;
    puzzle?: Puzzle;
    submitted: string[];
    results?: LiveResult[];
    winners?: string[];
  };
};
export type LiveAck =
  | { ok: true; state?: LiveSnapshot; serverNow?: number }
  | { ok: false; error: string; status?: number };
