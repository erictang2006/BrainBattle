/** Opt-in smoke check. Creates three new guests and fresh test matches via public APIs.
 * No database access, migrations, website requests, or credential logging.
 * Run: node --import tsx scripts/check-hosted-beta.ts https://YOUR-API-HOST
 */
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { io, type Socket } from 'socket.io-client';
import type { LiveSnapshot, MatchView } from '@brain/shared';
const url = new URL(process.argv[2] ?? '');
assert(
  url.protocol === 'https:' &&
    url.pathname === '/' &&
    !url.search &&
    !url.username &&
    !url.password,
  'Supply an HTTPS API origin only.',
);
const base = url.origin;
type Guest = { id: string; token: string };
async function request<T>(
  path: string,
  guest?: Guest,
  method = 'GET',
  body?: unknown,
  expected = 200,
): Promise<T> {
  const response = await fetch(`${base}/api/${path}`, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(25_000),
    headers: {
      ...(guest ? { Authorization: `Bearer ${guest.token}` } : {}),
      ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  const rotated = response.headers.get('x-brain-session');
  if (guest && rotated) guest.token = rotated;
  assert.equal(
    response.status,
    expected,
    `${method} ${path.replace(/[a-f0-9]{48}/g, '[invitation]')} HTTP status`,
  );
  const data = await response.json();
  if (path === 'native/session' && !guest) return { id: data.id, token: rotated } as T;
  return data as T;
}
const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, Math.max(0, ms)));
async function main() {
  const health = await request<{ ok: boolean; auth: string }>('health');
  assert(health.ok && health.auth === 'supabase');
  const guests: Guest[] = [];
  for (let i = 0; i < 3; i++) {
    const guest = await request<Guest>('native/session', undefined, 'POST');
    assert(guest.token && guest.id);
    guests.push(guest);
    const restored = await request<{ id: string }>('native/session', guest, 'POST');
    assert.equal(restored.id, guest.id);
  }
  assert.equal(new Set(guests.map((g) => g.id)).size, 3);
  console.log('PASS: hosted Supabase guest creation, authenticated restore, separate identities');
  const created = await request<MatchView>('matches', guests[0], 'POST', { mode: 'challenge' });
  const token = created.inviteUrl?.split('/').at(-1);
  assert(token && /^[a-f0-9]{48}$/.test(token));
  const preview = await request<{ claimed: boolean }>(`invitations/${token}`, guests[1]);
  assert.equal(preview.claimed, false);
  await request(`invitations/${token}/claim`, guests[1], 'POST');
  await request(`invitations/${token}/claim`, guests[2], 'POST', undefined, 409);
  console.log(
    'PASS: async token preview/redemption and single-use claim, without requesting any website URL',
  );
  let final: MatchView | undefined;
  for (let round = 1; round <= 5; round++) {
    const views = await Promise.all(
      guests
        .slice(0, 2)
        .map((g) => request<MatchView>(`matches/${created.id}/rounds/${round}/start`, g, 'POST')),
    );
    const puzzles = views.map((v) => v.rounds[round - 1]);
    assert.deepEqual(puzzles[0].puzzle, puzzles[1].puzzle);
    const answer = puzzles[0].puzzle!.cubes.length;
    await wait(Math.max(...views.map((v, i) => puzzles[i].displayUntil! - v.serverNow)) + 200);
    const results = await Promise.all(
      guests
        .slice(0, 2)
        .map((g) =>
          request<MatchView>(`matches/${created.id}/rounds/${round}/attempt`, g, 'POST', {
            answer,
            submissionId: randomUUID(),
          }),
        ),
    );
    assert(results.every((v) => v.rounds[round - 1].attempt?.correct));
    final = results[1];
  }
  const both = await Promise.all(
    guests.slice(0, 2).map((g) => request<MatchView>(`matches/${created.id}`, g)),
  );
  assert(both.every((v) => v.complete));
  assert.equal(both[0].winner, both[1].winner);
  const rematch = await request<MatchView>(`matches/${created.id}/rematch`, guests[0], 'POST');
  assert.notEqual(rematch.id, final!.id);
  assert.notEqual(rematch.inviteUrl, created.inviteUrl);
  console.log('PASS: five async rounds, equivalent puzzles, agreed results, fresh rematch');
  for (const mode of ['duel', 'party'] as const)
    await live(mode, guests.slice(0, mode === 'duel' ? 2 : 3));
  console.log(
    'PASS: hosted beta smoke checks complete; no secrets or invitation codes written to disk',
  );
}
async function connect(guest: Guest) {
  const socket = io(base, {
    path: '/socket.io',
    transports: ['websocket'],
    extraHeaders: { Authorization: `Bearer ${guest.token}` },
    reconnection: false,
    timeout: 20_000,
  });
  try {
    await new Promise<void>((resolve, reject) => {
      socket.once('connect', resolve);
      socket.once('connect_error', reject);
    });
  } catch (error) {
    socket.disconnect();
    throw error;
  }
  return socket;
}
async function command(socket: Socket, code: string, command: unknown): Promise<LiveSnapshot> {
  const ack = await socket.timeout(25_000).emitWithAck('room:command', { code, command });
  assert(ack.ok, `Live command rejected: ${(command as { action: string }).action}`);
  return ack.state;
}
async function watch(socket: Socket, code: string): Promise<LiveSnapshot> {
  const ack = await socket.timeout(25_000).emitWithAck('room:watch', { code });
  assert(ack.ok, 'Room subscription');
  return ack.state;
}
async function live(mode: 'duel' | 'party', guests: Guest[]) {
  const room = await request<LiveSnapshot>('live/rooms', guests[0], 'POST', {
    mode,
    capacity: guests.length,
  });
  assert(/^[A-HJ-NP-Z2-9]{6}$/.test(room.code));
  for (const guest of guests.slice(1))
    await request(`live/rooms/${room.code}/join`, guest, 'POST', {});
  const sockets: Socket[] = [];
  try {
    for (const guest of guests) {
      const socket = await connect(guest);
      sockets.push(socket);
      await watch(socket, room.code);
      await command(socket, room.code, { action: 'ready', ready: true });
    }
    let state = await command(sockets[0], room.code, { action: 'start' });
    const deadline = state.round!.deadline;
    sockets[0].disconnect();
    sockets[0] = await connect(guests[0]);
    const restored = await watch(sockets[0], room.code);
    assert.equal(restored.round!.deadline, deadline);
    for (let round = 1; round <= 5; round++) {
      const views = await Promise.all(sockets.map((s) => watch(s, room.code)));
      assert(views.every((v) => v.round!.number === round));
      for (const v of views) assert.deepEqual(v.round!.puzzle, state.round!.puzzle);
      assert(views.every((v) => !v.round!.results));
      const answer = state.round!.puzzle!.cubes.length;
      await wait(Math.max(...views.map((v) => v.round!.displayUntil - v.serverNow)) + 200);
      const ids = guests.map(() => randomUUID());
      const submissions = await Promise.all(
        sockets.map((s, i) =>
          command(s, room.code, { action: 'submit', round, answer, submissionId: ids[i] }),
        ),
      );
      state = submissions.find((v) => v.round!.results) ?? (await watch(sockets[0], room.code));
      assert.equal(state.round!.results!.length, guests.length);
      assert(state.round!.results!.every((r) => r.correct && r.score > 0));
      const repeated = await command(sockets[0], room.code, {
        action: 'submit',
        round,
        answer: 0,
        submissionId: ids[0],
      });
      assert.deepEqual(repeated.round!.results, state.round!.results);
      console.log(
        `PASS: hosted ${mode} round ${round}, shared puzzle/results and duplicate protection`,
      );
      if (round < 5) {
        await wait(state.nextAt! - state.serverNow + 200);
        state = await watch(sockets[0], room.code);
      }
    }
    const finals = await Promise.all(sockets.map((s) => watch(s, room.code)));
    assert(finals.every((v) => v.status === 'completed'));
    for (const v of finals) assert.deepEqual(v.standings, state.standings);
    const next = await command(sockets[0], room.code, { action: 'rematch' });
    assert(next.rematchCode && next.rematchCode !== room.code);
    for (const guest of guests)
      await request(`live/rooms/${next.rematchCode}/join`, guest, 'POST', {});
    for (const s of sockets) await command(s, next.rematchCode, { action: 'leave' });
    console.log(`PASS: hosted ${mode} reconnect, five-round final standings and rematch`);
  } finally {
    for (const s of sockets) s.disconnect();
  }
}
main().catch((error) => {
  console.error(error instanceof Error ? error.message : 'Hosted beta check failed');
  process.exitCode = 1;
});
