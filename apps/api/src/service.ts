import { randomBytes, randomUUID } from 'node:crypto';
import { and, desc, eq, isNull, lte, or, sql } from 'drizzle-orm';
import { attempts, matches, profiles, rounds, type Database } from '@brain/db';
import { getGame } from '@brain/games';
import {
  DEFAULT_ROUNDS,
  GAME_ID,
  RULES_VERSION,
  type AttemptView,
  type MatchView,
  type RoundView,
} from '@brain/shared';

export class AppError extends Error {
  constructor(
    public statusCode: number,
    message: string,
  ) {
    super(message);
  }
}
type Match = typeof matches.$inferSelect;
type Attempt = typeof attempts.$inferSelect;
type Tx = Parameters<Parameters<Database['transaction']>[0]>[0];
const attemptView = (a: Attempt): AttemptView => ({
  score: a.score ?? 0,
  correct: a.correct ?? false,
  timedOut: a.timedOut ?? false,
});

export class GameService {
  constructor(
    private db: Database,
    private origin: string,
    private now = Date.now,
  ) {}
  async profile(id: string) {
    let [profile] = await this.db.select().from(profiles).where(eq(profiles.id, id));
    if (!profile) {
      await this.db
        .insert(profiles)
        .values({
          id,
          name: `Player ${randomBytes(2).toString('hex').toUpperCase()}`,
          createdAt: this.now(),
        })
        .onConflictDoNothing();
      [profile] = await this.db.select().from(profiles).where(eq(profiles.id, id));
    }
    return { id: profile.id, name: profile.name };
  }
  async rename(id: string, name: string) {
    await this.db.update(profiles).set({ name }).where(eq(profiles.id, id));
    return this.profile(id);
  }
  async list(playerId: string) {
    const rows = await this.db
      .select()
      .from(matches)
      .where(or(eq(matches.hostId, playerId), eq(matches.guestId, playerId)))
      .orderBy(desc(matches.createdAt))
      .limit(8);
    return Promise.all(
      rows.map(async (m) => {
        const otherId = m.hostId === playerId ? m.guestId : m.hostId;
        const [other] = otherId
          ? await this.db
              .select({ name: profiles.name })
              .from(profiles)
              .where(eq(profiles.id, otherId))
          : [];
        return { id: m.id, mode: m.mode, opponent: other?.name ?? null, createdAt: m.createdAt };
      }),
    );
  }
  async create(
    playerId: string,
    mode: 'solo' | 'challenge',
    rulesVersion: number = RULES_VERSION,
    roundCount: number = DEFAULT_ROUNDS,
  ) {
    if (![5, 10].includes(roundCount)) throw new AppError(400, 'Choose five or ten rounds.');
    rulesVersion = roundCount === 10 ? 4 : rulesVersion;
    const id = randomUUID();
    await this.db.transaction(async (tx) => {
      await tx.insert(matches).values({
        id,
        hostId: playerId,
        mode,
        gameId: GAME_ID,
        rulesVersion,
        inviteToken: mode === 'challenge' ? randomBytes(24).toString('hex') : null,
        createdAt: this.now(),
        expiresAt: this.now() + 48 * 60 * 60 * 1000,
      });
      await tx.insert(rounds).values(
        Array.from({ length: roundCount }, (_, i) => ({
          matchId: id,
          number: i + 1,
          seed: randomBytes(32).toString('hex'),
        })),
      );
    });
    return this.view(id, playerId);
  }
  async invitation(token: string) {
    const [match] = await this.db.select().from(matches).where(eq(matches.inviteToken, token));
    if (!match) throw new AppError(404, 'Challenge not found.');
    const [host] = await this.db.select().from(profiles).where(eq(profiles.id, match.hostId));
    return {
      hostName: host.name,
      claimed: match.guestId !== null,
      expired: this.now() >= match.expiresAt,
      rounds: (await this.db.select().from(rounds).where(eq(rounds.matchId, match.id))).length,
    };
  }
  async claim(token: string, playerId: string) {
    const id = await this.db.transaction(async (tx) => {
      const [match] = await tx
        .select()
        .from(matches)
        .where(eq(matches.inviteToken, token))
        .for('update');
      if (!match) throw new AppError(404, 'Challenge not found.');
      if (match.hostId === playerId || match.guestId === playerId) return match.id;
      if (match.expiresAt <= this.now()) throw new AppError(410, 'This challenge has expired.');
      if (match.guestId) throw new AppError(409, 'Someone has already accepted this challenge.');
      await tx.update(matches).set({ guestId: playerId }).where(eq(matches.id, match.id));
      return match.id;
    });
    return this.view(id, playerId);
  }
  private async authorized<T>(
    id: string,
    playerId: string,
    work: (tx: Tx, match: Match) => Promise<T>,
  ) {
    return this.db.transaction(async (tx) => {
      const [match] = await tx.select().from(matches).where(eq(matches.id, id)).for('update');
      if (!match || (match.hostId !== playerId && match.guestId !== playerId))
        throw new AppError(404, 'Match not found.');
      await tx
        .update(attempts)
        .set({ submittedAt: this.now(), score: 0, correct: false, timedOut: true })
        .where(
          and(
            eq(attempts.matchId, id),
            isNull(attempts.submittedAt),
            lte(attempts.deadline, this.now()),
          ),
        );
      return work(tx, match);
    });
  }
  async view(id: string, playerId: string) {
    return this.authorized(id, playerId, (tx, match) => this.project(tx, match, playerId));
  }
  async start(id: string, playerId: string, number: number) {
    return this.authorized(id, playerId, async (tx, match) => {
      const [stored] = await tx
        .select()
        .from(rounds)
        .where(and(eq(rounds.matchId, id), eq(rounds.number, number)));
      if (!stored) throw new AppError(404, 'Round not found.');
      const [existing] = await tx
        .select()
        .from(attempts)
        .where(
          and(
            eq(attempts.matchId, id),
            eq(attempts.playerId, playerId),
            eq(attempts.round, number),
          ),
        );
      // Retrying start never extends a stored clock, even after finalization.
      if (existing) return this.project(tx, match, playerId);
      if (match.expiresAt <= this.now()) throw new AppError(410, 'This match has expired.');
      if (number > 1) {
        const [previous] = await tx
          .select()
          .from(attempts)
          .where(
            and(
              eq(attempts.matchId, id),
              eq(attempts.playerId, playerId),
              eq(attempts.round, number - 1),
            ),
          );
        if (previous?.submittedAt == null)
          throw new AppError(409, 'Finish the previous round first.');
        const feedbackMs = getGame(match.gameId, match.rulesVersion).rules(number - 1).feedbackMs;
        if (this.now() < previous.submittedAt + feedbackMs)
          throw new AppError(409, 'Take a moment to see your result.');
      }
      const rules = getGame(match.gameId, match.rulesVersion).rules(number);
      const startedAt = this.now();
      const displayUntil =
        rules.answerTimeLimit === false
          ? startedAt + rules.displayMs
          : Math.min(startedAt + rules.displayMs, match.expiresAt - rules.answerMs);
      if (displayUntil <= startedAt)
        throw new AppError(410, 'There is not enough time left to start this round.');
      await tx
        .insert(attempts)
        .values({
          matchId: id,
          playerId,
          round: number,
          startedAt,
          displayUntil,
          deadline: rules.answerTimeLimit === false ? null : displayUntil + rules.answerMs,
        })
        .onConflictDoNothing();
      return this.project(tx, match, playerId);
    });
  }
  async submit(
    id: string,
    playerId: string,
    number: number,
    answer: number | null,
    submissionId: string,
  ) {
    return this.authorized(id, playerId, async (tx, match) => {
      const [attempt] = await tx
        .select()
        .from(attempts)
        .where(
          and(
            eq(attempts.matchId, id),
            eq(attempts.playerId, playerId),
            eq(attempts.round, number),
          ),
        );
      if (!attempt) throw new AppError(409, 'Start the round first.');
      if (attempt.submittedAt !== null) return this.project(tx, match, playerId);
      if (this.now() < attempt.displayUntil)
        throw new AppError(409, 'Wait until the puzzle is hidden.');
      const [used] = await tx
        .select()
        .from(attempts)
        .where(and(eq(attempts.playerId, playerId), eq(attempts.submissionId, submissionId)));
      if (used) throw new AppError(409, 'This submission ID was already used in another round.');
      const [round] = await tx
        .select()
        .from(rounds)
        .where(and(eq(rounds.matchId, id), eq(rounds.number, number)));
      const game = getGame(match.gameId, match.rulesVersion);
      const rules = game.rules(number);
      const expected = game.generate(round.seed, number).answer;
      const elapsed = this.now() - attempt.displayUntil;
      await tx
        .update(attempts)
        .set({
          answer,
          submissionId,
          submittedAt: this.now(),
          score: game.score(expected, answer, elapsed, number),
          correct:
            answer === expected && (rules.answerTimeLimit === false || elapsed < rules.answerMs),
          timedOut: rules.answerTimeLimit !== false && elapsed >= rules.answerMs,
        })
        .where(
          and(
            eq(attempts.matchId, id),
            eq(attempts.playerId, playerId),
            eq(attempts.round, number),
            isNull(attempts.submittedAt),
          ),
        );
      return this.project(tx, match, playerId);
    });
  }
  async rematch(id: string, playerId: string) {
    const old = await this.view(id, playerId);
    if (!old.yoursComplete) throw new AppError(409, 'Finish your rounds before a rematch.');
    return this.create(
      playerId,
      old.mode,
      old.rounds.length === 10 ? 4 : RULES_VERSION,
      old.rounds.length,
    );
  }
  private async project(tx: Tx, match: Match, playerId: string): Promise<MatchView> {
    const all = await tx.select().from(attempts).where(eq(attempts.matchId, match.id));
    const storedRounds = await tx.select().from(rounds).where(eq(rounds.matchId, match.id));
    const otherId = match.hostId === playerId ? match.guestId : match.hostId;
    const [you] = await tx
      .select({ id: profiles.id, name: profiles.name })
      .from(profiles)
      .where(eq(profiles.id, playerId));
    const [opponent] = otherId
      ? await tx
          .select({ id: profiles.id, name: profiles.name })
          .from(profiles)
          .where(eq(profiles.id, otherId))
      : [];
    const now = this.now();
    const roundViews: RoundView[] = [];
    for (let number = 1; number <= storedRounds.length; number++) {
      const mine = all.find((a) => a.playerId === playerId && a.round === number);
      const theirs = all.find((a) => a.playerId === otherId && a.round === number);
      const done = mine?.submittedAt != null;
      const finalized = done && (match.mode === 'solo' || theirs?.submittedAt != null);
      const state = done
        ? 'done'
        : mine
          ? now < mine.displayUntil
            ? 'display'
            : 'answer'
          : number === 1 || roundViews[number - 2].state === 'done'
            ? 'ready'
            : 'locked';
      const rules = getGame(match.gameId, match.rulesVersion).rules(number);
      const view: RoundView = { number, state, finalized, rules };
      if (done && mine?.submittedAt != null)
        view.feedbackUntil = mine.submittedAt + rules.feedbackMs;
      if (mine) {
        view.displayUntil = mine.displayUntil;
        if (mine.deadline !== null) view.deadline = mine.deadline;
      }
      if (state === 'display') {
        const [round] = await tx
          .select()
          .from(rounds)
          .where(and(eq(rounds.matchId, match.id), eq(rounds.number, number)));
        view.puzzle = getGame(match.gameId, match.rulesVersion).generate(round.seed, number).puzzle;
      }
      if (done) {
        view.attempt = attemptView(mine!);
        const [storedRound] = await tx
          .select()
          .from(rounds)
          .where(and(eq(rounds.matchId, match.id), eq(rounds.number, number)));
        const generated = getGame(match.gameId, match.rulesVersion).generate(
          storedRound.seed,
          number,
        );
        // Only this authenticated player's finalized attempt may obtain its solution.
        view.reveal = {
          puzzle: generated.puzzle,
          correctAnswer: generated.answer,
          submittedAnswer: mine!.answer ?? null,
        };
      }
      if (finalized && theirs) view.opponent = attemptView(theirs);
      roundViews.push(view);
    }
    const yoursComplete = roundViews.every((r) => r.state === 'done');
    const complete = roundViews.every((r) => r.finalized);
    const total = roundViews.reduce((sum, r) => sum + (r.attempt?.score ?? 0), 0);
    const result: MatchView = {
      id: match.id,
      mode: match.mode as MatchView['mode'],
      gameId: GAME_ID,
      rulesVersion: match.rulesVersion,
      you,
      opponent: opponent ?? null,
      rounds: roundViews,
      expiresAt: match.expiresAt,
      complete,
      yoursComplete,
      total,
      serverNow: now,
    };
    if (match.hostId === playerId && match.inviteToken)
      result.inviteUrl = `${this.origin}/invite/${match.inviteToken}`;
    if (complete && match.mode === 'challenge') {
      const opponentTotal = roundViews.reduce((sum, r) => sum + (r.opponent?.score ?? 0), 0);
      result.opponentTotal = opponentTotal;
      result.winner =
        total === opponentTotal ? 'draw' : total > opponentTotal ? playerId : otherId!;
    }
    return result;
  }
}
