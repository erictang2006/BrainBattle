import { randomBytes, randomUUID } from 'node:crypto';
import { eq, sql } from 'drizzle-orm';
import { liveRooms, profiles, type Database } from '@brain/db';
import {
  GAME_ID,
  RULES_VERSION,
  type LiveCommand,
  type LiveSnapshot,
  type LiveResult,
} from '@brain/shared';
import { getGame } from '@brain/games';
import { AppError } from './service.js';

type Player = { id: string; name: string; ready: boolean; forfeited: boolean };
type StoredResult = LiveResult & { submissionId: string | null };
type Transaction = Parameters<Parameters<Database['transaction']>[0]>[0];
type History = { number: number; results: StoredResult[] };
type State = {
  version: 1;
  id: string;
  code: string;
  revision: number;
  rulesVersion: number;
  status: LiveSnapshot['status'];
  hostId: string;
  players: Player[];
  expiresAt: number;
  mode?: 'duel' | 'party';
  capacity?: number;
  roundCount?: number;
  history?: History[];
  nextAt?: number;
  rematchCode?: string;
  round?: {
    number?: number;
    seed: string;
    startsAt: number;
    displayUntil: number;
    deadline: number;
    results: StoredResult[];
  };
};
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
/** One locked aggregate per room; never serialize this private state to a client. */
export class LiveService {
  private presence = new Map<string, Map<string, Set<string>>>();
  private offlineSince = new Map<string, number>();
  onChanged: (state: LiveSnapshot) => void = () => {};
  constructor(
    private db: Database,
    private now: () => number = Date.now,
    private codeFactory: () => string = () =>
      [...randomBytes(6)].map((b) => alphabet[b % alphabet.length]).join(''),
  ) {}
  async create(
    playerId: string,
    input: { roundCount?: number; mode?: 'duel' | 'party'; capacity?: number } = {},
  ) {
    const [profile] = await this.db.select().from(profiles).where(eq(profiles.id, playerId));
    if (!profile) throw new AppError(401, 'Restore your guest profile first.');
    const state = await this.insertRoom(
      this.db,
      profile,
      input.roundCount ?? 5,
      input.mode ?? 'duel',
      input.capacity ?? (input.mode === 'party' ? 8 : 2),
    );
    return this.publicState(state);
  }
  private async insertRoom(
    db: Database | Transaction,
    profile: { id: string; name: string },
    roundCount: number,
    mode: 'duel' | 'party',
    capacity: number,
  ) {
    for (let attempt = 0; attempt < 8; attempt++) {
      const state = this.newRoom(profile, roundCount, mode, capacity);
      // ON CONFLICT keeps a rematch transaction usable after a code collision.
      const inserted = await db
        .insert(liveRooms)
        .values({ id: state.id, code: state.code, state, updatedAt: this.now() })
        .onConflictDoNothing({ target: liveRooms.code })
        .returning({ id: liveRooms.id });
      if (inserted.length) return state;
    }
    throw new AppError(409, 'Could not reserve a room code. Please try again.');
  }
  private newRoom(
    profile: { id: string; name: string },
    roundCount: number,
    mode: 'duel' | 'party' = 'duel',
    capacity = 2,
  ): State {
    const code = this.codeFactory();
    return {
      version: 1,
      id: randomUUID(),
      code,
      revision: 0,
      rulesVersion: RULES_VERSION,
      roundCount,
      mode,
      capacity,
      status: 'lobby',
      hostId: profile.id,
      players: [{ id: profile.id, name: profile.name, ready: false, forfeited: false }],
      expiresAt: this.now() + 2 * 60 * 60 * 1000,
      history: [],
    };
  }
  private startRound(state: State, number: number) {
    const rules = getGame(GAME_ID, state.rulesVersion).rules(number);
    const startsAt = this.now() + 4000;
    state.round = {
      number,
      seed: randomBytes(32).toString('hex'),
      startsAt,
      displayUntil: startsAt + rules.displayMs,
      deadline: startsAt + rules.displayMs + rules.answerMs,
      results: state.players
        .filter((p) => p.forfeited)
        .map((p) => ({
          playerId: p.id,
          score: 0,
          correct: false,
          timedOut: false,
          forfeited: true,
          submissionId: null,
        })),
    };
    delete state.nextAt;
  }
  private winners(results: StoredResult[]) {
    const eligible = results.filter((r) => !r.forfeited);
    const best = Math.max(...eligible.map((r) => r.score));
    return eligible.filter((r) => r.score === best).map((r) => r.playerId);
  }
  private placement(state: State, results: StoredResult[], id: string) {
    const result = results.find((r) => r.playerId === id);
    if (!result || result.forfeited) return { placement: state.players.length, points: 0 };
    const placement = 1 + results.filter((r) => !r.forfeited && r.score > result.score).length;
    const winners = this.winners(results);
    return {
      placement,
      points:
        state.mode === 'party'
          ? state.players.length - placement
          : winners.length === 1 && winners[0] === id
            ? 1
            : 0,
    };
  }
  private member(state: State, id: string) {
    const player = state.players.find((p) => p.id === id);
    if (!player) throw new AppError(403, 'You are not a member of this room.');
    return player;
  }
  private connected(code: string, id: string) {
    return !!this.presence.get(code)?.get(id)?.size;
  }
  private advance(state: State) {
    const now = this.now();
    if (state.status === 'lobby' && now >= state.expiresAt) state.status = 'closed';
    if (state.status === 'lobby') {
      for (const player of state.players) {
        const key = `${state.code}:${player.id}`;
        if (this.connected(state.code, player.id)) this.offlineSince.delete(key);
        else if (!this.offlineSince.has(key)) this.offlineSince.set(key, now);
      }
      if (state.players.some((p) => this.connected(state.code, p.id))) {
        state.players = state.players.filter(
          (p) =>
            this.connected(state.code, p.id) ||
            now - (this.offlineSince.get(`${state.code}:${p.id}`) ?? now) < 30_000,
        );
        if (!state.players.some((p) => p.id === state.hostId)) state.hostId = state.players[0].id;
      }
    }
    if (state.status === 'lobby' && !this.connected(state.code, state.hostId)) {
      const key = `${state.code}:${state.hostId}`;
      if (!this.offlineSince.has(key)) this.offlineSince.set(key, now);
      if (now - this.offlineSince.get(key)! >= 20_000) {
        const next = state.players.find((p) => this.connected(state.code, p.id));
        if (next) state.hostId = next.id;
      }
    }
    if (state.status !== 'running' || !state.round) return;
    if (state.nextAt && now >= state.nextAt)
      this.startRound(state, (state.history?.length ?? 0) + 1);
    const round = state.round;
    if (now >= round.deadline)
      for (const p of state.players) {
        if (!round.results.some((r) => r.playerId === p.id))
          round.results.push({
            playerId: p.id,
            score: 0,
            correct: false,
            timedOut: true,
            forfeited: p.forfeited,
            submissionId: null,
          });
      }
    if (
      round.results.length === state.players.length &&
      !state.history?.some((h) => h.number === (round.number ?? 1))
    ) {
      (state.history ??= []).push({ number: round.number ?? 1, results: round.results });
      if (state.history.length >= (state.roundCount ?? 1)) state.status = 'completed';
      else state.nextAt = now + 4000;
    }
  }
  private async mutate(
    code: string,
    operation: (state: State, tx: Transaction) => Promise<void> | void,
    quiet = false,
  ) {
    let changed = false;
    const snapshot = await this.db.transaction(async (tx) => {
      const [row] = await tx.select().from(liveRooms).where(eq(liveRooms.code, code)).for('update');
      if (!row) throw new AppError(404, 'Room not found.');
      const state = row.state as State;
      const before = JSON.stringify(state);
      this.advance(state);
      await operation(state, tx);
      this.advance(state);
      if (JSON.stringify(state) !== before) {
        changed = true;
        state.revision++;
        await tx
          .update(liveRooms)
          .set({ state, updatedAt: this.now() })
          .where(eq(liveRooms.id, row.id));
      }
      return this.publicState(state);
    });
    if (!quiet || changed) this.onChanged(snapshot);
    return snapshot;
  }
  async view(code: string, playerId: string) {
    return this.mutate(code, (state) => {
      this.member(state, playerId);
    });
  }
  async join(code: string, playerId: string) {
    const [profile] = await this.db.select().from(profiles).where(eq(profiles.id, playerId));
    if (!profile) throw new AppError(401, 'Restore your guest profile first.');
    return this.mutate(code, (state) => {
      if (state.players.some((p) => p.id === playerId)) return;
      if (state.status === 'closed')
        throw new AppError(410, 'This room has expired or closed. Ask for a new code.');
      if (state.status !== 'lobby')
        throw new AppError(409, 'This room has already started. Ask for a new room code.');
      if (state.players.length >= (state.capacity ?? 2))
        throw new AppError(409, 'This room is full.');
      state.players.push({ id: profile.id, name: profile.name, ready: false, forfeited: false });
    });
  }
  async command(code: string, id: string, command: LiveCommand) {
    return this.mutate(code, async (state, tx) => {
      const player = this.member(state, id);
      const now = this.now();
      if (command.action === 'rematch') {
        if (state.status !== 'completed')
          throw new AppError(409, 'Finish this match before a rematch.');
        if (!state.rematchCode) {
          const next = await this.insertRoom(
            tx,
            player,
            state.roundCount ?? 1,
            state.mode ?? 'duel',
            state.capacity ?? 2,
          );
          state.rematchCode = next.code;
        }
        return;
      }
      if (command.action === 'leave') {
        if (state.status === 'lobby') {
          state.players = state.players.filter((p) => p.id !== id);
          if (!state.players.length) state.status = 'closed';
          else if (state.hostId === id) state.hostId = state.players[0].id;
        } else if (state.status === 'running') {
          player.forfeited = true;
          if (!state.round!.results.some((r) => r.playerId === id))
            state.round!.results.push({
              playerId: id,
              score: 0,
              correct: false,
              timedOut: false,
              forfeited: true,
              submissionId: null,
            });
        }
        return;
      }
      if (command.action === 'submit') {
        const round = state.round;
        if (!round) throw new AppError(409, 'The round has not started.');
        if (command.round < (round.number ?? 1)) return;
        if (command.round !== (round.number ?? 1))
          throw new AppError(409, 'This is not the active round.');
        // A finalized attempt is immutable, including when retried with another UUID.
        if (round.results.some((r) => r.playerId === id)) return;
        if (state.status !== 'running' || now >= round.deadline) return;
        if (now < round.displayUntil)
          throw new AppError(409, 'Wait until the answer window opens.');
        const engine = getGame(GAME_ID, state.rulesVersion);
        const { answer } = engine.generate(round.seed, round.number ?? 1);
        round.results.push({
          playerId: id,
          submissionId: command.submissionId,
          score: engine.score(answer, command.answer, now - round.displayUntil, round.number ?? 1),
          correct: answer === command.answer,
          timedOut: false,
          forfeited: false,
        });
        return;
      }
      if (state.status !== 'lobby') throw new AppError(409, 'This lobby is no longer open.');
      if (command.action === 'ready') {
        player.ready = command.ready;
        return;
      }
      if (state.hostId !== id) throw new AppError(403, 'Only the host can start.');
      if (
        state.players.length < (state.mode === 'party' ? 3 : 2) ||
        state.players.length > (state.capacity ?? 2) ||
        state.players.some((p) => !p.ready || !this.connected(code, p.id))
      )
        throw new AppError(
          409,
          'The minimum player count must be met and all players must be connected and ready.',
        );
      this.startRound(state, 1);
      state.status = 'running';
    });
  }
  async watch(code: string, playerId: string, socketId: string) {
    await this.view(code, playerId);
    let room = this.presence.get(code);
    if (!room) {
      room = new Map();
      this.presence.set(code, room);
    }
    let sockets = room.get(playerId);
    if (!sockets) {
      sockets = new Set();
      room.set(playerId, sockets);
    }
    sockets.add(socketId);
    this.offlineSince.delete(`${code}:${playerId}`);
    return this.view(code, playerId);
  }
  async disconnect(socketId: string) {
    for (const [code, players] of this.presence)
      for (const [id, sockets] of players) {
        if (sockets.delete(socketId) && !sockets.size) {
          this.offlineSince.set(`${code}:${id}`, this.now());
          await this.mutate(code, () => {});
        }
      }
  }
  async tick() {
    const rows = await this.db
      .select({ code: liveRooms.code })
      .from(liveRooms)
      .where(sql`${liveRooms.state}->>'status' IN ('lobby', 'running')`);
    for (const row of rows) await this.mutate(row.code, () => {}, true);
  }
  private publicState(state: State): LiveSnapshot {
    const now = this.now();
    const snapshot: LiveSnapshot = {
      id: state.id,
      code: state.code,
      revision: state.revision,
      rulesVersion: state.rulesVersion,
      status: state.status,
      hostId: state.hostId,
      mode: state.mode ?? 'duel',
      capacity: state.capacity ?? 2,
      roundCount: state.roundCount ?? 1,
      expiresAt: state.expiresAt,
      serverNow: now,
      rematchCode: state.rematchCode,
      nextAt: state.nextAt,
      lineup: Array.from({ length: state.roundCount ?? 1 }, (_, i) => ({
        number: i + 1,
        gameId: GAME_ID,
        rules: getGame(GAME_ID, state.rulesVersion).rules(i + 1),
      })),
      standings: state.players.map((p) => {
        const history =
          state.history ??
          (state.round && state.status === 'completed'
            ? [{ number: state.round.number ?? 1, results: state.round.results }]
            : []);
        const roundWins = history.filter((h) => {
          const winners = this.winners(h.results);
          return winners.length === 1 && winners[0] === p.id;
        }).length;
        return {
          playerId: p.id,
          points:
            state.mode === 'party'
              ? history.reduce((sum, h) => sum + this.placement(state, h.results, p.id).points, 0)
              : roundWins,
          roundWins,
          totalScore: history.reduce(
            (sum, h) => sum + (h.results.find((r) => r.playerId === p.id)?.score ?? 0),
            0,
          ),
          rank: 0,
        };
      }),
      players: state.players.map((p) => ({
        id: p.id,
        name: p.name,
        ready: p.ready,
        forfeited: p.forfeited,
        connected: this.connected(state.code, p.id),
      })),
    };
    for (const standing of snapshot.standings) {
      const forfeited = state.players.find((p) => p.id === standing.playerId)!.forfeited;
      standing.rank = forfeited
        ? state.players.length
        : 1 +
          snapshot.standings.filter(
            (s) =>
              !state.players.find((p) => p.id === s.playerId)!.forfeited &&
              s.points > standing.points,
          ).length;
    }
    if (state.round) {
      const round = state.round;
      snapshot.round = {
        number: round.number ?? 1,
        startsAt: round.startsAt,
        displayUntil: round.displayUntil,
        deadline: round.deadline,
        rules: getGame(GAME_ID, state.rulesVersion).rules(round.number ?? 1),
        submitted: round.results.map((r) => r.playerId),
      };
      // Prewarm public geometry for a scheduled future display; private generation material stays server-only.
      if (state.status === 'running' && now < round.displayUntil)
        snapshot.round.puzzle = getGame(GAME_ID, state.rulesVersion).generate(
          round.seed,
          round.number ?? 1,
        ).puzzle;
      if (round.results.length === state.players.length) {
        snapshot.round.results = round.results.map(({ submissionId: _, ...result }) => ({
          ...result,
          ...this.placement(state, round.results, result.playerId),
        }));
        snapshot.round.winners = this.winners(round.results);
      }
    }
    return snapshot;
  }
}
