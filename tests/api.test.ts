import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { and, eq, sql } from 'drizzle-orm';
import { openDatabase, rounds, attempts, matches } from '@brain/db';
import { countingBoxes } from '@brain/games';
import { ANSWER_MS, DISPLAY_MS, type MatchView } from '@brain/shared';
import { createApp } from '../apps/api/src/app.js';
let database: Awaited<ReturnType<typeof openDatabase>>;
let server: Awaited<ReturnType<typeof createApp>>;
let now = 1_800_000_000_000;
const origin = 'http://localhost:3000';
beforeAll(async () => {
  database = await openDatabase();
  server = await createApp({
    db: database.db,
    secret: 'test-secret-that-has-at-least-thirty-two-characters',
    origin,
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
async function guest() {
  const response = await server.app.inject({ method: 'POST', url: '/api/session' });
  expect(response.statusCode).toBe(200);
  return {
    cookie: response.cookies[0].name + '=' + encodeURIComponent(response.cookies[0].value),
    profile: response.json(),
  };
}
async function request(
  cookie: string,
  method: 'GET' | 'POST' | 'PATCH',
  url: string,
  payload?: Record<string, unknown>,
) {
  return server.app.inject({ method, url, headers: { cookie, origin }, payload });
}
async function create(cookie: string, mode = 'challenge') {
  const res = await request(cookie, 'POST', '/api/matches', { mode });
  expect(res.statusCode).toBe(200);
  const created = res.json<MatchView>();
  // This suite is the unchanged legacy behavior contract for stored v1 matches.
  await database.db.update(matches).set({ rulesVersion: 1 }).where(eq(matches.id, created.id));
  return (await request(cookie, 'GET', `/api/matches/${created.id}`)).json<MatchView>();
}
async function start(cookie: string, id: string, round: number) {
  const res = await request(cookie, 'POST', `/api/matches/${id}/rounds/${round}/start`);
  expect(res.statusCode).toBe(200);
  return res.json<MatchView>();
}
async function answerFor(id: string, number: number) {
  const [round] = await database.db
    .select()
    .from(rounds)
    .where(and(eq(rounds.matchId, id), eq(rounds.number, number)));
  return countingBoxes.generate(round.seed, number).answer;
}
async function submit(
  cookie: string,
  id: string,
  round: number,
  answer: number | null,
  submissionId = randomUUID(),
) {
  return request(cookie, 'POST', `/api/matches/${id}/rounds/${round}/attempt`, {
    answer,
    submissionId,
  });
}
const tokenOf = (m: MatchView) => m.inviteUrl!.split('/').at(-1)!;
describe('authoritative asynchronous challenge', () => {
  it('retains v2 on request and plays identical fast puzzles with authoritative feedback and scores', async () => {
    const a = await guest(),
      b = await guest();
    const m = (
      await request(a.cookie, 'POST', '/api/matches', { mode: 'challenge', rulesVersion: 2 })
    ).json<MatchView>();
    expect(m.rulesVersion).toBe(2);
    const seen: unknown[] = [];
    for (const [index, cookie] of [a.cookie, b.cookie].entries()) {
      if (index === 1)
        expect(
          (await request(cookie, 'POST', `/api/invitations/${tokenOf(m)}/claim`)).statusCode,
        ).toBe(200);
      for (let n = 1; n <= 5; n++) {
        const state = await start(cookie, m.id, n),
          r = state.rounds[n - 1];
        const rules = r.rules!;
        expect(r.displayUntil! - now).toBe(rules.displayMs);
        expect(r.deadline! - r.displayUntil!).toBe(rules.answerMs);
        if (index === 0) seen.push(r.puzzle);
        else expect(r.puzzle).toEqual(seen[n - 1]);
        expect(JSON.stringify(state)).not.toMatch(/"seed"/);
        expect(
          state.rounds.filter((r) => r.state !== 'done').every((r) => r.reveal === undefined),
        ).toBe(true);
        const same = await start(cookie, m.id, n);
        expect(same.rounds[n - 1].deadline).toBe(r.deadline);
        expect((await submit(cookie, m.id, n, 0)).statusCode).toBe(409);
        const answer = r.puzzle!.cubes.length;
        now = r.displayUntil! + rules.answerMs / 2;
        const submissionId = randomUUID();
        const [first, duplicate] = await Promise.all([
          submit(cookie, m.id, n, answer, submissionId),
          submit(cookie, m.id, n, answer, submissionId),
        ]);
        expect(first.json().rounds[n - 1].attempt).toEqual({
          score: 1250,
          correct: true,
          timedOut: false,
        });
        expect(duplicate.json().rounds[n - 1].attempt).toEqual(first.json().rounds[n - 1].attempt);
        expect(first.json().rounds[n - 1].puzzle).toBeUndefined();
        expect(first.json().rounds[n - 1].feedbackUntil).toBe(now + 1000);
        if (n < 5)
          expect(
            (await request(cookie, 'POST', `/api/matches/${m.id}/rounds/${n + 1}/start`))
              .statusCode,
          ).toBe(409);
        now += 1000;
      }
    }
    const result = (await request(a.cookie, 'GET', `/api/matches/${m.id}`)).json<MatchView>();
    expect(result.complete).toBe(true);
    expect(result.total).toBe(6250);
    expect(result.opponentTotal).toBe(6250);
    expect(result.winner).toBe('draw');
    const replay = (
      await request(a.cookie, 'POST', `/api/matches/${m.id}/rematch`)
    ).json<MatchView>();
    expect(replay.rulesVersion).toBe(3);
    expect(replay.id).not.toBe(m.id);
  });
  it('v2 finalizes wrong and expired answers and preserves faster deadlines on refresh', async () => {
    const a = await guest();
    const m = (
      await request(a.cookie, 'POST', '/api/matches', { mode: 'solo', rulesVersion: 2 })
    ).json<MatchView>();
    const first = await start(a.cookie, m.id, 1);
    now = first.rounds[0].displayUntil!;
    expect((await submit(a.cookie, m.id, 1, 99)).json().rounds[0].attempt.correct).toBe(false);
    now += 1000;
    const second = await start(a.cookie, m.id, 2);
    now += 500;
    expect((await start(a.cookie, m.id, 2)).rounds[1].deadline).toBe(second.rounds[1].deadline);
    now = second.rounds[1].deadline!;
    const res = (await request(a.cookie, 'GET', `/api/matches/${m.id}`)).json<MatchView>();
    expect(res.rounds[1].attempt).toEqual({ score: 0, correct: false, timedOut: true });
    expect(res.rounds[1].puzzle).toBeUndefined();
    expect((await submit(a.cookie, m.id, 2, 4)).json().rounds[1].attempt.timedOut).toBe(true);
  });
  it('plays five identical puzzles as two guests and reveals final results to both', async () => {
    const a = await guest(),
      b = await guest();
    const m = await create(a.cookie);
    const puzzles = [];
    expect(m.rounds).toHaveLength(5);
    expect(JSON.stringify(m)).not.toMatch(/seed|correctAnswer|winner/);
    for (let n = 1; n <= 5; n++) {
      const started = await start(a.cookie, m.id, n);
      puzzles.push(started.rounds[n - 1].puzzle);
      now += DISPLAY_MS + 1000;
      const res = await submit(a.cookie, m.id, n, await answerFor(m.id, n));
      expect(res.statusCode).toBe(200);
      expect(res.json<MatchView>().rounds[n - 1].attempt?.score).toBe(1458);
      expect(res.json<MatchView>().rounds[n - 1].opponent).toBeUndefined();
    }
    const beforeClaim = await request(a.cookie, 'GET', `/api/matches/${m.id}`);
    expect(beforeClaim.json().yoursComplete).toBe(true);
    expect(beforeClaim.json().complete).toBe(false);
    const claim = await request(b.cookie, 'POST', `/api/invitations/${tokenOf(m)}/claim`);
    expect(claim.statusCode).toBe(200);
    expect(claim.json().inviteUrl).toBeUndefined();
    expect(claim.json().opponentTotal).toBeUndefined();
    for (let n = 1; n <= 5; n++) {
      const started = await start(b.cookie, m.id, n);
      expect(started.rounds[n - 1].puzzle).toEqual(puzzles[n - 1]);
      expect(started.rounds[n - 1].opponent).toBeUndefined();
      now += DISPLAY_MS + 1000;
      const res = await submit(b.cookie, m.id, n, await answerFor(m.id, n));
      expect(res.statusCode).toBe(200);
      expect(res.json().rounds[n - 1].opponent.score).toBe(1458);
    }
    for (const cookie of [a.cookie, b.cookie]) {
      const result = (await request(cookie, 'GET', `/api/matches/${m.id}`)).json<MatchView>();
      expect(result.complete).toBe(true);
      expect(result.total).toBe(7290);
      expect(result.opponentTotal).toBe(7290);
      expect(result.winner).toBe('draw');
      expect(JSON.stringify(result)).not.toMatch(/"seed"/);
      expect(result.rounds.every((r) => r.puzzle === undefined)).toBe(true);
    }
    const rematch = (
      await request(a.cookie, 'POST', `/api/matches/${m.id}/rematch`)
    ).json<MatchView>();
    expect(rematch.id).not.toBe(m.id);
    expect(rematch.inviteUrl).not.toBe(m.inviteUrl);
    expect(rematch.total).toBe(0);
  });
  it('persists profile, forbids unauthenticated access, and rejects forged player IDs and scores', async () => {
    const a = await guest(),
      other = await guest();
    const m = await create(a.cookie);
    expect(
      (await server.app.inject({ method: 'GET', url: `/api/matches/${m.id}` })).statusCode,
    ).toBe(401);
    expect((await request(other.cookie, 'GET', `/api/matches/${m.id}`)).statusCode).toBe(404);
    expect(
      (await request(other.cookie, 'POST', `/api/matches/${m.id}/rounds/1/start`)).statusCode,
    ).toBe(404);
    expect(
      (await request(a.cookie, 'PATCH', '/api/profile', { name: 'Cube Captain' })).json().name,
    ).toBe('Cube Captain');
    const again = await request(a.cookie, 'POST', '/api/session');
    expect(again.json()).toEqual({ id: a.profile.id, name: 'Cube Captain' });
    expect(
      (
        await request(a.cookie, 'POST', '/api/matches', {
          mode: 'challenge',
          playerId: other.profile.id,
          seed: 'cheat',
        })
      ).statusCode,
    ).toBe(400);
    await start(a.cookie, m.id, 1);
    now += DISPLAY_MS + 100;
    expect(
      (
        await request(a.cookie, 'POST', `/api/matches/${m.id}/rounds/1/attempt`, {
          answer: 3,
          score: 1500,
          submissionId: randomUUID(),
        })
      ).statusCode,
    ).toBe(400);
    expect(
      (
        await server.app.inject({
          method: 'POST',
          url: '/api/matches',
          headers: { cookie: a.cookie, origin: 'https://evil.example' },
          payload: { mode: 'solo' },
        })
      ).statusCode,
    ).toBe(403);
    const forged = await request('bb-session=forged', 'GET', `/api/matches/${m.id}`);
    expect(forged.statusCode).toBe(401);
  });
  it('rejects early answers, skipping rounds and submissions before start', async () => {
    const a = await guest();
    const m = await create(a.cookie, 'solo');
    expect((await submit(a.cookie, m.id, 1, 2)).statusCode).toBe(409);
    expect(
      (await request(a.cookie, 'POST', `/api/matches/${m.id}/rounds/2/start`)).statusCode,
    ).toBe(409);
    await start(a.cookie, m.id, 1);
    expect((await submit(a.cookie, m.id, 1, await answerFor(m.id, 1))).statusCode).toBe(409);
    expect(
      (await request(a.cookie, 'POST', `/api/matches/${m.id}/rounds/6/start`)).statusCode,
    ).toBe(404);
  });
  it('does not extend clocks on retries or refresh and finalizes timeouts authoritatively', async () => {
    const a = await guest();
    const m = await create(a.cookie, 'solo');
    const started = await start(a.cookie, m.id, 1);
    const deadline = started.rounds[0].deadline;
    now += 2500;
    expect((await start(a.cookie, m.id, 1)).rounds[0].deadline).toBe(deadline);
    now += DISPLAY_MS;
    const hidden = (await request(a.cookie, 'GET', `/api/matches/${m.id}`)).json<MatchView>();
    expect(hidden.rounds[0].puzzle).toBeUndefined();
    now = deadline!;
    const late = await submit(a.cookie, m.id, 1, await answerFor(m.id, 1));
    expect(late.statusCode).toBe(200);
    expect(late.json().rounds[0].attempt).toEqual({ score: 0, correct: false, timedOut: true });
    expect((await start(a.cookie, m.id, 1)).rounds[0].deadline).toBe(deadline);
  });
  it('applies concurrent duplicate submissions once and never changes a finalized score', async () => {
    const a = await guest();
    const m = await create(a.cookie, 'solo');
    await start(a.cookie, m.id, 1);
    now += DISPLAY_MS + 100;
    const answer = await answerFor(m.id, 1),
      submissionId = randomUUID();
    const results = await Promise.all([
      submit(a.cookie, m.id, 1, answer, submissionId),
      submit(a.cookie, m.id, 1, answer, submissionId),
      submit(a.cookie, m.id, 1, answer + 1),
    ]);
    for (const res of results) {
      expect(res.statusCode).toBe(200);
      expect(res.json().rounds[0].attempt.correct).toBe(true);
    }
    const rows = await database.db.select().from(attempts).where(eq(attempts.matchId, m.id));
    expect(rows).toHaveLength(1);
    expect(rows[0].answer).toBe(answer);
    await start(a.cookie, m.id, 2);
    now += DISPLAY_MS + 100;
    expect((await submit(a.cookie, m.id, 2, 1, submissionId)).statusCode).toBe(409);
  });
  it('claims an invitation atomically for one guest and makes the claim retryable', async () => {
    const a = await guest(),
      b = await guest(),
      c = await guest();
    const m = await create(a.cookie);
    const url = `/api/invitations/${tokenOf(m)}/claim`;
    const res = await Promise.all([request(b.cookie, 'POST', url), request(c.cookie, 'POST', url)]);
    expect(res.map((r) => r.statusCode).sort()).toEqual([200, 409]);
    const winner = res[0].statusCode === 200 ? b : c;
    expect((await request(winner.cookie, 'POST', url)).statusCode).toBe(200);
    const [stored] = await database.db.select().from(matches).where(eq(matches.id, m.id));
    expect(stored.guestId).toBe(winner.profile.id);
    expect((await request(a.cookie, 'POST', url)).json().opponent.id).toBe(winner.profile.id);
  });
  it('expires invitations and prevents new rounds after match expiry', async () => {
    const a = await guest(),
      b = await guest();
    const m = await create(a.cookie);
    now = m.expiresAt;
    expect(
      (await request(b.cookie, 'POST', `/api/invitations/${tokenOf(m)}/claim`)).statusCode,
    ).toBe(410);
    expect(
      (await request(a.cookie, 'POST', `/api/matches/${m.id}/rounds/1/start`)).statusCode,
    ).toBe(410);
    expect((await request(b.cookie, 'GET', `/api/invitations/${tokenOf(m)}`)).json().expired).toBe(
      true,
    );
  });
});
