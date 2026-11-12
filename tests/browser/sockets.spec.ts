import { expect, test } from '@playwright/test';
import { io, type Socket } from 'socket.io-client';
import type { MatchView } from '@brain/shared';
test('Socket.IO authenticates guests, authorizes subscriptions and only sends invalidations', async ({
  browser,
}) => {
  const context = await browser.newContext();
  const sockets: Socket[] = [];
  try {
    await context.request.post('http://localhost:3000/api/session');
    const match = (await (
      await context.request.post('http://localhost:3000/api/matches', { data: { mode: 'solo' } })
    ).json()) as MatchView;
    const cookies = await context.cookies();
    const cookie = cookies.map((c) => `${c.name}=${c.value}`).join('; ');
    const connect = (authenticated: boolean) =>
      io('http://localhost:3000', {
        path: '/socket.io',
        addTrailingSlash: false,
        transports: ['polling'],
        upgrade: false,
        reconnection: false,
        extraHeaders: authenticated ? { Cookie: cookie } : undefined,
      });
    const unauth = connect(false);
    sockets.push(unauth);
    await expect(
      new Promise<string>((resolve) => unauth.on('connect_error', (e) => resolve(e.message))),
    ).resolves.toBe('Authentication required');
    const socket = connect(true);
    sockets.push(socket);
    await new Promise<void>((resolve, reject) => {
      socket.on('connect', () => resolve());
      socket.on('connect_error', reject);
    });
    const watch = (matchId: string) =>
      new Promise<{ ok: boolean }>((resolve, reject) =>
        socket
          .timeout(4000)
          .emit('match:watch', { matchId }, (error: Error | null, ack: { ok: boolean }) =>
            error ? reject(error) : resolve(ack),
          ),
      );
    expect(await watch(crypto.randomUUID())).toEqual({ ok: false });
    expect(await watch(match.id)).toEqual({ ok: true });
    const notification = new Promise<unknown>((resolve) => socket.once('match:changed', resolve));
    await context.request.post(`http://localhost:3000/api/matches/${match.id}/rounds/1/start`);
    expect(await notification).toEqual({ matchId: match.id });
  } finally {
    for (const socket of sockets) socket.disconnect();
    await context.close();
  }
});
