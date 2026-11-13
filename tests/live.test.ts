import { afterEach, beforeEach, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { openDatabase, liveRooms } from '@brain/db';
import { getGame } from '@brain/games';
import { GameService } from '../apps/api/src/service.js';
import { LiveService } from '../apps/api/src/live-service.js';
import { createApp } from '../apps/api/src/app.js';
import { io as client, type Socket } from 'socket.io-client';
let database: Awaited<ReturnType<typeof openDatabase>>;
let service: LiveService, now: number, a: string, b: string, c: string;
beforeEach(async () => {
  database = await openDatabase();
  now = 1_800_000_000_000;
  service = new LiveService(database.db, () => now);
  const profiles = new GameService(database.db, 'http://localhost:3000', () => now);
  [a, b, c] = [randomUUID(), randomUUID(), randomUUID()];
  for (const id of [a, b, c]) await profiles.profile(id);
});
afterEach(async () => {
  await database.close();
});
async function start() {
  const { code } = await service.create(a, { rulesVersion: 2, roundCount: 1 });
  await service.join(code, b);
  await service.watch(code, a, 'a');
  await service.watch(code, b, 'b');
  await service.command(code, a, { action: 'ready', ready: true });
  await service.command(code, b, { action: 'ready', ready: true });
  return service.command(code, a, { action: 'start' });
}
it('enforces membership, capacity, host and ready checks and validates equal v2 puzzles', async () => {
  const room = await service.create(a, { rulesVersion: 2, roundCount: 1 });
  await expect(service.view(room.code, c)).rejects.toThrow('not a member');
  await expect(service.command(room.code, a, { action: 'start' })).rejects.toThrow(
    'connected and ready',
  );
  await service.join(room.code, b);
  await expect(service.join(room.code, c)).rejects.toThrow('full');
  await expect(service.command(room.code, b, { action: 'start' })).rejects.toThrow('Only the host');
  const running = await start();
  expect(running.rulesVersion).toBe(2);
  expect(running.round!.startsAt).toBe(now + 4000);
  expect((await service.view(running.code, a)).round!.puzzle).toEqual(
    (await service.view(running.code, b)).round!.puzzle,
  );
  expect(JSON.stringify(running)).not.toMatch(/seed|"answer"|submissionId/);
  await expect(service.join(running.code, c)).rejects.toThrow('started');
  await expect(
    service.command(running.code, a, {
      action: 'submit',
      round: 1,
      answer: 4,
      submissionId: randomUUID(),
    }),
  ).rejects.toThrow('answer window');
});
it('hides early scores, serializes concurrent duplicates and finalizes identical results', async () => {
  const room = await start();
  const answer = room.round!.puzzle!.cubes.length;
  now = room.round!.displayUntil + 100;
  const command = {
    action: 'submit' as const,
    round: 1 as const,
    answer,
    submissionId: randomUUID(),
  };
  const first = await service.command(room.code, a, command);
  expect(first.round!.results).toBeUndefined();
  expect(first.round!.puzzle).toBeUndefined();
  expect(first.round!.reveal).toBeUndefined();
  expect(JSON.stringify(first)).not.toMatch(/correctAnswer|submittedAnswer/);
  await Promise.all([
    service.command(room.code, a, command),
    service.command(room.code, a, { ...command, answer: 0, submissionId: randomUUID() }),
    service.command(room.code, b, { ...command, submissionId: randomUUID() }),
  ]);
  const final = await service.view(room.code, a);
  expect(final.status).toBe('completed');
  expect(final.round!.results).toHaveLength(2);
  expect(final.round!.reveal).toEqual({ puzzle: room.round!.puzzle, correctAnswer: answer });
  expect(final.round!.results!.every((r) => r.submittedAnswer === answer)).toBe(true);
  expect([...final.round!.winners!].sort()).toEqual([a, b].sort());
  expect(final.round!.results![0].score).toBe(
    getGame('counting-boxes', 2).score(answer, answer, 100, 1),
  );
  expect(await service.view(room.code, b)).toEqual(final);
});
it('preserves deadlines after disconnect and service restart, and times out missing attempts', async () => {
  const room = await start();
  await service.disconnect('a');
  service = new LiveService(database.db, () => now);
  const restored = await service.watch(room.code, a, 'new');
  expect(restored.round).toEqual(room.round);
  now = room.round!.deadline!;
  await service.tick();
  const final = await service.view(room.code, b);
  expect(final.status).toBe('completed');
  expect(final.round!.results!.every((r) => r.timedOut && r.score === 0)).toBe(true);
  expect(final.round!.reveal?.puzzle).toEqual(room.round!.puzzle);
  expect(final.round!.reveal?.correctAnswer).toBe(room.round!.puzzle!.cubes.length);
  const late = await service.command(room.code, a, {
    action: 'submit',
    round: 1,
    answer: 5,
    submissionId: randomUUID(),
  });
  expect(late.round!.results).toEqual(final.round!.results);
});
it('transfers a disconnected lobby host after grace and preserves multiple connections', async () => {
  const room = await service.create(a, { rulesVersion: 2, roundCount: 1 });
  await service.join(room.code, b);
  await service.watch(room.code, a, 'a');
  await service.watch(room.code, a, 'a2');
  await service.watch(room.code, b, 'b');
  await service.disconnect('a');
  expect((await service.view(room.code, b)).players.find((p) => p.id === a)!.connected).toBe(true);
  await service.disconnect('a2');
  now += 20_001;
  await service.tick();
  expect((await service.view(room.code, b)).hostId).toBe(b);
  await service.command(room.code, b, { action: 'leave' });
  expect((await service.view(room.code, a)).players).toHaveLength(1);
});
it('voluntary forfeit loses even to a zero-scoring opponent; expired lobbies cannot start', async () => {
  const room = await start();
  await service.command(room.code, a, { action: 'leave' });
  now = room.round!.deadline!;
  await service.tick();
  expect((await service.view(room.code, b)).round!.winners).toEqual([b]);
  const lobby = await service.create(a, { rulesVersion: 2, roundCount: 1 });
  now = lobby.expiresAt;
  expect((await service.view(lobby.code, a)).status).toBe('closed');
});
it('authenticates native Socket.IO polling, rejects outsiders/forged events, and broadcasts public results', async () => {
  const { app } = await createApp({
    db: database.db,
    secret: 'a'.repeat(48),
    origin: 'http://localhost:3000',
    now: () => now,
  });
  const sockets: Socket[] = [];
  try {
    await app.listen({ host: '127.0.0.1', port: 0 });
    const address = app.server.address() as { port: number };
    const base = `http://127.0.0.1:${address.port}`;
    async function guest() {
      const result = await app.inject({ method: 'POST', url: '/api/native/session' });
      return { token: result.headers['x-brain-session'] as string, id: result.json().id as string };
    }
    async function connect(token: string) {
      const s = client(base, {
        transports: ['polling'],
        extraHeaders: { Authorization: `Bearer ${token}` },
        reconnection: false,
      });
      sockets.push(s);
      await new Promise<void>((resolve, reject) => {
        s.once('connect', resolve);
        s.once('connect_error', reject);
      });
      return s;
    }
    const ga = await guest(),
      gb = await guest(),
      gc = await guest();
    const sa = await connect(ga.token),
      sb = await connect(gb.token),
      sc = await connect(gc.token);
    const created = await app.inject({
      method: 'POST',
      url: '/api/live/rooms',
      headers: { authorization: `Bearer ${ga.token}` },
      payload: { roundCount: 1, rulesVersion: 2 },
    });
    const code = created.json().code;
    await app.inject({
      method: 'POST',
      url: `/api/live/rooms/${code}/join`,
      headers: { authorization: `Bearer ${gb.token}` },
      payload: {},
    });
    expect((await sc.emitWithAck('room:watch', { code })).ok).toBe(false);
    for (const s of [sa, sb]) {
      expect((await s.emitWithAck('room:watch', { code })).ok).toBe(true);
      expect(
        (
          await s.emitWithAck('room:command', {
            code,
            command: { action: 'ready', ready: true, playerId: ga.id },
          })
        ).ok,
      ).toBe(false);
      expect(
        (await s.emitWithAck('room:command', { code, command: { action: 'ready', ready: true } }))
          .ok,
      ).toBe(true);
    }
    const started = await sa.emitWithAck('room:command', { code, command: { action: 'start' } });
    expect(started.state.status).toBe('running');
    expect((await sb.emitWithAck('clock:sync', {})).serverNow).toBe(now);
    const deadline = started.state.round.deadline;
    sa.disconnect();
    const reconnect = await connect(ga.token);
    expect((await reconnect.emitWithAck('room:watch', { code })).state.round.deadline).toBe(
      deadline,
    );
    const broadcast = new Promise<any>((resolve) =>
      sb.on('room:state', (state) => {
        if (state.status === 'completed') resolve(state);
      }),
    );
    now = deadline;
    await sb.emitWithAck('room:watch', { code });
    expect((await broadcast).round.results).toHaveLength(2);
    const bad = client(base, {
      transports: ['polling'],
      extraHeaders: { Authorization: 'Bearer fake' },
      reconnection: false,
    });
    sockets.push(bad);
    await expect(
      new Promise<void>((resolve, reject) => {
        bad.once('connect', resolve);
        bad.once('connect_error', reject);
      }),
    ).rejects.toThrow('Authentication');
    now += 31 * 24 * 60 * 60 * 1000;
    expect((await sb.emitWithAck('clock:sync', {})).status).toBe(401);
  } finally {
    for (const s of sockets) s.disconnect();
    await app.close();
  }
});
it('plays five rounds with server intermissions, wins-based standings and one shared rematch', async () => {
  const room = await service.create(a, { rulesVersion: 2 });
  await service.join(room.code, b);
  await service.watch(room.code, a, 'a');
  await service.watch(room.code, b, 'b');
  for (const id of [a, b]) await service.command(room.code, id, { action: 'ready', ready: true });
  let state = await service.command(room.code, a, { action: 'start' });
  for (let round = 1; round <= 5; round++) {
    expect(state.round!.number).toBe(round);
    const answer = state.round!.puzzle!.cubes.length;
    now = state.round!.displayUntil + 100;
    await service.command(room.code, a, {
      action: 'submit',
      round,
      answer,
      submissionId: randomUUID(),
    });
    state = await service.command(room.code, b, {
      action: 'submit',
      round,
      answer: 0,
      submissionId: randomUUID(),
    });
    expect(state.standings.find((p) => p.playerId === a)!.roundWins).toBe(round);
    expect(state.round!.reveal?.correctAnswer).toBe(answer);
    const restored = await new LiveService(database.db, () => now).view(room.code, a);
    expect(restored.round!.reveal).toEqual(state.round!.reveal);
    if (round < 5) {
      expect(state.status).toBe('running');
      expect(state.round!.results).toHaveLength(2);
      const nextAt = state.nextAt!;
      now = nextAt - 1;
      await service.tick();
      expect((await service.view(room.code, a)).round!.number).toBe(round);
      now = nextAt;
      await service.tick();
      state = await service.view(room.code, a);
      expect(state.round!.startsAt).toBeGreaterThan(now);
      // A late retry for the previous round must not score the new round.
      await service.command(room.code, a, {
        action: 'submit',
        round,
        answer,
        submissionId: randomUUID(),
      });
      expect((await service.view(room.code, a)).round!.submitted).toHaveLength(0);
    }
  }
  expect(state.status).toBe('completed');
  expect(state.standings.find((p) => p.playerId === a)!.rank).toBe(1);
  const [ra, rb] = await Promise.all([
    service.command(room.code, a, { action: 'rematch' }),
    service.command(room.code, b, { action: 'rematch' }),
  ]);
  expect(ra.rematchCode).toBe(rb.rematchCode);
  expect(ra.rematchCode).not.toBe(room.code);
  const rematch = await service.join(ra.rematchCode!, b);
  expect(rematch.roundCount).toBe(5);
  expect(rematch.status).toBe('lobby');
  expect((await service.view(room.code, a)).standings).toEqual(state.standings);
});
it('scores five eight-player rounds with tied placements, forfeits and a shared party rematch', async () => {
  const profiles = new GameService(database.db, 'http://localhost:3000', () => now);
  const ids = [a, b, c, ...Array.from({ length: 5 }, () => randomUUID())];
  for (const id of ids.slice(3)) await profiles.profile(id);
  const room = await service.create(a, { rulesVersion: 2, mode: 'party', capacity: 8 });
  await service.join(room.code, b);
  await service.watch(room.code, a, a);
  await service.watch(room.code, b, b);
  for (const id of [a, b]) await service.command(room.code, id, { action: 'ready', ready: true });
  await expect(service.command(room.code, a, { action: 'start' })).rejects.toThrow('minimum');
  await Promise.all(ids.slice(2).map((id) => service.join(room.code, id)));
  const outsider = randomUUID();
  await profiles.profile(outsider);
  await expect(service.join(room.code, outsider)).rejects.toThrow('full');
  for (const id of ids.slice(2)) {
    await service.watch(room.code, id, id);
    await service.command(room.code, id, { action: 'ready', ready: true });
  }
  let state = await service.command(room.code, a, { action: 'start' });
  await service.command(room.code, ids[7], { action: 'leave' });
  const totals = new Map(ids.map((id) => [id, 0]));
  for (let round = 1; round <= 5; round++) {
    const answer = state.round!.puzzle!.cubes.length,
      displayUntil = state.round!.displayUntil;
    for (let i = 0; i < 7; i++) {
      now = displayUntil + (round === 1 ? [100, 200, 200, 300, 400, 500, 600][i] : 100);
      state = await service.command(room.code, ids[i], {
        action: 'submit',
        round,
        answer,
        submissionId: randomUUID(),
      });
      if (i < 6) {
        expect(state.round!.reveal).toBeUndefined();
        expect(JSON.stringify(state)).not.toMatch(/correctAnswer|submittedAnswer/);
      }
    }
    expect(state.round!.results).toHaveLength(8);
    expect(state.round!.reveal?.correctAnswer).toBe(answer);
    expect(state.round!.reveal!.puzzle.cubes).toHaveLength(answer);
    const results = state.round!.results!;
    if (round === 1)
      expect(ids.map((id) => results.find((r) => r.playerId === id)!.points)).toEqual([
        7, 6, 6, 4, 3, 2, 1, 0,
      ]);
    for (const id of ids)
      totals.set(id, totals.get(id)! + results.find((r) => r.playerId === id)!.points!);
    for (const standing of state.standings)
      expect(standing.points).toBe(totals.get(standing.playerId));
    if (round < 5) {
      now = state.nextAt!;
      await service.tick();
      state = await service.view(room.code, a);
    }
  }
  expect(state.status).toBe('completed');
  expect(state.standings.find((p) => p.playerId === a)!.points).toBe(35);
  expect(state.standings.filter((p) => p.rank === 2)).toHaveLength(2);
  expect(state.standings.find((p) => p.playerId === ids[7])!.rank).toBe(8);
  const rematch = await service.command(room.code, b, { action: 'rematch' });
  const next = await service.join(rematch.rematchCode!, a);
  expect(next.mode).toBe('party');
  expect(next.capacity).toBe(8);
  expect(next.roundCount).toBe(5);
});
it('resolves concurrent final lobby slots and all-zero party ties deterministically', async () => {
  const room = await service.create(a, {
    rulesVersion: 2,
    mode: 'party',
    capacity: 3,
    roundCount: 1,
  });
  const extra = randomUUID();
  await new GameService(database.db, 'http://localhost:3000').profile(extra);
  const joins = await Promise.allSettled([b, c, extra].map((id) => service.join(room.code, id)));
  expect(joins.filter((r) => r.status === 'fulfilled')).toHaveLength(2);
  const state = await service.view(room.code, a);
  for (const player of state.players) {
    await service.watch(room.code, player.id, player.id);
    await service.command(room.code, player.id, { action: 'ready', ready: true });
  }
  const start = await service.command(room.code, a, { action: 'start' });
  now = start.round!.deadline!;
  await service.tick();
  const final = await service.view(room.code, a);
  expect(final.standings.every((s) => s.points === 2 && s.rank === 1)).toBe(true);
  expect(final.round!.results!.every((r) => r.points === 2 && r.placement === 1)).toBe(true);
});
it('supports eight independently authenticated Socket.IO guests without exposing private state', async () => {
  const { app } = await createApp({
    db: database.db,
    secret: 'b'.repeat(48),
    origin: 'http://localhost:3000',
    now: () => now,
  });
  const sockets: Socket[] = [];
  try {
    await app.listen({ host: '127.0.0.1', port: 0 });
    const base = `http://127.0.0.1:${(app.server.address() as { port: number }).port}`;
    const tokens: string[] = [];
    for (let i = 0; i < 9; i++)
      tokens.push(
        (await app.inject({ method: 'POST', url: '/api/native/session' })).headers[
          'x-brain-session'
        ] as string,
      );
    const created = await app.inject({
      method: 'POST',
      url: '/api/live/rooms',
      headers: { authorization: `Bearer ${tokens[0]}` },
      payload: { mode: 'party', capacity: 8, roundCount: 1, rulesVersion: 2 },
    });
    const code = created.json().code;
    for (let i = 0; i < 8; i++) {
      if (i)
        expect(
          (
            await app.inject({
              method: 'POST',
              url: `/api/live/rooms/${code}/join`,
              headers: { authorization: `Bearer ${tokens[i]}` },
              payload: {},
            })
          ).statusCode,
        ).toBe(200);
      const socket = client(base, {
        transports: ['websocket'],
        extraHeaders: { authorization: `Bearer ${tokens[i]}` },
        reconnection: false,
      });
      sockets.push(socket);
      await new Promise<void>((resolve, reject) => {
        socket.once('connect', resolve);
        socket.once('connect_error', reject);
      });
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
    expect(
      (
        await app.inject({
          method: 'POST',
          url: `/api/live/rooms/${code}/join`,
          headers: { authorization: `Bearer ${tokens[8]}` },
          payload: {},
        })
      ).statusCode,
    ).toBe(409);
    const started = await sockets[0].emitWithAck('room:command', {
      code,
      command: { action: 'start' },
    });
    expect(started.state.players).toHaveLength(8);
    const snapshots = await Promise.all(sockets.map((s) => s.emitWithAck('room:watch', { code })));
    expect(
      snapshots.every((s) => JSON.stringify(s.state.round) === JSON.stringify(started.state.round)),
    ).toBe(true);
    expect(JSON.stringify(started.state)).not.toMatch(/seed|"answer"|submissionId/);
    now = started.state.round.deadline;
    const finals = await Promise.all(sockets.map((s) => s.emitWithAck('room:watch', { code })));
    expect(
      finals.every(
        (s) =>
          s.state.status === 'completed' &&
          s.state.standings.every((p: { points: number }) => p.points === 7),
      ),
    ).toBe(true);
  } finally {
    for (const s of sockets) s.disconnect();
    await app.close();
  }
});
it('releases stale lobby slots after grace so a disconnected host cannot block the party', async () => {
  const extra = randomUUID();
  await new GameService(database.db, 'http://localhost:3000').profile(extra);
  const room = await service.create(a, { rulesVersion: 2, mode: 'party', capacity: 4 });
  for (const id of [a, b, c, extra]) {
    if (id !== a) await service.join(room.code, id);
    await service.watch(room.code, id, id);
    await service.command(room.code, id, { action: 'ready', ready: true });
  }
  await service.disconnect(a);
  now += 30_001;
  await service.tick();
  const resumed = await service.view(room.code, b);
  expect(resumed.players).toHaveLength(3);
  expect(resumed.hostId).toBe(b);
  const started = await service.command(room.code, b, { action: 'start' });
  expect(started.status).toBe('running');
  await expect(service.join(room.code, a)).rejects.toThrow('started');
});
it('retries room-code collisions atomically for creation and concurrent rematches', async () => {
  const sequence = ['ABC234', 'ABC234', 'DEF567', 'ABC234', 'DEF567', 'GHJ789'];
  const rooms = new LiveService(
    database.db,
    () => now,
    () => sequence.shift() ?? 'KLM234',
  );
  const original = await rooms.create(a, { rulesVersion: 2, roundCount: 1 });
  const independent = await rooms.create(c);
  expect(original.code).toBe('ABC234');
  expect(independent.code).toBe('DEF567');
  await rooms.join(original.code, b);
  for (const id of [a, b]) {
    await rooms.watch(original.code, id, id);
    await rooms.command(original.code, id, { action: 'ready', ready: true });
  }
  const start = await rooms.command(original.code, a, { action: 'start' });
  now = start.round!.deadline!;
  await rooms.tick();
  const results = await Promise.all(
    [a, b].map((id) => rooms.command(original.code, id, { action: 'rematch' })),
  );
  expect(results.map((s) => s.rematchCode)).toEqual(['GHJ789', 'GHJ789']);
  expect((await rooms.view(independent.code, c)).id).toBe(independent.id);
});
it('bounds repeated collisions and reports expired rooms without changing existing data', async () => {
  const rooms = new LiveService(
    database.db,
    () => now,
    () => 'ABC234',
  );
  const room = await rooms.create(a, { rulesVersion: 2 });
  await expect(rooms.create(b)).rejects.toMatchObject({
    statusCode: 409,
    message: 'Could not reserve a room code. Please try again.',
  });
  expect((await rooms.view(room.code, a)).players.map((p) => p.id)).toEqual([a]);
  now = room.expiresAt;
  await expect(rooms.join(room.code, b)).rejects.toMatchObject({ statusCode: 410 });
  expect((await rooms.view(room.code, a)).status).toBe('closed');
});
