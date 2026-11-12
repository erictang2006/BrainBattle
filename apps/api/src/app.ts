import Fastify, { type FastifyReply, type FastifyRequest } from 'fastify';
import cookie from '@fastify/cookie';
import rateLimit from '@fastify/rate-limit';
import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';
import { Server } from 'socket.io';
import { z } from 'zod';
import { type Database } from '@brain/db';
import {
  attemptInput,
  createMatchInput,
  inviteInput,
  matchIdInput,
  profileInput,
  roundInput,
  type ClientToServerEvents,
  type ServerToClientEvents,
} from '@brain/shared';
import { AppError, GameService } from './service.js';
import { LiveService } from './live-service.js';
import { liveCode, liveCommand, createLiveInput } from '@brain/shared/live';
import type { LiveAck } from '@brain/shared';

type Options = {
  db: Database;
  secret: string;
  origin: string;
  production?: boolean;
  supabaseUrl?: string;
  supabaseKey?: string;
  now?: () => number;
  logger?: boolean;
};
type Session = {
  localId?: string;
  access?: string;
  refresh?: string;
  transport?: 'native';
  expiresAt?: number;
};
export async function createApp(options: Options) {
  if (options.secret.length < 32)
    throw new Error('SESSION_SECRET must contain at least 32 characters.');
  if (!!options.supabaseUrl !== !!options.supabaseKey)
    throw new Error('Configure both SUPABASE_URL and SUPABASE_ANON_KEY.');
  if (
    options.production &&
    (!options.supabaseUrl || options.secret.startsWith('local-development'))
  )
    throw new Error('Production requires Supabase Auth and a unique SESSION_SECRET.');
  const app = Fastify({ logger: options.logger ?? false, bodyLimit: 8192 });
  const service = new GameService(options.db, options.origin, options.now);
  const live = new LiveService(options.db, options.now);
  await app.register(cookie, { secret: options.secret });
  await app.register(rateLimit, { max: 180, timeWindow: '1 minute' });
  const authClient = () =>
    createClient(options.supabaseUrl!, options.supabaseKey!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  const isNative = (req: FastifyRequest) =>
    req.headers.authorization !== undefined || req.routeOptions?.url === '/api/native/session';
  const writeSession = (req: FastifyRequest, reply: FastifyReply, session: Session) => {
    if (isNative(req)) {
      const credential = {
        ...session,
        transport: 'native',
        expiresAt: (options.now ?? Date.now)() + 30 * 24 * 60 * 60 * 1000,
      };
      reply.header('X-Brain-Session', app.signCookie(JSON.stringify(credential)));
      return;
    }
    reply.setCookie('bb-session', JSON.stringify(session), {
      path: '/',
      httpOnly: true,
      secure: options.production ?? false,
      sameSite: 'lax',
      signed: true,
      maxAge: 60 * 60 * 24 * 30,
    });
  };
  const readSession = (req: FastifyRequest) => {
    const native = isNative(req);
    const authorization = req.headers.authorization;
    if (native && authorization && !authorization.startsWith('Bearer ')) return null;
    const value = native ? authorization?.slice(7) : req.cookies['bb-session'];
    if (!value) return null;
    const unsigned = req.unsignCookie(value);
    if (!unsigned.valid || !unsigned.value) return null;
    try {
      const session = JSON.parse(unsigned.value) as Session;
      if (
        native &&
        (session.transport !== 'native' ||
          !session.expiresAt ||
          session.expiresAt <= (options.now ?? Date.now)())
      )
        return null;
      if (!native && session.transport === 'native') return null;
      return session;
    } catch {
      return null;
    }
  };
  async function identify(
    req: FastifyRequest,
    reply?: FastifyReply,
    create = false,
  ): Promise<string> {
    const session = readSession(req);
    if (req.headers.authorization && !session)
      throw new AppError(401, 'Your native session is invalid or expired.');
    if (options.supabaseUrl) {
      const supabase = authClient();
      if (session?.access) {
        const { data } = await supabase.auth.getUser(session.access);
        if (data.user) return data.user.id;
        if (session.refresh && reply) {
          const { data: refreshed } = await supabase.auth.refreshSession({
            refresh_token: session.refresh,
          });
          if (refreshed.session && refreshed.user) {
            writeSession(req, reply, {
              access: refreshed.session.access_token,
              refresh: refreshed.session.refresh_token,
            });
            return refreshed.user.id;
          }
        }
        // Preserve the existing identity when the provider is unavailable. A transient
        // refresh failure must not replace an established guest with a new account.
        throw new AppError(401, 'Could not restore your guest session. Please retry.');
      }
      if (create && reply) {
        const { data, error } = await supabase.auth.signInAnonymously();
        if (error || !data.user || !data.session)
          throw new AppError(
            503,
            'Guest sign-in is unavailable. Check Supabase anonymous sign-ins.',
          );
        writeSession(req, reply, {
          access: data.session.access_token,
          refresh: data.session.refresh_token,
        });
        return data.user.id;
      }
    } else {
      if (session?.localId && z.uuid().safeParse(session.localId).success) return session.localId;
      if (create && reply) {
        const id = randomUUID();
        writeSession(req, reply, { localId: id });
        return id;
      }
    }
    throw new AppError(401, 'Your guest session has expired. Return home to sign in again.');
  }
  app.addHook('onRequest', async (req, reply) => {
    reply.header('Cache-Control', 'no-store');
    reply.header('X-Content-Type-Options', 'nosniff');
    if (
      !['GET', 'HEAD', 'OPTIONS'].includes(req.method) &&
      req.headers.origin &&
      req.headers.origin !== options.origin
    )
      throw new AppError(403, 'Origin is not allowed.');
  });
  app.setErrorHandler((error, _req, reply) => {
    if (error instanceof z.ZodError)
      return reply
        .code(400)
        .send({ error: 'Invalid request.', details: error.issues.map((i) => i.message) });
    const typed = error as { statusCode?: number; message?: string };
    const cause = error as { code?: string; cause?: { code?: string } };
    if (cause.code === '23505' || cause.cause?.code === '23505')
      return reply.code(409).send({ error: 'This submission ID has already been used.' });
    const status = typeof typed.statusCode === 'number' ? typed.statusCode : 500;
    if (status >= 500) app.log.error(error);
    return reply.code(status).send({
      error: status >= 500 ? 'The server could not complete this request.' : typed.message,
    });
  });
  const io = new Server<ClientToServerEvents, ServerToClientEvents>(app.server, {
    path: '/socket.io',
    addTrailingSlash: false,
    serveClient: false,
    cors: { origin: options.origin, credentials: true },
    allowRequest: (req, done) =>
      done(null, !req.headers.origin || req.headers.origin === options.origin),
  });
  const changed = (matchId: string) => io.to(matchId).emit('match:changed', { matchId });
  io.use(async (socket, next) => {
    try {
      const raw = socket.request.headers.cookie;
      const cookies = app.parseCookie(raw ?? '');
      const identity = await identify({
        cookies,
        headers: { authorization: socket.request.headers.authorization },
        unsignCookie: app.unsignCookie,
      } as unknown as FastifyRequest);
      socket.data.playerId = identity;
      next();
    } catch {
      next(new Error('Authentication required'));
    }
  });
  live.onChanged = (state) => {
    const room = `live:${state.code}`;
    for (const socketId of io.sockets.adapter.rooms.get(room) ?? []) {
      const client = io.sockets.sockets.get(socketId);
      if (client && !state.players.some((p) => p.id === client.data.playerId))
        void client.leave(room);
    }
    io.to(room).emit('room:state', state);
  };
  // One scheduler per API process. State and original deadlines survive process restarts.
  let ticking = false;
  const ticker = setInterval(async () => {
    if (ticking) return;
    ticking = true;
    try {
      await live.tick();
    } catch (error) {
      app.log.error(error);
    } finally {
      ticking = false;
    }
  }, 500);
  ticker.unref();
  app.addHook('onClose', async () => {
    clearInterval(ticker);
  });
  io.on('connection', (socket) => {
    let budget = 0,
      windowAt = Date.now();
    const handle = async (
      ack: ((result: LiveAck) => void) | undefined,
      action: () => Promise<LiveAck>,
    ) => {
      try {
        if (Date.now() - windowAt > 60_000) {
          budget = 0;
          windowAt = Date.now();
        }
        if (++budget > 120) throw new AppError(429, 'Too many room events.');
        // Revalidate credentials on every privileged event, not just the handshake.
        await identify({
          cookies: app.parseCookie(socket.request.headers.cookie ?? ''),
          headers: { authorization: socket.request.headers.authorization },
          unsignCookie: app.unsignCookie,
        } as unknown as FastifyRequest);
        const result = await action();
        if (typeof ack === 'function') ack(result);
      } catch (error) {
        const message =
          error instanceof z.ZodError
            ? 'Invalid room event.'
            : error instanceof AppError
              ? error.message
              : 'Could not update this room.';
        if (typeof ack === 'function')
          ack({
            ok: false,
            error: message,
            status:
              error instanceof AppError
                ? error.statusCode
                : error instanceof z.ZodError
                  ? 400
                  : 500,
          });
      }
    };
    socket.on(
      'room:watch',
      (payload, ack) =>
        void handle(ack, async () => {
          const { code } = z.object({ code: liveCode }).strict().parse(payload);
          const state = await live.watch(code, socket.data.playerId, socket.id);
          await socket.join(`live:${code}`);
          return { ok: true, state };
        }),
    );
    socket.on(
      'room:command',
      (payload, ack) =>
        void handle(ack, async () => {
          const { code, command } = z
            .object({ code: liveCode, command: liveCommand })
            .strict()
            .parse(payload);
          return { ok: true, state: await live.command(code, socket.data.playerId, command) };
        }),
    );
    socket.on(
      'clock:sync',
      (payload, ack) =>
        void handle(ack, async () => {
          z.object({}).strict().parse(payload);
          return { ok: true, serverNow: (options.now ?? Date.now)() };
        }),
    );
    socket.on('disconnect', () => {
      void live.disconnect(socket.id).catch((error) => app.log.error(error));
    });
    socket.on('match:watch', async (payload, ack) => {
      try {
        const { matchId } = z.object({ matchId: matchIdInput }).strict().parse(payload);
        await service.view(matchId, socket.data.playerId);
        await socket.join(matchId);
        if (typeof ack === 'function') ack({ ok: true });
      } catch {
        if (typeof ack === 'function') ack({ ok: false });
      }
    });
  });
  app.addHook('preClose', async () => {
    await new Promise<void>((resolve) => io.close(() => resolve()));
  });
  app.post('/api/live/rooms', async (req, reply) => {
    const input = createLiveInput.parse(req.body ?? {});
    return live.create(await identify(req, reply), input);
  });
  app.post<{ Params: { code: string } }>('/api/live/rooms/:code/join', async (req, reply) => {
    z.object({})
      .strict()
      .parse(req.body ?? {});
    return live.join(liveCode.parse(req.params.code), await identify(req, reply));
  });
  app.get<{ Params: { code: string } }>('/api/live/rooms/:code', async (req, reply) =>
    live.view(liveCode.parse(req.params.code), await identify(req, reply)),
  );
  app.get('/api/health', async () => ({
    ok: true,
    auth: options.supabaseUrl ? 'supabase' : 'local-development',
  }));
  app.post(
    '/api/session',
    { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } },
    async (req, reply) => service.profile(await identify(req, reply, true)),
  );
  // Native clients retain this signed credential in Keychain and send Bearer auth.
  // Existing web clients continue to use the unchanged HttpOnly cookie contract.
  app.post(
    '/api/native/session',
    { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } },
    async (req, reply) => service.profile(await identify(req, reply, true)),
  );
  app.patch('/api/profile', async (req, reply) => {
    const id = await identify(req, reply);
    const input = profileInput.parse(req.body);
    return service.rename(id, input.name);
  });
  app.get('/api/matches', async (req, reply) => service.list(await identify(req, reply)));
  app.post('/api/matches', async (req, reply) => {
    const id = await identify(req, reply);
    const input = createMatchInput.parse(req.body);
    return service.create(id, input.mode);
  });
  app.get<{ Params: { id: string } }>('/api/matches/:id', async (req, reply) =>
    service.view(matchIdInput.parse(req.params.id), await identify(req, reply)),
  );
  app.post<{ Params: { id: string; round: string } }>(
    '/api/matches/:id/rounds/:round/start',
    async (req, reply) => {
      const result = await service.start(
        matchIdInput.parse(req.params.id),
        await identify(req, reply),
        roundInput.parse(req.params.round),
      );
      changed(result.id);
      return result;
    },
  );
  app.post<{ Params: { id: string; round: string } }>(
    '/api/matches/:id/rounds/:round/attempt',
    async (req, reply) => {
      const input = attemptInput.parse(req.body);
      const result = await service.submit(
        matchIdInput.parse(req.params.id),
        await identify(req, reply),
        roundInput.parse(req.params.round),
        input.answer,
        input.submissionId,
      );
      changed(result.id);
      return result;
    },
  );
  app.post<{ Params: { id: string } }>('/api/matches/:id/rematch', async (req, reply) =>
    service.rematch(matchIdInput.parse(req.params.id), await identify(req, reply)),
  );
  app.get<{ Params: { token: string } }>('/api/invitations/:token', async (req) =>
    service.invitation(inviteInput.parse(req.params.token)),
  );
  app.post<{ Params: { token: string } }>('/api/invitations/:token/claim', async (req, reply) => {
    const result = await service.claim(
      inviteInput.parse(req.params.token),
      await identify(req, reply),
    );
    changed(result.id);
    return result;
  });
  return { app, service, live, io };
}
