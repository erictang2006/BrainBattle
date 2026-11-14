import { z } from 'zod';

export const VISUAL_MEMORY_ID = 'visual-memory' as const;
export const MEMORY_MATCH_MS = 120_000;
// A turn identifies a particular level attempt. Replayed taps cannot affect its successor.
export const memoryTapInput = z
  .object({
    action: z.literal('memory-tap'),
    level: z.number().int().min(1).max(1_000_000),
    attempt: z.number().int().min(1).max(3),
    tile: z.number().int().min(0).max(63),
  })
  .strict();
export const memoryRetryInput = z
  .object({
    action: z.literal('memory-retry'),
    level: z.number().int().min(1).max(1_000_000),
    attempt: z.number().int().min(1).max(3),
  })
  .strict();
export type MemoryPhase = 'prepare' | 'display' | 'recall' | 'cleared' | 'lifeLost' | 'finished';
export type MemoryPlayerView = {
  playerId: string;
  level: number;
  attempt: number;
  lives: number;
  mistakes: number;
  totalMistakes: number;
  score: number;
  gridSize: number;
  targetCount: number;
  phase: MemoryPhase;
  startsAt: number;
  displayUntil: number;
  nextAt?: number;
  correct: number[];
  wrong: number[];
  highlighted?: number[];
  finishReason?: 'eliminated' | 'time' | 'left';
  lifeLossReason?: 'mistakes' | 'retry';
};
export type MemoryView = {
  startsAt: number;
  endsAt: number | null;
  players: MemoryPlayerView[];
};
export type MemoryHistory = {
  bestLevel: number;
  games: {
    code: string;
    mode: string;
    updatedAt: number;
    completed: boolean;
    level: number;
    score: number;
    lives: number;
    rank: number;
  }[];
};
