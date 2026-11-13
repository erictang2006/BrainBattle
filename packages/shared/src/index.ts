import { z } from 'zod';
export const GAME_ID = 'counting-boxes' as const;
export const RULES_VERSION = 3 as const;
export const DEFAULT_ROUNDS = 5;
// Released v1 timing. New versions resolve timing from their registered rules.
export const DISPLAY_MS = 8000;
export const ANSWER_MS = 12000;
export const profileInput = z
  .object({
    name: z
      .string()
      .trim()
      .min(2)
      .max(24)
      .regex(/^[\p{L}\p{N} _-]+$/u, 'Use letters, numbers, spaces, _ or -'),
  })
  .strict();
export const createMatchInput = z
  .object({
    mode: z.enum(['challenge', 'solo']).default('challenge'),
    rulesVersion: z.union([z.literal(1), z.literal(2), z.literal(3)]).default(RULES_VERSION),
  })
  .strict();
export const attemptInput = z
  .object({ answer: z.number().int().min(0).max(100).nullable(), submissionId: z.uuid() })
  .strict();
export const matchIdInput = z.uuid();
export const inviteInput = z.string().regex(/^[a-f0-9]{48}$/);
export const roundInput = z.coerce.number().int().min(1).max(DEFAULT_ROUNDS);
export type Cube = { x: number; y: number; z: number };
export type Puzzle = { cubes: Cube[]; gridSize?: number };
export type RoundRules = {
  difficulty: 'classic' | 'easy' | 'medium' | 'hard';
  displayMs: number;
  answerMs: number;
  answerTimeLimit?: boolean;
  feedbackMs: number;
  gridSize?: number;
};
export type Profile = { id: string; name: string };
export type AttemptView = { score: number; correct: boolean; timedOut: boolean };
export type AnswerReveal = {
  puzzle: Puzzle;
  correctAnswer: number;
  submittedAnswer: number | null;
};
export type RoundView = {
  number: number;
  state: 'locked' | 'ready' | 'display' | 'answer' | 'done';
  displayUntil?: number;
  deadline?: number;
  puzzle?: Puzzle;
  attempt?: AttemptView;
  opponent?: AttemptView;
  finalized: boolean;
  rules?: RoundRules;
  feedbackUntil?: number;
  reveal?: AnswerReveal;
};
export type MatchView = {
  id: string;
  mode: 'solo' | 'challenge';
  gameId: typeof GAME_ID;
  rulesVersion: number;
  you: Profile;
  opponent: Profile | null;
  rounds: RoundView[];
  inviteUrl?: string;
  expiresAt: number;
  complete: boolean;
  yoursComplete: boolean;
  total: number;
  opponentTotal?: number;
  winner?: string | 'draw';
  serverNow: number;
};
export type InvitationView = {
  hostName: string;
  claimed: boolean;
  expired: boolean;
  rounds: number;
};
export type MatchSummary = { id: string; mode: string; opponent: string | null; createdAt: number };
import type { LiveAck, LiveCommand, LiveSnapshot } from './live.js';
export interface ClientToServerEvents {
  'room:watch': (payload: { code: string }, ack: (result: LiveAck) => void) => void;
  'room:command': (
    payload: { code: string; command: LiveCommand },
    ack: (result: LiveAck) => void,
  ) => void;
  'clock:sync': (payload: Record<string, never>, ack: (result: LiveAck) => void) => void;
  'match:watch': (payload: { matchId: string }, ack: (result: { ok: boolean }) => void) => void;
}
export interface ServerToClientEvents {
  'room:state': (payload: LiveSnapshot) => void;
  'match:changed': (payload: { matchId: string }) => void;
}
export type * from './live.js';
