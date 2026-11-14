import { afterEach, beforeEach, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { openDatabase } from '@brain/db';
import { getGame } from '@brain/games';
import { createApp } from '../apps/api/src/app.js';
import { GameService } from '../apps/api/src/service.js';
import { LiveService } from '../apps/api/src/live-service.js';
let database: Awaited<ReturnType<typeof openDatabase>>;
let now: number;
beforeEach(async () => {
  database = await openDatabase();
  now = 1_800_000_000_000;
});
afterEach(async () => {
  await database.close();
});
it('versions the 3/4/3 difficulty progression without changing five-round rules', () => {
  const game = getGame('counting-boxes', 4);
  expect(Array.from({ length: 10 }, (_, i) => game.rules(i + 1).difficulty)).toEqual([
    'easy',
    'easy',
    'easy',
    'medium',
    'medium',
    'medium',
    'medium',
    'hard',
    'hard',
    'hard',
  ]);
  for (let round = 1; round <= 10; round++) {
    const generated = game.generate('fixed-seed', round);
    expect(generated).toEqual(game.generate('fixed-seed', round));
    expect(generated.answer).toBe(generated.puzzle.cubes.length);
    expect(game.rules(round).answerTimeLimit).toBe(false);
    expect(game.score(generated.answer, generated.answer, 100_000, round)).toBe(1000);
  }
  expect(getGame('counting-boxes', 3).rules(3).difficulty).toBe('medium');
  expect(() => getGame('counting-boxes', 3).rules(6)).toThrow();
  expect(() => game.rules(11)).toThrow();
});
it('creates, redeems, scores and rematches a ten-round native challenge through HTTP', async () => {
  const { app } = await createApp({
    db: database.db,
    secret: 'ten-round-regression-secret-at-least-32-chars',
    origin: 'http://localhost:3000',
    now: () => now,
  });
  try {
    const a = (await app.inject({ method: 'POST', url: '/api/native/session' })).headers[
      'x-brain-session'
    ] as string;
    const b = (await app.inject({ method: 'POST', url: '/api/native/session' })).headers[
      'x-brain-session'
    ] as string;
    const request = (token: string, url: string, payload?: Record<string, unknown>) =>
      app.inject({
        method: payload ? 'POST' : 'GET',
        url: `/api/${url}`,
        headers: { authorization: `Bearer ${token}` },
        ...(payload ? { payload } : {}),
      });
    const created = (await request(a, 'matches', { mode: 'challenge', roundCount: 10 })).json();
    expect(created.rulesVersion).toBe(4);
    expect(created.rounds).toHaveLength(10);
    const invitation = created.inviteUrl.split('/').at(-1);
    expect((await request(b, `invitations/${invitation}`)).json().rounds).toBe(10);
    await request(b, `invitations/${invitation}/claim`, {});
    for (const token of [a, b]) {
      for (let round = 1; round <= 10; round++) {
        const started = (
          await request(token, `matches/${created.id}/rounds/${round}/start`, {})
        ).json();
        expect(started.rounds[round - 1].reveal).toBeUndefined();
        const answer = started.rounds[round - 1].puzzle.cubes.length;
        now = started.rounds[round - 1].displayUntil + 100;
        const submitted = await request(token, `matches/${created.id}/rounds/${round}/attempt`, {
          answer,
          submissionId: randomUUID(),
        });
        expect(submitted.statusCode).toBe(200);
        const state = submitted.json();
        expect(state.rounds[round - 1].reveal.correctAnswer).toBe(answer);
        expect(state.yoursComplete).toBe(round === 10);
        now += 1001;
      }
    }
    expect((await request(a, `matches/${created.id}`)).json().complete).toBe(true);
    const rematch = (await request(a, `matches/${created.id}/rematch`, {})).json();
    expect(rematch.rounds).toHaveLength(10);
    const classic = (await request(a, 'matches', { mode: 'solo' })).json();
    expect(classic.rulesVersion).toBe(3);
    expect(classic.rounds).toHaveLength(5);
    expect((await request(a, `matches/${classic.id}/rounds/6/start`, {})).statusCode).toBe(404);
    expect((await request(a, 'matches', { roundCount: 7 })).statusCode).toBe(400);
  } finally {
    await app.close();
  }
});
for (const mode of ['duel', 'party'] as const)
  it(`finishes ten ${mode} rounds and preserves rematch length`, async () => {
    const profiles = new GameService(database.db, 'http://localhost:3000', () => now);
    const ids = Array.from({ length: mode === 'party' ? 3 : 2 }, () => randomUUID());
    for (const id of ids) await profiles.profile(id);
    const live = new LiveService(database.db, () => now);
    const room = await live.create(ids[0], { roundCount: 10, mode, capacity: ids.length });
    for (const id of ids) {
      if (id !== ids[0]) await live.join(room.code, id);
      await live.watch(room.code, id, id);
      await live.command(room.code, id, { action: 'ready', ready: true });
    }
    let state = await live.command(room.code, ids[0], { action: 'start' });
    expect(state.rulesVersion).toBe(4);
    expect(state.lineup).toHaveLength(10);
    for (let round = 1; round <= 10; round++) {
      const answer = state.round!.puzzle!.cubes.length;
      now = state.round!.displayUntil + 100;
      for (const id of ids)
        state = await live.command(room.code, id, {
          action: 'submit',
          round,
          answer,
          submissionId: randomUUID(),
        });
      expect(state.round!.reveal?.correctAnswer).toBe(answer);
      expect(state.status).toBe(round === 10 ? 'completed' : 'running');
      if (round < 10) {
        now = state.nextAt!;
        state = await live.view(room.code, ids[0]);
      }
    }
    const rematch = await live.command(room.code, ids[0], { action: 'rematch' });
    expect((await live.view(rematch.rematchCode!, ids[0])).roundCount).toBe(10);
  });
