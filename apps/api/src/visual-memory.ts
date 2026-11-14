import { randomBytes } from 'node:crypto';
import { MEMORY_MATCH_MS, type MemoryPlayerView, type MemoryView } from '@brain/shared';
import { visualMemoryPattern, visualMemoryRules, visualMemoryScore } from '@brain/games';

export type MemoryState = {
  seed: string;
  startsAt: number;
  endsAt: number | null;
  players: MemoryPlayerView[];
};
function newTurn(player: MemoryPlayerView, startsAt: number) {
  const rules = visualMemoryRules(player.level);
  Object.assign(player, rules, {
    phase: 'prepare',
    startsAt,
    displayUntil: startsAt + rules.displayMs,
    correct: [],
    wrong: [],
    mistakes: 0,
  });
  delete player.nextAt;
  delete player.lifeLossReason;
  player.score = visualMemoryScore(player.level, 0, player.totalMistakes);
}
export function startMemory(ids: string[], now: number, solo: boolean): MemoryState {
  const startsAt = now + (solo ? 1000 : 4000);
  const state: MemoryState = {
    seed: randomBytes(32).toString('hex'),
    startsAt,
    endsAt: solo ? null : startsAt + MEMORY_MATCH_MS,
    players: ids.map((playerId) => ({
      playerId,
      level: 1,
      attempt: 1,
      lives: 3,
      mistakes: 0,
      totalMistakes: 0,
      score: 0,
      gridSize: 3,
      targetCount: 3,
      phase: 'prepare',
      startsAt,
      displayUntil: startsAt + 1500,
      correct: [],
      wrong: [],
    })),
  };
  return state;
}
export function advanceMemory(state: MemoryState, now: number) {
  for (const p of state.players) {
    if (p.phase === 'finished') continue;
    if (state.endsAt !== null && now >= state.endsAt) {
      p.phase = 'finished';
      p.finishReason = 'time';
      delete p.nextAt;
      continue;
    }
    if ((p.phase === 'cleared' || p.phase === 'lifeLost') && now >= p.nextAt!) {
      if (p.phase === 'cleared') {
        p.level++;
        p.attempt = 1;
      } else p.attempt++;
      // Schedule from delivery time, so a delayed scheduler never skips a fresh pattern.
      newTurn(p, now + 250);
    }
    if (p.phase === 'prepare' && now >= p.startsAt) p.phase = 'display';
    if (p.phase === 'display' && now >= p.displayUntil) p.phase = 'recall';
  }
  return state.players.every((p) => p.phase === 'finished');
}
function loseLife(p: MemoryPlayerView, now: number, reason: 'mistakes' | 'retry' = 'mistakes') {
  p.lifeLossReason = reason;
  p.lives--;
  p.mistakes = 0;
  if (p.lives === 0) {
    p.phase = 'finished';
    p.finishReason = 'eliminated';
  } else {
    p.phase = 'lifeLost';
    p.nextAt = now + 1500;
  }
}
export function tapMemory(state: MemoryState, playerId: string, tile: number, now: number) {
  const p = state.players.find((p) => p.playerId === playerId)!;
  if (p.phase !== 'recall') return;
  if (tile >= p.gridSize * p.gridSize || tile < 0) throw new Error('Tile is outside this grid');
  if (p.correct.includes(tile) || p.wrong.includes(tile)) return;
  const pattern = visualMemoryPattern(state.seed, p.level, p.attempt);
  if (pattern.includes(tile)) {
    p.correct.push(tile);
    if (p.correct.length === pattern.length) {
      p.phase = 'cleared';
      p.nextAt = now + 800;
      p.score = p.level * 1000 - p.totalMistakes;
      return;
    }
  } else {
    p.wrong.push(tile);
    p.mistakes++;
    p.totalMistakes++;
    if (p.mistakes === 3) loseLife(p, now);
  }
  p.score = visualMemoryScore(p.level, p.correct.length, p.totalMistakes);
}
export function retryMemory(state: MemoryState, playerId: string, now: number) {
  const p = state.players.find((p) => p.playerId === playerId)!;
  if (p.phase !== 'recall') return;
  // An explicit retry spends a heart without inventing incorrect tile selections.
  loseLife(p, now, 'retry');
  p.score = visualMemoryScore(p.level, p.correct.length, p.totalMistakes);
}
export function memoryView(state: MemoryState): MemoryView {
  return {
    startsAt: state.startsAt,
    endsAt: state.endsAt,
    players: state.players.map((p) => ({
      ...p,
      // Only sent to the owner by LiveService.forPlayer. Never send seeds or future patterns.
      highlighted:
        p.phase === 'prepare' || p.phase === 'display' || p.phase === 'lifeLost'
          ? visualMemoryPattern(state.seed, p.level, p.attempt)
          : undefined,
    })),
  };
}
