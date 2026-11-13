import { afterEach, beforeEach, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { openDatabase } from '@brain/db';
import { GameService } from '../apps/api/src/service.js';
import { LiveService } from '../apps/api/src/live-service.js';
let database: Awaited<ReturnType<typeof openDatabase>>;
let now: number;
let game: GameService;
let players: string[];
beforeEach(async () => {
  database = await openDatabase();
  now = 1_800_000_000_000;
  game = new GameService(database.db, 'http://localhost:3000', () => now);
  players = [randomUUID(), randomUUID(), randomUUID()];
  for (const id of players) await game.profile(id);
});
afterEach(async () => {
  await database.close();
});
it('accepts untimed async answers hours later, keeps single attempts and finalizes five rounds', async () => {
  const match = await game.create(players[0], 'challenge');
  expect(match.rulesVersion).toBe(3);
  await game.claim(match.inviteUrl!.split('/').at(-1)!, players[1]);
  for (let number = 1; number <= 5; number++) {
    const views = await Promise.all(
      players.slice(0, 2).map((id) => game.start(match.id, id, number)),
    );
    const round = views[0].rounds[number - 1];
    expect(round.rules!.answerTimeLimit).toBe(false);
    expect(round.deadline).toBeUndefined();
    expect(views[1].rounds[number - 1].puzzle).toEqual(round.puzzle);
    const answer = round.puzzle!.cubes.length;
    now = round.displayUntil! + 60 * 60 * 1000;
    const refreshed = await game.view(match.id, players[0]);
    expect(refreshed.rounds[number - 1].state).toBe('answer');
    expect(refreshed.rounds[number - 1].attempt).toBeUndefined();
    for (const id of players.slice(0, 2)) {
      const result = await game.submit(match.id, id, number, answer, randomUUID());
      expect(result.rounds[number - 1].attempt).toEqual({
        score: 1000,
        correct: true,
        timedOut: false,
      });
      const duplicate = await game.submit(match.id, id, number, 0, randomUUID());
      expect(duplicate.rounds[number - 1].attempt).toEqual(result.rounds[number - 1].attempt);
    }
    now += 1000;
  }
  const final = await game.view(match.id, players[0]);
  expect(final.complete).toBe(true);
  expect(final.total).toBe(5000);
  expect(final.opponentTotal).toBe(5000);
  expect(final.winner).toBe('draw');
});
it('waits for all live answers after long disconnects and preserves timed v2 deadlines', async () => {
  const live = new LiveService(database.db, () => now);
  for (const mode of ['duel', 'party'] as const) {
    const roster = players.slice(0, mode === 'duel' ? 2 : 3);
    const room = await live.create(roster[0], { mode, capacity: roster.length, roundCount: 1 });
    for (const id of roster) {
      if (id !== roster[0]) await live.join(room.code, id);
      await live.watch(room.code, id, id);
      await live.command(room.code, id, { action: 'ready', ready: true });
    }
    const start = await live.command(room.code, roster[0], { action: 'start' });
    expect(start.rulesVersion).toBe(3);
    expect(start.round!.deadline).toBeNull();
    const answer = start.round!.puzzle!.cubes.length;
    await live.disconnect(roster[0]);
    now = start.round!.displayUntil + 30 * 60 * 1000;
    await live.tick();
    const resumed = await live.watch(room.code, roster[0], 'reconnected');
    expect(resumed.round!.deadline).toBeNull();
    expect(resumed.round!.results).toBeUndefined();
    for (const id of roster)
      await live.command(room.code, id, {
        action: 'submit',
        round: 1,
        answer,
        submissionId: randomUUID(),
      });
    const final = await live.view(room.code, roster[0]);
    expect(final.status).toBe('completed');
    expect(final.round!.results!.every((r) => r.correct && r.score === 1000 && !r.timedOut)).toBe(
      true,
    );
  }
  const legacy = await game.create(players[0], 'solo', 2);
  const started = await game.start(legacy.id, players[0], 1);
  const deadline = started.rounds[0].deadline!;
  expect(deadline).toBeTypeOf('number');
  now = deadline;
  expect((await game.view(legacy.id, players[0])).rounds[0].attempt!.timedOut).toBe(true);
});
