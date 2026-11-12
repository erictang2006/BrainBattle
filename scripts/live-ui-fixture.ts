/** Test companion only. Talks to the existing API; never opens a database. */
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { io } from 'socket.io-client';
const base = 'http://127.0.0.1:4000';
const sockets = new Set<ReturnType<typeof io>>();
async function guest() {
  const session = await fetch(`${base}/api/native/session`, { method: 'POST' });
  const token = session.headers.get('x-brain-session');
  if (!token) throw new Error('Native session unavailable');
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}
async function fixture(party: boolean) {
  const headers = await guest(),
    target = party ? 8 : 2;
  const created = await fetch(`${base}/api/live/rooms`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ mode: party ? 'party' : 'duel', capacity: target }),
  });
  if (!created.ok) throw new Error('Could not create fixture');
  const room = (await created.json()) as { code: string };
  for (let i = 0; i < target - 1; i++) {
    const credential = i ? await guest() : headers;
    if (i) {
      const joined = await fetch(`${base}/api/live/rooms/${room.code}/join`, {
        method: 'POST',
        headers: credential,
        body: '{}',
      });
      if (!joined.ok) throw new Error('Could not join companion');
    }
    const socket = io(base, {
      transports: ['websocket'],
      extraHeaders: credential,
      reconnection: false,
    });
    sockets.add(socket);
    await new Promise<void>((resolve, reject) => {
      socket.once('connect', resolve);
      socket.once('connect_error', reject);
    });
    await socket.emitWithAck('room:watch', { code: room.code });
    let starting = false;
    const submitted = new Set<number>();
    socket.on('room:state', async (state) => {
      if (
        !i &&
        state.status === 'lobby' &&
        state.players.length === target &&
        state.players.every((p: { ready: boolean }) => p.ready) &&
        !starting
      ) {
        starting = true;
        await socket.emitWithAck('room:command', { code: room.code, command: { action: 'start' } });
      }
      if (state.status === 'running' && state.round?.puzzle && !submitted.has(state.round.number)) {
        submitted.add(state.round.number);
        const answer = state.round.puzzle.cubes.length;
        setTimeout(
          () =>
            socket.emit('room:command', {
              code: room.code,
              command: {
                action: 'submit',
                round: state.round.number,
                answer,
                submissionId: randomUUID(),
              },
            }),
          Math.max(0, state.round.displayUntil - Date.now() + 100 + i * 100),
        );
      }
      if (state.status === 'completed')
        setTimeout(() => {
          socket.disconnect();
          sockets.delete(socket);
        }, 1000);
    });
    await socket.emitWithAck('room:command', {
      code: room.code,
      command: { action: 'ready', ready: true },
    });
    setTimeout(() => {
      socket.disconnect();
      sockets.delete(socket);
    }, 180_000).unref();
  }
  return room;
}
const server = createServer(async (req, res) => {
  try {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(await fixture(req.url === '/party')));
  } catch {
    res.statusCode = 500;
    res.end('{"error":"Fixture unavailable"}');
  }
});
server.listen(4011, '127.0.0.1', () =>
  process.stdout.write('Live UI companion listening on 4011\n'),
);
process.on('SIGTERM', () => {
  for (const s of sockets) s.disconnect();
  server.close();
});
