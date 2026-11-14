import { afterAll, beforeAll, beforeEach, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { openDatabase } from '@brain/db';
import { visualMemoryPattern, visualMemoryRules, visualMemoryScore } from '@brain/games';
import { type LiveSnapshot, type MemoryPlayerView } from '@brain/shared';
import { liveCommand } from '@brain/shared/live';
import { LiveService } from '../apps/api/src/live-service.js';
import { GameService } from '../apps/api/src/service.js';
import { createApp } from '../apps/api/src/app.js';

let database: Awaited<ReturnType<typeof openDatabase>>;
let service: LiveService;
let now: number;
let ids: string[];
beforeAll(async () => {
  database = await openDatabase();
  ids = Array.from({ length: 4 }, () => randomUUID());
  const profiles = new GameService(database.db, 'http://localhost:3000');
  for (const id of ids) await profiles.profile(id);
});
beforeEach(() => {
  now = 1_800_000_000_000;
  service = new LiveService(database.db, () => now);
});
afterAll(async () => {
  await database.close();
});
const mine = (state: LiveSnapshot, id = ids[0]) =>
  state.memory!.players.find((p) => p.playerId === id)!;
async function solo() {
  return service.create(ids[0], {
    format: 'visual-memory',
    solo: true,
    capacity: 1,
    roundCount: 1,
  });
}
async function start(mode: 'duel' | 'party' = 'duel') {
  const room = await service.create(ids[0], {
    format: 'visual-memory',
    mode,
    capacity: mode === 'party' ? 3 : 2,
  });
  const players = ids.slice(0, mode === 'party' ? 3 : 2);
  for (const id of players) {
    if (id !== ids[0]) await service.join(room.code, id);
    await service.watch(room.code, id, id);
    await service.command(room.code, id, { action: 'ready', ready: true });
  }
  return service.command(room.code, ids[0], { action: 'start' });
}
async function recall(code: string, id = ids[0]) {
  let room = await service.view(code, id);
  let p = mine(room, id);
  now = Math.max(now, p.startsAt);
  room = await service.view(code, id);
  p = mine(room, id);
  const pattern = p.highlighted!;
  expect(pattern).toHaveLength(p.targetCount);
  now = p.displayUntil;
  room = await service.view(code, id);
  expect(mine(room, id).highlighted).toBeUndefined();
  return { room, p: mine(room, id), pattern };
}
async function tap(code: string, p: MemoryPlayerView, tile: number) {
  return service.command(code, p.playerId, {
    action: 'memory-tap',
    level: p.level,
    attempt: p.attempt,
    tile,
  });
}
async function lose(code: string, id = ids[0]) {
  const { p, pattern } = await recall(code, id);
  const wrong = Array.from({ length: p.gridSize ** 2 }, (_, i) => i)
    .filter((i) => !pattern.includes(i))
    .slice(0, 3);
  let room!: LiveSnapshot;
  for (const tile of wrong) room = await tap(code, p, tile);
  return room;
}

it('generates stable unique solvable patterns and grows difficulty without a final level', () => {
  for (let level = 1; level <= 1000; level++) {
    const rules = visualMemoryRules(level);
    const pattern = visualMemoryPattern('fair-seed', level, 1);
    expect(pattern).toEqual(visualMemoryPattern('fair-seed', level, 1));
    expect(new Set(pattern).size).toBe(rules.targetCount);
    expect(pattern.every((tile) => tile >= 0 && tile < rules.gridSize ** 2)).toBe(true);
    expect(rules.gridSize ** 2 - pattern.length).toBeGreaterThanOrEqual(3);
    expect(rules.gridSize).toBeLessThanOrEqual(8);
    expect(rules.displayMs).toBeGreaterThanOrEqual(600);
  }
  expect(visualMemoryPattern('fair-seed', 4, 1)).not.toEqual(
    visualMemoryPattern('fair-seed', 4, 2),
  );
  expect(() => visualMemoryRules(0)).toThrow();
  expect(visualMemoryScore(3, 2, 1)).toBe(2019);
});

it('blocks early taps, out-of-grid taps, duplicate taps, and untrusted scoring fields', async () => {
  const initial = await solo();
  const p = mine(initial);
  const early = await tap(initial.code, p, p.highlighted![0]);
  expect(mine(early).correct).toEqual([]);
  expect(mine(early).mistakes).toBe(0);
  const turn = await recall(initial.code);
  await expect(tap(initial.code, turn.p, 63)).rejects.toMatchObject({ statusCode: 400 });
  const wrong = Array.from({ length: 9 }, (_, i) => i).find((i) => !turn.pattern.includes(i))!;
  await Promise.all(Array.from({ length: 6 }, () => tap(initial.code, turn.p, wrong)));
  let result = mine(await service.view(initial.code, ids[0]));
  expect(result.mistakes).toBe(1);
  expect(result.lives).toBe(3);
  await Promise.all(Array.from({ length: 4 }, () => tap(initial.code, turn.p, turn.pattern[0])));
  result = mine(await service.view(initial.code, ids[0]));
  expect(result.correct).toEqual([turn.pattern[0]]);
  expect(result.mistakes).toBe(1);
  expect(
    liveCommand.safeParse({ action: 'memory-tap', level: 1, attempt: 1, tile: 0, score: 999999 })
      .success,
  ).toBe(false);
});

it('loses exactly one heart for each three distinct mistakes and ends after nine', async () => {
  const initial = await solo();
  for (let attempt = 1; attempt <= 3; attempt++) {
    const room = await lose(initial.code);
    const p = mine(room);
    expect(p.lives).toBe(3 - attempt);
    expect(p.mistakes).toBe(0);
    expect(p.totalMistakes).toBe(attempt * 3);
    expect(p.level).toBe(1);
    expect(p.attempt).toBe(attempt);
    if (attempt < 3) {
      expect(p.phase).toBe('lifeLost');
      expect(p.wrong).toHaveLength(3);
      now = p.nextAt!;
      const next = await service.view(room.code, ids[0]);
      expect(mine(next).attempt).toBe(attempt + 1);
      expect(mine(next).correct).toEqual([]);
    } else {
      expect(room.status).toBe('completed');
      expect(p.phase).toBe('finished');
      expect(p.finishReason).toBe('eliminated');
    }
  }
  const history = await service.memoryHistory(ids[0]);
  expect(history.games.find((g) => g.code === initial.code)).toMatchObject({
    completed: true,
    lives: 0,
    level: 1,
  });
});

it('clears once under simultaneous last taps, resets mistakes, and ignores stale turn commands', async () => {
  const initial = await solo();
  const { p, pattern } = await recall(initial.code);
  const wrong = Array.from({ length: 9 }, (_, i) => i).find((i) => !pattern.includes(i))!;
  await tap(initial.code, p, wrong);
  for (const tile of pattern.slice(0, -1)) await tap(initial.code, p, tile);
  const results = await Promise.all(
    Array.from({ length: 5 }, () => tap(initial.code, p, pattern.at(-1)!)),
  );
  expect(results.every((r) => mine(r).phase === 'cleared')).toBe(true);
  expect(mine(results[0]).score).toBe(999);
  now = mine(results[0]).nextAt!;
  const next = await service.view(initial.code, ids[0]);
  expect(mine(next)).toMatchObject({ level: 2, attempt: 1, mistakes: 0, lives: 3, score: 999 });
  await tap(initial.code, p, wrong);
  expect(mine(await service.view(initial.code, ids[0]))).toMatchObject({
    level: 2,
    mistakes: 0,
    lives: 3,
  });
});

it('supports unlimited solo progression and preserves state and original clocks on restart', async () => {
  const initial = await solo();
  for (let level = 1; level <= 55; level++) {
    const { p, pattern } = await recall(initial.code);
    expect(p.level).toBe(level);
    let room!: LiveSnapshot;
    for (const tile of pattern) room = await tap(initial.code, p, tile);
    expect(mine(room).score).toBe(level * 1000);
    now = mine(room).nextAt!;
    await service.view(initial.code, ids[0]);
  }
  const turn = await recall(initial.code);
  now += 24 * 60 * 60 * 1000;
  service = new LiveService(database.db, () => now);
  const restored = await service.view(initial.code, ids[0]);
  expect(restored.status).toBe('running');
  expect(restored.memory!.endsAt).toBeNull();
  expect(mine(restored)).toMatchObject({ level: 56, lives: 3, displayUntil: turn.p.displayUntil });
  expect((await service.memoryHistory(ids[0])).bestLevel).toBeGreaterThanOrEqual(56);
}, 30_000);

it('gives rivals equal patterns and independent progress, with private personalized projections', async () => {
  const initial = await start();
  const a = mine(initial);
  expect(a.highlighted).toBeDefined();
  expect(mine(initial, ids[1]).highlighted).toBeUndefined();
  const other = await service.view(initial.code, ids[1]);
  expect(mine(other, ids[1]).highlighted).toEqual(a.highlighted);
  expect(mine(other).highlighted).toBeUndefined();
  expect(JSON.stringify(initial)).not.toMatch(/seed/);
  const { p, pattern } = await recall(initial.code);
  for (const tile of pattern) await tap(initial.code, p, tile);
  let room = await service.view(initial.code, ids[0]);
  now = mine(room).nextAt!;
  room = await service.view(initial.code, ids[0]);
  expect(mine(room).level).toBe(2);
  expect(mine(room, ids[1]).level).toBe(1);
  expect(mine(room, ids[1]).lives).toBe(3);
  const opponentView = await service.view(initial.code, ids[1]);
  expect(mine(opponentView).highlighted).toBeUndefined();
  expect(mine(opponentView).correct).toEqual([]);
  expect(room.status).toBe('running');
});

it('keeps retry patterns equal, and explicit missed-pattern retries cost exactly one heart', async () => {
  const initial = await start();
  const turn = await recall(initial.code);
  for (const id of ids.slice(0, 2)) {
    await service.command(initial.code, id, { action: 'memory-retry', level: 1, attempt: 1 });
  }
  const after = await service.view(initial.code, ids[0]);
  expect(
    after.memory!.players.every(
      (p) => p.lives === 2 && p.totalMistakes === 0 && p.lifeLossReason === 'retry',
    ),
  ).toBe(true);
  now = mine(after).nextAt!;
  const a = await service.view(initial.code, ids[0]);
  const b = await service.view(initial.code, ids[1]);
  expect(mine(a).highlighted).toEqual(mine(b, ids[1]).highlighted);
  expect(mine(a).highlighted).not.toEqual(turn.pattern);
  await service.command(initial.code, ids[0], { action: 'memory-retry', level: 1, attempt: 1 });
  expect(mine(await service.view(initial.code, ids[0])).lives).toBe(2);
});

it('lets eliminated players wait, preserves disconnect deadlines, and finishes offline players at the cap', async () => {
  const initial = await start();
  for (let i = 0; i < 3; i++) {
    const failed = await lose(initial.code);
    if (i < 2) {
      now = mine(failed).nextAt!;
      await service.view(initial.code, ids[0]);
    }
  }
  expect((await service.view(initial.code, ids[0])).status).toBe('running');
  await service.disconnect(ids[1]);
  service = new LiveService(database.db, () => now);
  const restored = await service.watch(initial.code, ids[1], 'reconnected');
  expect(restored.memory!.endsAt).toBe(initial.memory!.endsAt);
  now = initial.memory!.endsAt!;
  await service.tick();
  const final = await service.view(initial.code, ids[1]);
  expect(final.status).toBe('completed');
  expect(mine(final, ids[1])).toMatchObject({ finishReason: 'time', lives: 3 });
  expect(mine(final).lives).toBe(0);
  const frozen = mine(final, ids[1]).score;
  await tap(initial.code, mine(final, ids[1]), 0);
  expect(mine(await service.view(initial.code, ids[1]), ids[1]).score).toBe(frozen);
});

it('uses existing party readiness, rankings, forfeits, membership, and one shared rematch lobby', async () => {
  const initial = await start('party');
  await expect(service.view(initial.code, ids[3])).rejects.toMatchObject({ statusCode: 403 });
  await service.command(initial.code, ids[2], { action: 'leave' });
  now = initial.memory!.endsAt!;
  const final = await service.view(initial.code, ids[0]);
  expect(final.status).toBe('completed');
  expect(final.standings.map((p) => p.rank)).toEqual([1, 1, 3]);
  const [a, b] = await Promise.all(
    ids.slice(0, 2).map((id) => service.command(initial.code, id, { action: 'rematch' })),
  );
  expect(a.rematchCode).toBe(b.rematchCode);
  const rematch = await service.join(a.rematchCode!, ids[1]);
  expect(rematch).toMatchObject({
    mode: 'party',
    format: 'visual-memory',
    status: 'lobby',
    rulesVersion: 1,
  });
  expect(rematch.memory).toBeUndefined();
  expect(rematch.players.every((p) => !p.ready)).toBe(true);
});

it('authorizes native solo, history, and commands and restarts solo with fresh hearts', async () => {
  const { app } = await createApp({
    db: database.db,
    origin: 'http://localhost:3000',
    secret: 'visual-memory-test-secret-at-least-32',
    now: () => now,
  });
  try {
    const login = await app.inject({ method: 'POST', url: '/api/native/session' });
    const headers = { authorization: `Bearer ${login.headers['x-brain-session']}` };
    const response = await app.inject({
      method: 'POST',
      url: '/api/visual-memory/solo',
      headers,
      payload: {},
    });
    expect(response.statusCode).toBe(200);
    const room = response.json<LiveSnapshot>();
    expect(room.mode).toBe('solo');
    expect(room.format).toBe('visual-memory');
    expect((await app.inject({ url: '/api/visual-memory/history' })).statusCode).toBe(401);
    const outsider = await app.inject({ method: 'POST', url: '/api/native/session' });
    const otherHeaders = { authorization: `Bearer ${outsider.headers['x-brain-session']}` };
    expect(
      (
        await app.inject({
          method: 'POST',
          url: `/api/live/rooms/${room.code}/join`,
          headers: otherHeaders,
          payload: {},
        })
      ).statusCode,
    ).toBe(403);
    expect(
      (await app.inject({ url: `/api/live/rooms/${room.code}`, headers: otherHeaders })).statusCode,
    ).toBe(403);
    expect(
      (
        await app.inject({
          method: 'POST',
          url: `/api/live/rooms/${room.code}/command`,
          headers: otherHeaders,
          payload: { action: 'leave' },
        })
      ).statusCode,
    ).toBe(403);
    const finish = await app.inject({
      method: 'POST',
      url: `/api/live/rooms/${room.code}/command`,
      headers,
      payload: { action: 'leave' },
    });
    expect(finish.json().status).toBe('completed');
    const again = await app.inject({
      method: 'POST',
      url: `/api/live/rooms/${room.code}/command`,
      headers,
      payload: { action: 'rematch' },
    });
    const fresh = await app.inject({ url: `/api/live/rooms/${again.json().rematchCode}`, headers });
    expect(fresh.json().memory.players[0]).toMatchObject({ lives: 3, level: 1, mistakes: 0 });
    expect(fresh.json().status).toBe('running');
    const history = await app.inject({ url: '/api/visual-memory/history', headers });
    expect(history.json().games.some((g: { code: string }) => g.code === room.code)).toBe(true);
    const otherHistory = await app.inject({
      url: '/api/visual-memory/history',
      headers: otherHeaders,
    });
    expect(otherHistory.json().games).toEqual([]);
  } finally {
    await app.close();
  }
});

it('plays an eight-player Visual Memory party over authenticated sockets with private broadcasts and early results', async () => {
  const { io } = await import('socket.io-client');
  const server = await createApp({
    db: database.db,
    origin: 'http://localhost:3000',
    secret: 'memory-socket-tests-secret-at-least-32',
    now: () => now,
  });
  const sockets: ReturnType<typeof io>[] = [];
  try {
    await server.app.listen({ host: '127.0.0.1', port: 0 });
    const base = `http://127.0.0.1:${(server.app.server.address() as { port: number }).port}`;
    const guests: { id: string; token: string }[] = [];
    for (let i = 0; i < 8; i++) {
      const session = await server.app.inject({ method: 'POST', url: '/api/native/session' });
      guests.push({
        id: session.json().id as string,
        token: session.headers['x-brain-session'] as string,
      });
    }
    const created = await server.app.inject({
      method: 'POST',
      url: '/api/live/rooms',
      headers: { authorization: `Bearer ${guests[0].token}` },
      payload: { format: 'visual-memory', mode: 'party', capacity: 8 },
    });
    expect(created.statusCode).toBe(200);
    const code = created.json().code as string;
    const leaks: string[] = [];
    const completed: Promise<LiveSnapshot>[] = [];
    for (let i = 0; i < guests.length; i++) {
      const g = guests[i];
      if (i)
        await server.app.inject({
          method: 'POST',
          url: `/api/live/rooms/${code}/join`,
          headers: { authorization: `Bearer ${g.token}` },
          payload: {},
        });
      const socket = io(base, {
        transports: ['websocket'],
        reconnection: false,
        extraHeaders: { Authorization: `Bearer ${g.token}` },
      });
      sockets.push(socket);
      await new Promise<void>((resolve, reject) => {
        socket.once('connect', resolve);
        socket.once('connect_error', reject);
      });
      completed.push(
        new Promise((resolve) => {
          socket.on('room:state', (state: LiveSnapshot) => {
            if (JSON.stringify(state).includes('"seed"')) leaks.push('seed');
            for (const p of state.memory?.players ?? []) {
              if (p.playerId !== g.id && (p.highlighted || p.correct.length || p.wrong.length))
                leaks.push(g.id);
            }
            if (state.status === 'completed') resolve(state);
          });
        }),
      );
      expect((await socket.emitWithAck('room:watch', { code })).ok).toBe(true);
      expect(
        (
          await socket.emitWithAck('room:command', {
            code,
            command: { action: 'ready', ready: true },
          })
        ).ok,
      ).toBe(true);
    }
    const start = await sockets[0].emitWithAck('room:command', {
      code,
      command: { action: 'start' },
    });
    const endsAt = start.state.memory.endsAt;
    for (let attempt = 1; attempt <= 3; attempt++) {
      const views = await Promise.all(sockets.map((s) => s.emitWithAck('room:watch', { code })));
      const own = views.map((v, i) => mine(v.state, guests[i].id));
      expect(own.every((p) => p.attempt === attempt)).toBe(true);
      expect(
        own.every((p) => JSON.stringify(p.highlighted) === JSON.stringify(own[0].highlighted)),
      ).toBe(true);
      now = own[0].displayUntil;
      for (let mistake = 0; mistake < 3; mistake++) {
        await Promise.all(
          sockets.map(async (s, i) => {
            const p = own[i];
            const wrong = Array.from({ length: 9 }, (_, tile) => tile).filter(
              (tile) => !p.highlighted!.includes(tile),
            );
            const ack = await s.emitWithAck('room:command', {
              code,
              command: { action: 'memory-tap', level: 1, attempt, tile: wrong[mistake] },
            });
            expect(ack.ok).toBe(true);
          }),
        );
      }
      if (attempt < 3) {
        const state = (await sockets[0].emitWithAck('room:watch', { code })).state as LiveSnapshot;
        now = mine(state, guests[0].id).nextAt!;
        await server.live.tick();
      }
    }
    const results = await Promise.all(completed);
    expect(now).toBeLessThan(endsAt);
    expect(results.every((r) => r.standings.every((s) => s.rank === 1))).toBe(true);
    expect(results.every((r) => r.memory!.players.every((p) => p.lives === 0))).toBe(true);
    expect(leaks).toEqual([]);
  } finally {
    sockets.forEach((s) => s.disconnect());
    await server.app.close();
  }
}, 20_000);
