import { ANSWER_MS, DISPLAY_MS, GAME_ID, type Puzzle, type RoundRules } from '@brain/shared';

/** Pure rules only. Seed creation and clocks belong to the authoritative server. */
export interface MiniGame<PublicPuzzle, Answer> {
  id: string;
  version: number;
  generate(seed: string, round: number): { puzzle: PublicPuzzle; answer: Answer };
  score(expected: Answer, submitted: Answer | null, elapsedMs: number, round?: number): number;
  rules(round: number): RoundRules;
}
function random(seed: string) {
  let value = 2166136261;
  for (const char of seed) value = Math.imul(value ^ char.charCodeAt(0), 16777619);
  return () => {
    value += 0x6d2b79f5;
    let n = Math.imul(value ^ (value >>> 15), 1 | value);
    n ^= n + Math.imul(n ^ (n >>> 7), 61 | n);
    return ((n ^ (n >>> 14)) >>> 0) / 4294967296;
  };
}
export const countingBoxes: MiniGame<Puzzle, number> = {
  id: GAME_ID,
  version: 1,
  rules: () => ({
    difficulty: 'classic',
    displayMs: DISPLAY_MS,
    answerMs: ANSWER_MS,
    feedbackMs: 0,
  }),
  generate(seed, round) {
    const rng = random(`${GAME_ID}:v1:${seed}:${round}`);
    const cubes: Puzzle['cubes'] = [];
    // A rising heightfield keeps every column top visible from the fixed front
    // camera. Hidden cubes can be inferred from support, rather than guessed.
    const size = round >= 4 ? 4 : 3;
    const heights: number[][] = Array.from({ length: size }, () => []);
    for (let x = 0; x < size; x++)
      for (let z = 0; z < size; z++) {
        const front = Math.max(x > 0 ? heights[x - 1][z] : 1, z > 0 ? heights[x][z - 1] : 1);
        const maxHeight = Math.min(4, 1 + Math.floor((x + z) / 2) + (round >= 3 ? 1 : 0));
        const height = Math.min(maxHeight, front + (rng() > 0.48 ? 1 : 0));
        heights[x][z] = height;
        for (let y = 0; y < height; y++) cubes.push({ x, y, z });
      }
    return { puzzle: { cubes }, answer: cubes.length };
  },
  score(expected, submitted, elapsedMs) {
    if (submitted !== expected || elapsedMs >= ANSWER_MS || elapsedMs < 0) return 0;
    return 1000 + Math.round(500 * (1 - elapsedMs / ANSWER_MS));
  },
};
// Published v2 balancing targets. Future changes require a new rules version.
export function countingBoxesV2Rules(round: number): RoundRules {
  if (!Number.isInteger(round) || round < 1 || round > 5) throw new Error('Invalid round');
  return round <= 2
    ? { difficulty: 'easy', displayMs: 3000, answerMs: 6000, feedbackMs: 1000, gridSize: 5 }
    : round <= 4
      ? { difficulty: 'medium', displayMs: 2500, answerMs: 6000, feedbackMs: 1000, gridSize: 5 }
      : { difficulty: 'hard', displayMs: 2000, answerMs: 5000, feedbackMs: 1000, gridSize: 5 };
}
export const countingBoxesV2: MiniGame<Puzzle, number> = {
  id: GAME_ID,
  version: 2,
  rules: countingBoxesV2Rules,
  generate(seed, round) {
    const rules = countingBoxesV2Rules(round);
    const rng = random(`${GAME_ID}:v2:${seed}:${round}`);
    const [minimum, maximum, maxHeight, stackChance] =
      rules.difficulty === 'easy'
        ? [3, 5, 2, 0.12]
        : rules.difficulty === 'medium'
          ? [6, 10, 3, 0.35]
          : [11, 16, 3, 0.45];
    const total = minimum + Math.floor(rng() * (maximum - minimum + 1));
    type Column = { x: number; z: number; height: number };
    let columns: Column[] = [];
    const visibleTops = (values: Column[]) =>
      values.every((back) =>
        values.every((front) => {
          const distance = back.x - front.x;
          return (
            distance <= 0 ||
            back.x - back.z !== front.x - front.z ||
            back.height + distance * 0.857 > front.height + 0.15
          );
        }),
      );
    for (let placed = 0; placed < total; placed++) {
      const ground: Column[] = [],
        stacks: Column[] = [];
      for (let x = 0; x < 5; x++)
        for (let z = 0; z < 5; z++) {
          const existing = columns.find((c) => c.x === x && c.z === z);
          if ((existing?.height ?? 0) >= maxHeight) continue;
          const candidate = { x, z, height: (existing?.height ?? 0) + 1 };
          const next = [...columns.filter((c) => c !== existing), candidate];
          if (visibleTops(next)) (existing ? stacks : ground).push(candidate);
        }
      const adjacent = ground.filter((c) =>
        columns.some((p) => Math.abs(c.x - p.x) + Math.abs(c.z - p.z) === 1),
      );
      const isolated = ground.filter(
        (c) => !columns.some((p) => Math.abs(c.x - p.x) + Math.abs(c.z - p.z) <= 1),
      );
      let choices = ground;
      if (stacks.length && rng() < stackChance) choices = stacks;
      else if (rules.difficulty === 'easy' && isolated.length && rng() < 0.7) choices = isolated;
      else if (adjacent.length && rng() < 0.55) choices = adjacent;
      if (!choices.length) choices = [...ground, ...stacks];
      if (!choices.length) throw new Error('Cannot place supported cube');
      const selected = choices[Math.floor(rng() * choices.length)];
      columns = [...columns.filter((c) => c.x !== selected.x || c.z !== selected.z), selected];
    }
    const cubes: Puzzle['cubes'] = [];
    for (const c of columns.sort((a, b) => a.x - b.x || a.z - b.z))
      for (let y = 0; y < c.height; y++) cubes.push({ x: c.x, y, z: c.z });
    return { puzzle: { cubes, gridSize: 5 }, answer: cubes.length };
  },
  score(expected, submitted, elapsedMs, round) {
    if (round === undefined) throw new Error('Round required for v2 scoring');
    const { answerMs } = countingBoxesV2Rules(round);
    if (submitted !== expected || elapsedMs < 0 || elapsedMs >= answerMs) return 0;
    return 1000 + Math.round(500 * (1 - elapsedMs / answerMs));
  },
};
const registry = new Map<string, MiniGame<Puzzle, number>>([
  [`${GAME_ID}@1`, countingBoxes],
  [`${GAME_ID}@2`, countingBoxesV2],
]);
export function getGame(id: string, version: number) {
  const game = registry.get(`${id}@${version}`);
  if (!game) throw new Error(`Unsupported game rules: ${id}@${version}`);
  return game;
}
