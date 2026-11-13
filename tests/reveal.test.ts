import { afterEach, beforeEach, expect, it } from 'vitest';
import { openDatabase } from '@brain/db';
import { createApp } from '../apps/api/src/app.js';
import type { MatchView } from '@brain/shared';
let db: Awaited<ReturnType<typeof openDatabase>>;
let server: Awaited<ReturnType<typeof createApp>>;
let now: number;
let tokens: string[];
beforeEach(async () => {
  db = await openDatabase();
  now = 1_800_000_000_000;
  server = await createApp({
    db: db.db,
    secret: 'reveal-regression-secret-with-at-least-32-characters',
    origin: 'http://localhost:3000',
    now: () => now,
  });
  tokens = [];
  for (let i = 0; i < 3; i++)
    tokens.push(
      String(
        (await server.app.inject({ method: 'POST', url: '/api/native/session' })).headers[
          'x-brain-session'
        ],
      ),
    );
});
afterEach(async () => {
  await server.app.close();
  await db.close();
});
async function request(
  player: number,
  path: string,
  method: 'POST' | 'GET' = 'GET',
  payload?: Record<string, unknown>,
) {
  return server.app.inject({
    method,
    url: `/api/${path}`,
    headers: { authorization: `Bearer ${tokens[player]}` },
    ...(payload === undefined ? {} : { payload }),
  });
}
it('reveals only an authorized finalized player attempt, preserving hidden opponent results', async () => {
  const created = (await request(0, 'matches', 'POST', { mode: 'challenge' })).json<MatchView>();
  const token = created.inviteUrl!.split('/').at(-1)!;
  await request(1, `invitations/${token}/claim`, 'POST');
  const started = (
    await request(0, `matches/${created.id}/rounds/1/start`, 'POST')
  ).json<MatchView>();
  const cubes = started.rounds[0].puzzle!.cubes;
  expect(started.rounds[0].reveal).toBeUndefined();
  expect(JSON.stringify(started)).not.toMatch(/correctAnswer|seed/);
  await request(1, `matches/${created.id}/rounds/1/start`, 'POST');
  now = started.rounds[0].displayUntil! + 100;
  expect(
    (await request(0, `matches/${created.id}`)).json<MatchView>().rounds[0].reveal,
  ).toBeUndefined();
  const first = (
    await request(0, `matches/${created.id}/rounds/1/attempt`, 'POST', {
      answer: cubes.length,
      submissionId: crypto.randomUUID(),
    })
  ).json<MatchView>();
  expect(first.rounds[0].reveal).toEqual({
    puzzle: { cubes, gridSize: 5 },
    correctAnswer: cubes.length,
    submittedAnswer: cubes.length,
  });
  expect(first.rounds[0].opponent).toBeUndefined();
  const guest = (await request(1, `matches/${created.id}`)).json<MatchView>();
  expect(guest.rounds[0].reveal).toBeUndefined();
  expect(JSON.stringify(guest)).not.toContain('correctAnswer');
  expect((await request(2, `matches/${created.id}`)).statusCode).toBe(404);
  expect((await request(2, `invitations/${token}`)).body).not.toContain('correctAnswer');
  const repeated = (
    await request(0, `matches/${created.id}/rounds/1/attempt`, 'POST', {
      answer: 0,
      submissionId: crypto.randomUUID(),
    })
  ).json<MatchView>();
  expect(repeated.rounds[0].reveal).toEqual(first.rounds[0].reveal);
  expect(repeated.rounds[0].attempt).toEqual(first.rounds[0].attempt);
  expect(JSON.stringify(repeated)).not.toContain('"seed"');
});
it('provides a deterministic reveal after a legacy timeout without accepting a late answer', async () => {
  const created = (
    await request(0, 'matches', 'POST', { mode: 'solo', rulesVersion: 2 })
  ).json<MatchView>();
  const start = (
    await request(0, `matches/${created.id}/rounds/1/start`, 'POST')
  ).json<MatchView>();
  const puzzle = start.rounds[0].puzzle!;
  now = start.rounds[0].deadline! - 1;
  expect(
    (await request(0, `matches/${created.id}`)).json<MatchView>().rounds[0].reveal,
  ).toBeUndefined();
  now += 1;
  const end = (await request(0, `matches/${created.id}`)).json<MatchView>();
  expect(end.rounds[0].attempt).toEqual({ score: 0, correct: false, timedOut: true });
  expect(end.rounds[0].reveal).toEqual({
    puzzle,
    correctAnswer: puzzle.cubes.length,
    submittedAnswer: null,
  });
  const late = (
    await request(0, `matches/${created.id}/rounds/1/attempt`, 'POST', {
      answer: puzzle.cubes.length,
      submissionId: crypto.randomUUID(),
    })
  ).json<MatchView>();
  expect(late.rounds[0]).toEqual(end.rounds[0]);
});
it('keeps reveal authorization and server feedback gates through all five rounds', async () => {
  const created = (await request(0, 'matches', 'POST', { mode: 'solo' })).json<MatchView>();
  for (let number = 1; number <= 5; number++) {
    const start = (
      await request(0, `matches/${created.id}/rounds/${number}/start`, 'POST')
    ).json<MatchView>();
    expect(start.rounds[number - 1].reveal).toBeUndefined();
    const puzzle = start.rounds[number - 1].puzzle!;
    now = start.rounds[number - 1].displayUntil! + 10;
    const done = (
      await request(0, `matches/${created.id}/rounds/${number}/attempt`, 'POST', {
        answer: puzzle.cubes.length,
        submissionId: crypto.randomUUID(),
      })
    ).json<MatchView>();
    expect(done.rounds[number - 1].reveal!.correctAnswer).toBe(puzzle.cubes.length);
    expect(done.rounds[number - 1].reveal!.puzzle).toEqual(puzzle);
    if (number < 5)
      expect(
        (await request(0, `matches/${created.id}/rounds/${number + 1}/start`, 'POST')).statusCode,
      ).toBe(409);
    now += 1000;
    const reconnect = (await request(0, `matches/${created.id}`)).json<MatchView>();
    expect(reconnect.rounds[number - 1].reveal).toEqual(done.rounds[number - 1].reveal);
    if (number === 5) expect(reconnect.yoursComplete).toBe(true);
  }
});
