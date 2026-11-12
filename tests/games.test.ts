import { describe, expect, it } from 'vitest';
import { countingBoxes, countingBoxesV2, getGame } from '@brain/games';
import { ANSWER_MS } from '@brain/shared';
import { createHash } from 'node:crypto';
describe('Counting Boxes v1', () => {
  it('is deterministic across calls and has a stable versioned fixture', () => {
    const a = countingBoxes.generate('fixture-seed', 1);
    expect(a).toEqual(countingBoxes.generate('fixture-seed', 1));
    // A released rule version must reproduce the entire fixture byte for byte.
    expect(createHash('sha256').update(JSON.stringify(a)).digest('hex')).toBe(
      '45ca55e68e579dbd1d222a292a03f8ff92baa00b840a9620f6feacd60edd6814',
    );
    expect(countingBoxes.generate('different-seed', 1)).not.toEqual(a);
    expect(countingBoxes.generate('fixture-seed', 2)).not.toEqual(a);
    expect(getGame('counting-boxes', 1)).toBe(countingBoxes);
    expect(() => getGame('counting-boxes', 3)).toThrow('Unsupported');
  });
  it('produces unique supported integer cubes and an accurate count across many seeds', () => {
    for (let seed = 0; seed < 100; seed++)
      for (let round = 1; round <= 5; round++) {
        const { puzzle, answer } = countingBoxes.generate(String(seed), round);
        expect(answer).toBe(puzzle.cubes.length);
        expect(answer).toBeGreaterThan(0);
        expect(answer).toBeLessThan(65);
        const positions = new Set(puzzle.cubes.map((c) => `${c.x},${c.y},${c.z}`));
        expect(positions.size).toBe(answer);
        for (const c of puzzle.cubes)
          if (c.y > 0) expect(positions.has(`${c.x},${c.y - 1},${c.z}`)).toBe(true);
        const height = (x: number, z: number) =>
          puzzle.cubes.filter((c) => c.x === x && c.z === z).length;
        const size = round >= 4 ? 4 : 3;
        for (let x = 0; x < size; x++)
          for (let z = 0; z < size; z++) {
            if (x > 0) expect(height(x, z)).toBeGreaterThanOrEqual(height(x - 1, z));
            if (z > 0) expect(height(x, z)).toBeGreaterThanOrEqual(height(x, z - 1));
          }
      }
  });
  it('awards speed only for correct answers within the answer window', () => {
    expect(countingBoxes.score(12, 12, 0)).toBe(1500);
    expect(countingBoxes.score(12, 12, 6000)).toBe(1250);
    expect(countingBoxes.score(12, 12, ANSWER_MS - 1)).toBe(1000);
    expect(countingBoxes.score(12, 12, ANSWER_MS)).toBe(0);
    expect(countingBoxes.score(12, 13, 100)).toBe(0);
    expect(countingBoxes.score(12, null, 100)).toBe(0);
    expect(countingBoxes.score(12, 12, -1)).toBe(0);
  });
});

describe('Counting Boxes v2', () => {
  it('keeps a stable v2 deterministic fixture', () => {
    expect(
      createHash('sha256')
        .update(JSON.stringify(countingBoxesV2.generate('fixture-seed', 5)))
        .digest('hex'),
    ).toBe('61a462f7f43474c7f22edb5d55ebe9c1cdfa392f3edfe53cd22b3f677c69bdc4');
  });
  it('generates varied sparse supported 5x5 arrangements with the correct progression', () => {
    for (let round = 1; round <= 5; round++) {
      const shapes = new Set<string>();
      let stacked = false,
        adjacent = false,
        isolated = false;
      const [min, max] = round <= 2 ? [3, 5] : round <= 4 ? [6, 10] : [11, 16];
      for (let seed = 0; seed < 150; seed++) {
        const generated = countingBoxesV2.generate(String(seed), round);
        expect(generated).toEqual(countingBoxesV2.generate(String(seed), round));
        const { puzzle, answer } = generated;
        shapes.add(JSON.stringify(puzzle));
        expect(puzzle.gridSize).toBe(5);
        expect(answer).toBe(puzzle.cubes.length);
        expect(answer).toBeGreaterThanOrEqual(min);
        expect(answer).toBeLessThanOrEqual(max);
        const occupied = new Set(puzzle.cubes.map((c) => `${c.x},${c.y},${c.z}`));
        expect(occupied.size).toBe(answer);
        for (const c of puzzle.cubes) {
          expect(Number.isInteger(c.x) && Number.isInteger(c.y) && Number.isInteger(c.z)).toBe(
            true,
          );
          expect(c.x >= 0 && c.x < 5 && c.z >= 0 && c.z < 5 && c.y >= 0 && c.y < 3).toBe(true);
          if (c.y > 0) {
            stacked = true;
            expect(occupied.has(`${c.x},${c.y - 1},${c.z}`)).toBe(true);
          }
          const neighbours = puzzle.cubes.some(
            (p) => p.y === 0 && Math.abs(p.x - c.x) + Math.abs(p.z - c.z) === 1,
          );
          if (c.y === 0) {
            adjacent ||= neighbours;
            isolated ||= !neighbours;
          }
        }
      }
      expect(shapes.size).toBeGreaterThan(140);
      expect(stacked && adjacent && isolated).toBe(true);
    }
    expect(getGame('counting-boxes', 2)).toBe(countingBoxesV2);
  });
  it('uses difficulty-specific timing and scores only within each answer window', () => {
    expect(() => countingBoxesV2.score(4, 4, 0)).toThrow('Round required');
    for (let round = 1; round <= 5; round++) {
      const rules = countingBoxesV2.rules(round);
      expect(rules.displayMs).toBe(round <= 2 ? 3000 : round <= 4 ? 2500 : 2000);
      expect(rules.answerMs).toBe(round === 5 ? 5000 : 6000);
      expect(rules.feedbackMs).toBe(1000);
      expect(countingBoxesV2.score(4, 4, 0, round)).toBe(1500);
      expect(countingBoxesV2.score(4, 4, rules.answerMs / 2, round)).toBe(1250);
      expect(countingBoxesV2.score(4, 4, rules.answerMs, round)).toBe(0);
      expect(countingBoxesV2.score(4, 3, 100, round)).toBe(0);
      expect(countingBoxesV2.score(4, 4, -1, round)).toBe(0);
    }
  });
});
