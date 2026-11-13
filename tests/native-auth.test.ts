import { afterAll, beforeAll, beforeEach, expect, it } from 'vitest';
import { and, eq, sql } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { openDatabase, rounds } from '@brain/db';
import { getGame } from '@brain/games';
import { type MatchView, type Puzzle } from '@brain/shared';
import { createApp } from '../apps/api/src/app.js';

let database: Awaited<ReturnType<typeof openDatabase>>;
let server: Awaited<ReturnType<typeof createApp>>;
let now = 1_800_000_000_000;
beforeAll(async () => {
  database = await openDatabase();
  server = await createApp({
    db: database.db,
    secret: 'native-test-secret-at-least-thirty-two-characters',
    origin: 'http://localhost:3000',
    now: () => now,
  });
});
beforeEach(async () => {
  now = 1_800_000_000_000;
  await database.db.execute(sql`TRUNCATE attempts, rounds, matches, profiles CASCADE`);
});
afterAll(async () => {
  await server.app.close();
  await database.close();
});
async function native() {
  const response = await server.app.inject({ method: 'POST', url: '/api/native/session' });
  expect(response.statusCode).toBe(200);
  expect(response.cookies).toHaveLength(0);
  return { token: String(response.headers['x-brain-session']), profile: response.json() };
}
const headers = (token: string) => ({ authorization: `Bearer ${token}` });
it('creates and restores a signed native guest without using web cookies', async () => {
  const guest = await native();
  expect(guest.token).not.toBe('undefined');
  const restored = await server.app.inject({
    method: 'POST',
    url: '/api/native/session',
    headers: headers(guest.token),
  });
  expect(restored.json()).toEqual(guest.profile);
  expect(restored.cookies).toHaveLength(0);
  const renamed = await server.app.inject({
    method: 'PATCH',
    url: '/api/profile',
    headers: headers(guest.token),
    payload: { name: 'Native Brain' },
  });
  expect(renamed.json()).toEqual({ id: guest.profile.id, name: 'Native Brain' });
});
it('rejects tampered, expired, malformed and wrong-transport credentials', async () => {
  const guest = await native();
  for (const token of ['forged', guest.token + 'changed']) {
    const response = await server.app.inject({
      method: 'POST',
      url: '/api/native/session',
      headers: headers(token),
    });
    expect(response.statusCode).toBe(401);
    expect(response.headers['x-brain-session']).toBeUndefined();
  }
  const web = await server.app.inject({ method: 'POST', url: '/api/session' });
  const webToken = web.cookies[0].value;
  expect(
    (await server.app.inject({ method: 'GET', url: '/api/matches', headers: headers(webToken) }))
      .statusCode,
  ).toBe(401);
  expect(
    (
      await server.app.inject({
        method: 'GET',
        url: '/api/matches',
        headers: { cookie: `bb-session=${encodeURIComponent(guest.token)}` },
      })
    ).statusCode,
  ).toBe(401);
  expect(
    (
      await server.app.inject({
        method: 'GET',
        url: '/api/matches',
        headers: {
          authorization: 'Basic anything',
          cookie: `bb-session=${encodeURIComponent(webToken)}`,
        },
      })
    ).statusCode,
  ).toBe(401);
  now += 30 * 24 * 60 * 60 * 1000;
  expect(
    (
      await server.app.inject({
        method: 'POST',
        url: '/api/native/session',
        headers: headers(guest.token),
      })
    ).statusCode,
  ).toBe(401);
});
it('does not let a bearer guest authorize another player’s match', async () => {
  const a = await native(),
    b = await native();
  const created = await server.app.inject({
    method: 'POST',
    url: '/api/matches',
    headers: headers(a.token),
    payload: { mode: 'challenge' },
  });
  const match = created.json<MatchView>();
  expect(
    (
      await server.app.inject({
        method: 'GET',
        url: `/api/matches/${match.id}`,
        headers: headers(b.token),
      })
    ).statusCode,
  ).toBe(404);
});
it('plays a native/web challenge with the same puzzles, scores, deadlines and rematch API', async () => {
  const a = await native();
  const web = await server.app.inject({ method: 'POST', url: '/api/session' });
  const cookie = `bb-session=${encodeURIComponent(web.cookies[0].value)}`;
  const created = await server.app.inject({
    method: 'POST',
    url: '/api/matches',
    headers: headers(a.token),
    payload: { mode: 'challenge' },
  });
  const match = created.json<MatchView>();
  const puzzles: (Puzzle | undefined)[] = [];
  const play = async (auth: Record<string, string>, compare: boolean) => {
    for (let number = 1; number <= 5; number++) {
      const url = `/api/matches/${match.id}/rounds/${number}`;
      const start = (
        await server.app.inject({ method: 'POST', url: `${url}/start`, headers: auth })
      ).json<MatchView>();
      if (compare) expect(start.rounds[number - 1].puzzle).toEqual(puzzles[number - 1]);
      else puzzles.push(start.rounds[number - 1].puzzle);
      expect(start.rounds[number - 1].opponent).toBeUndefined();
      now += 1000;
      const retry = (
        await server.app.inject({ method: 'POST', url: `${url}/start`, headers: auth })
      ).json<MatchView>();
      expect(retry.rounds[number - 1].deadline).toBe(start.rounds[number - 1].deadline);
      now = start.rounds[number - 1].displayUntil! + 1000;
      const [round] = await database.db
        .select()
        .from(rounds)
        .where(and(eq(rounds.matchId, match.id), eq(rounds.number, number)));
      const payload = {
        answer: getGame('counting-boxes', match.rulesVersion).generate(round.seed, number).answer,
        submissionId: randomUUID(),
      };
      const result = await server.app.inject({
        method: 'POST',
        url: `${url}/attempt`,
        headers: auth,
        payload,
      });
      const duplicate = await server.app.inject({
        method: 'POST',
        url: `${url}/attempt`,
        headers: auth,
        payload,
      });
      expect(result.statusCode).toBe(200);
      expect(duplicate.json()).toEqual(result.json());
      expect(result.json<MatchView>().rounds[number - 1].attempt?.correct).toBe(true);
      expect(JSON.stringify(result.json())).not.toMatch(/"seed"/);
      expect(
        result
          .json<MatchView>()
          .rounds.filter((r) => r.state !== 'done')
          .every((r) => r.reveal === undefined),
      ).toBe(true);
      now += start.rounds[number - 1].rules!.feedbackMs;
    }
  };
  await play(headers(a.token), false);
  const token = match.inviteUrl!.split('/').at(-1);
  expect(
    (
      await server.app.inject({
        method: 'POST',
        url: `/api/invitations/${token}/claim`,
        headers: { cookie },
      })
    ).statusCode,
  ).toBe(200);
  await play({ cookie }, true);
  const final = (
    await server.app.inject({
      method: 'GET',
      url: `/api/matches/${match.id}`,
      headers: headers(a.token),
    })
  ).json<MatchView>();
  expect(final.complete).toBe(true);
  expect(final.winner).toBe('draw');
  expect(final.total).toBe(final.opponentTotal);
  const rematch = await server.app.inject({
    method: 'POST',
    url: `/api/matches/${match.id}/rematch`,
    headers: headers(a.token),
  });
  expect(rematch.statusCode).toBe(200);
  expect(rematch.json<MatchView>().id).not.toBe(match.id);
});
