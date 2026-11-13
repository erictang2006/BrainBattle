'use client';
import { useEffect, useRef, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { io, type Socket } from 'socket.io-client';
import {
  ArrowLeft,
  ArrowRight,
  Box,
  Check,
  Clock3,
  Copy,
  Link2,
  LoaderCircle,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  Trophy,
  X,
} from 'lucide-react';
import type { MatchView, RoundView } from '@brain/shared';
import { ANSWER_MS, DISPLAY_MS } from '@brain/shared';
import { api, ensureSession } from '../../../lib/api';
import { Header, Footer } from '../../../components/shell';
import { gameRenderers } from '../../../components/game-stage';

export default function MatchPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [match, setMatch] = useState<MatchView | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [answer, setAnswer] = useState('0');
  const [typeAnswer, setTypeAnswer] = useState(false);
  const [focused, setFocused] = useState<number | null>(null);
  const [now, setNow] = useState(Date.now());
  const offset = useRef(0);
  const [copied, setCopied] = useState(false);
  const [copyError, setCopyError] = useState('');
  const requestVersion = useRef(0);
  const submissionIds = useRef<Record<number, string>>({});
  const accept = (data: MatchView) => {
    offset.current = data.serverNow - Date.now();
    setNow(data.serverNow);
    setMatch(data);
    setError('');
  };
  async function refresh() {
    const version = ++requestVersion.current;
    try {
      const data = await api<MatchView>(`/matches/${id}`);
      if (version === requestVersion.current) accept(data);
    } catch (e) {
      if (version === requestVersion.current) setError((e as Error).message);
    }
  }
  useEffect(() => {
    let alive = true;
    let socket: Socket | undefined;
    void ensureSession()
      .then(() => {
        if (!alive) return;
        void refresh();
        socket = io({
          path: '/socket.io',
          addTrailingSlash: false,
          transports: ['polling'],
          upgrade: false,
        });
        socket.on('connect', () => socket?.emit('match:watch', { matchId: id }));
        socket.on('match:changed', () => {
          void refresh();
        });
      })
      .catch((e) => setError(e.message));
    const timer = setInterval(() => setNow(Date.now() + offset.current), 100);
    const poll = setInterval(() => {
      if (alive && document.visibilityState === 'visible') void refresh();
    }, 2500);
    const visible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    document.addEventListener('visibilitychange', visible);
    return () => {
      alive = false;
      socket?.disconnect();
      clearInterval(timer);
      clearInterval(poll);
      document.removeEventListener('visibilitychange', visible);
    };
  }, [id]);
  const currentNumber = focused ?? match?.rounds.find((r) => r.state !== 'done')?.number ?? 5;
  const round = match?.rounds[currentNumber - 1];
  const phase =
    round?.state === 'display' && now >= (round.displayUntil ?? Infinity) ? 'answer' : round?.state;
  const expired = !!match && now >= match.expiresAt;
  const draftKey = match ? `brain.countDraft.${match.you.id}.${id}.${currentNumber}` : null;
  useEffect(() => {
    if (!draftKey) return;
    try {
      const saved = localStorage.getItem(draftKey);
      setAnswer(saved !== null && /^\d{1,3}$/.test(saved) && Number(saved) <= 100 ? saved : '0');
    } catch {
      setAnswer('0');
    }
  }, [draftKey]);
  const changeAnswer = (value: string) => {
    if (!/^\d{0,3}$/.test(value) || Number(value) > 100) return;
    setAnswer(value);
    if (draftKey)
      try {
        localStorage.setItem(draftKey, value);
      } catch {
        /* input still works */
      }
  };

  async function act(path: string, body?: unknown) {
    if (busy) return;
    setBusy(true);
    ++requestVersion.current;
    try {
      const data = await api<MatchView>(path, 'POST', body);
      ++requestVersion.current;
      accept(data);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const start = () => {
    setFocused(currentNumber);
    changeAnswer('0');
    void act(`/matches/${id}/rounds/${currentNumber}/start`);
  };
  const submit = (value: number | null) => {
    setFocused(currentNumber);
    submissionIds.current[currentNumber] ??= crypto.randomUUID();
    void act(`/matches/${id}/rounds/${currentNumber}/attempt`, {
      answer: value,
      submissionId: submissionIds.current[currentNumber],
    });
  };
  useEffect(() => {
    if (round?.deadline && phase !== 'done' && now >= round.deadline && !busy) void refresh();
  }, [phase, round?.deadline, Math.floor(now / 1000)]);
  async function copy() {
    if (!match?.inviteUrl) return;
    try {
      await navigator.clipboard.writeText(match.inviteUrl);
      setCopied(true);
      setCopyError('');
      setTimeout(() => setCopied(false), 2500);
    } catch {
      setCopyError('Select and copy the link below.');
    }
  }
  if (!match)
    return (
      <>
        <Header />
        <main className="match-main">
          <Link href="/" className="back-link">
            <ArrowLeft size={16} /> Back to the playground
          </Link>
          <div className="loading-panel">
            {error ? (
              <>
                <p role="alert">{error}</p>
                <button className="button button-dark" onClick={refresh}>
                  Try again
                </button>
              </>
            ) : (
              <>
                <LoaderCircle className="spin" /> Finding your battle…
              </>
            )}
          </div>
        </main>
      </>
    );
  const Stage = gameRenderers[match.gameId];
  const remaining = Math.max(
    0,
    Math.ceil(((phase === 'display' ? round?.displayUntil : round?.deadline) ?? now) - now) / 1000,
  );
  const progress = Math.min(
    100,
    (remaining * 100) /
      ((phase === 'display'
        ? (round?.rules?.displayMs ?? DISPLAY_MS)
        : (round?.rules?.answerMs ?? ANSWER_MS)) /
        1000),
  );
  const won = match.winner === match.you.id;
  return (
    <>
      <Header profile={match.you} />
      <main className="match-main">
        <div className="match-breadcrumb">
          <Link href="/" className="back-link">
            <ArrowLeft size={16} /> Back to the playground
          </Link>
          <span className="secure-note">
            <ShieldCheck size={14} /> One fair shot per round
          </span>
        </div>
        <div className="match-heading">
          <div>
            <span className="eyebrow muted">
              {match.mode === 'solo' ? 'YOU vs. YOU' : 'THE FIVE-ROUND FACE-OFF'}
            </span>
            <h1>
              {match.yoursComplete
                ? match.complete
                  ? 'The results are in.'
                  : 'Your score is set.'
                : 'Counting Boxes'}
            </h1>
          </div>
          <span className="round-counter">
            <Box size={17} /> 5 rounds · Spatial reasoning
          </span>
        </div>
        {error && (
          <div className="error-banner" role="alert">
            {error}
            <button onClick={refresh}>Refresh</button>
          </div>
        )}
        <div className="battle-layout">
          <section className="battle-card">
            <div className="round-tracker" aria-label="Round progress">
              {match.rounds.map((r) => (
                <span
                  key={r.number}
                  className={`${r.number === currentNumber && !match.yoursComplete ? 'active' : ''} ${r.state === 'done' ? 'finished' : ''}`}
                  aria-label={`Round ${r.number}, ${r.state}`}
                >
                  {r.state === 'done' ? <Check size={15} /> : r.number}
                </span>
              ))}
            </div>
            {match.yoursComplete ? (
              <div className="results-panel">
                <span className="trophy-circle">
                  <Trophy size={42} />
                </span>
                <div className="eyebrow muted">
                  {match.mode === 'solo'
                    ? 'PRACTICE MAKES PROGRESS'
                    : !match.complete
                      ? 'OVER TO YOUR FRIEND'
                      : match.winner === 'draw'
                        ? 'GREAT MINDS THINK ALIKE'
                        : won
                          ? 'BRAGGING RIGHTS: EARNED'
                          : 'A WORTHY OPPONENT'}
                </div>
                <h2>
                  {match.mode === 'solo'
                    ? 'Nicely done, brain.'
                    : !match.complete
                      ? 'The challenge is on.'
                      : match.winner === 'draw'
                        ? 'It’s a draw!'
                        : won
                          ? 'You won this one!'
                          : `${match.opponent?.name} takes it!`}
                </h2>
                <p>
                  {match.mode === 'solo'
                    ? 'Five rounds of a little more focus.'
                    : match.complete
                      ? 'A little competition looks good on you.'
                      : expired
                        ? 'The challenge expired before both players finished.'
                        : 'Your rounds are complete. Send the link or come back when your friend finishes.'}
                </p>
                <div className="final-scores">
                  <div>
                    <small>{match.you.name} · YOU</small>
                    <strong>{match.total.toLocaleString()}</strong>
                    <span>POINTS</span>
                  </div>
                  {match.mode !== 'solo' && (
                    <>
                      <span className="versus">vs.</span>
                      <div>
                        <small>{match.opponent?.name ?? 'YOUR FRIEND'}</small>
                        <strong>
                          {match.complete ? match.opponentTotal?.toLocaleString() : '—'}
                        </strong>
                        <span>{match.complete ? 'POINTS' : 'AWAITING RESULT'}</span>
                      </div>
                    </>
                  )}
                </div>
                <div className="results-rounds">
                  {match.rounds.map((r) => (
                    <div key={r.number}>
                      <span>Round {r.number}</span>
                      <strong>{r.attempt?.score ?? 0}</strong>
                      {match.mode !== 'solo' && (
                        <span>
                          {r.finalized ? (r.opponent?.score ?? '—') : 'Hidden until finalized'}
                        </span>
                      )}
                    </div>
                  ))}
                </div>
                <button
                  disabled={busy}
                  className="button button-dark"
                  onClick={async () => {
                    setBusy(true);
                    try {
                      const next = await api<MatchView>(`/matches/${id}/rematch`, 'POST');
                      router.push(`/match/${next.id}`);
                      setFocused(null);
                    } catch (e) {
                      setError((e as Error).message);
                    } finally {
                      setBusy(false);
                    }
                  }}
                >
                  <RotateCcw size={17} />{' '}
                  {match.mode === 'solo' ? 'Practice again' : 'Create a rematch'}
                  <ArrowRight size={17} />
                </button>
              </div>
            ) : round?.state === 'done' ? (
              <div className="round-result">
                <span className={`result-icon ${round.attempt?.correct ? 'correct' : ''}`}>
                  {round.attempt?.correct ? <Check size={36} /> : <X size={36} />}
                </span>
                <span className="eyebrow muted">ROUND {currentNumber} COMPLETE</span>
                <h2>
                  {round.attempt?.correct
                    ? 'You’ve got a good eye.'
                    : round.attempt?.timedOut
                      ? 'The clock got this one.'
                      : 'A tricky little stack.'}
                </h2>
                <p>
                  {round.attempt?.correct
                    ? 'Every cube accounted for.'
                    : 'Shake it off. There’s another puzzle ahead.'}
                </p>
                <strong className="round-score">
                  +{round.attempt?.score.toLocaleString()} <span>points</span>
                </strong>
                {match.mode !== 'solo' && (
                  <p className="opponent-round-score">
                    {round.finalized
                      ? `${match.opponent?.name}: ${round.opponent?.score ?? 0} points`
                      : 'Your friend’s result stays hidden until both attempts are final.'}
                  </p>
                )}
                <button
                  className="button button-dark"
                  disabled={now < (round.feedbackUntil ?? 0)}
                  onClick={() => {
                    setFocused(currentNumber + 1);
                    changeAnswer('0');
                  }}
                >
                  Next round <ArrowRight size={17} />
                </button>
              </div>
            ) : (
              <>
                <div className="round-title">
                  <div>
                    <span className="eyebrow muted">ROUND {currentNumber} OF 5</span>
                    <h2>
                      {phase === 'ready'
                        ? 'Make every cube count.'
                        : phase === 'display'
                          ? 'Look closely. Think in 3D.'
                          : 'How many cubes were there?'}
                    </h2>
                  </div>
                  {phase !== 'ready' &&
                    (phase === 'display' || round?.rules?.answerTimeLimit !== false) && (
                      <span
                        className={`timer ${remaining <= 3 ? 'urgent' : ''}`}
                        role="timer"
                        aria-label={`${remaining} seconds remaining`}
                      >
                        <Clock3 size={18} />
                        {remaining.toFixed(0)}
                        <small>s</small>
                      </span>
                    )}
                </div>
                {phase !== 'ready' &&
                  (phase === 'display' || round?.rules?.answerTimeLimit !== false) && (
                    <div className="timer-track">
                      <span style={{ width: `${progress}%` }} />
                    </div>
                  )}
                <Stage
                  visible={phase === 'display'}
                  puzzle={phase === 'display' ? round?.puzzle : undefined}
                />
                {phase === 'ready' ? (
                  <div className="round-instructions">
                    <p>
                      You’ll have{' '}
                      <strong>{(round?.rules?.displayMs ?? DISPLAY_MS) / 1000} seconds</strong> to
                      study the stack, then{' '}
                      {round?.rules?.answerTimeLimit === false ? (
                        'take as long as you need to answer.'
                      ) : (
                        <>
                          <strong>{(round?.rules?.answerMs ?? ANSWER_MS) / 1000} seconds</strong> to
                          answer.
                        </>
                      )}{' '}
                      Count every cube, including the hidden ones.
                    </p>
                    <button
                      className="button button-dark"
                      disabled={busy || expired}
                      onClick={start}
                    >
                      {busy ? <LoaderCircle className="spin" size={17} /> : <Sparkles size={17} />}{' '}
                      {expired ? 'Challenge expired' : `Start round ${currentNumber}`}
                      <ArrowRight size={17} />
                    </button>
                    <small>Correct answer: 1,000 points + up to 500 for speed.</small>
                  </div>
                ) : remaining <= 0 && round?.rules?.answerTimeLimit !== false ? (
                  <p className="memorize-note">Time’s up. Setting your score…</p>
                ) : (
                  <form
                    className="answer-form"
                    onSubmit={(e) => {
                      e.preventDefault();
                      if (phase === 'answer') submit(Number(answer || '0'));
                    }}
                  >
                    <div className="count-method" role="group" aria-label="Answer method">
                      <button
                        type="button"
                        disabled={busy || phase !== 'answer'}
                        aria-pressed={!typeAnswer}
                        onClick={() => setTypeAnswer(false)}
                      >
                        Quick Count
                      </button>
                      <button
                        type="button"
                        disabled={busy || phase !== 'answer'}
                        aria-pressed={typeAnswer}
                        onClick={() => setTypeAnswer(true)}
                      >
                        Type Answer
                      </button>
                    </div>
                    {typeAnswer ? (
                      <>
                        <label htmlFor="cube-answer">YOUR CUBE COUNT</label>
                        <input
                          id="cube-answer"
                          type="number"
                          inputMode="numeric"
                          min={0}
                          max={100}
                          value={answer}
                          onChange={(e) => changeAnswer(e.target.value)}
                          disabled={busy || phase !== 'answer'}
                        />
                      </>
                    ) : (
                      <>
                        <output aria-label="Cube count" className="quick-count-value">
                          {answer || '0'}
                        </output>
                        <div className="quick-count-buttons">
                          <button
                            type="button"
                            aria-label="Subtract one"
                            disabled={busy || phase !== 'answer' || Number(answer) <= 0}
                            onClick={() => changeAnswer(String(Math.max(0, Number(answer) - 1)))}
                          >
                            −1
                          </button>
                          <button
                            type="button"
                            className="count-plus"
                            aria-label="Add one"
                            disabled={busy || phase !== 'answer' || Number(answer) >= 100}
                            onClick={() => changeAnswer(String(Math.min(100, Number(answer) + 1)))}
                          >
                            +1
                          </button>
                          <button
                            type="button"
                            disabled={busy || phase !== 'answer'}
                            onClick={() => changeAnswer('0')}
                          >
                            Clear
                          </button>
                        </div>
                      </>
                    )}
                    <button
                      className="button button-dark"
                      type="submit"
                      disabled={busy || phase !== 'answer'}
                    >
                      {busy ? (
                        <LoaderCircle className="spin" size={18} />
                      ) : (
                        <>
                          Done <ArrowRight size={17} />
                        </>
                      )}
                    </button>
                    <small>
                      {phase === 'display'
                        ? 'Count while you look. Submit when the cubes disappear.'
                        : 'Your count is saved. One scored attempt.'}
                    </small>
                  </form>
                )}
              </>
            )}
          </section>
          <aside className="battle-sidebar">
            <section className="scoreboard">
              <span className="eyebrow muted">THE MATCHUP</span>
              <div className="player-row">
                <span className="avatar purple">{match.you.name[0]}</span>
                <span>
                  <strong>{match.you.name}</strong>
                  <small>That’s you</small>
                </span>
                <strong>{match.total.toLocaleString()}</strong>
              </div>
              {match.mode !== 'solo' && (
                <div className="player-row">
                  <span className="avatar orange">{match.opponent?.name[0] ?? '?'}</span>
                  <span>
                    <strong>{match.opponent?.name ?? 'Your friend'}</strong>
                    <small>
                      {match.complete
                        ? 'Final score'
                        : match.opponent
                          ? 'Challenge accepted'
                          : 'Waiting for a challenger'}
                    </small>
                  </span>
                  <strong>{match.complete ? match.opponentTotal?.toLocaleString() : '—'}</strong>
                </div>
              )}
              <p>
                <ShieldCheck size={14} />
                {match.mode === 'solo'
                  ? 'Your next best is waiting.'
                  : 'Opponent totals unlock after all rounds are final.'}
              </p>
            </section>
            {match.inviteUrl && (
              <section className="share-card">
                <span className="share-icon">
                  <Link2 size={23} />
                </span>
                <h3>A little rivalry goes a long way.</h3>
                <p>
                  {match.yoursComplete
                    ? 'Your score is set. Send your friend the challenge.'
                    : 'Finish your rounds, then send this link to a friend. They’ll play the same puzzles.'}
                </p>
                <label className="sr-only" htmlFor="challenge-link">
                  Challenge invitation link
                </label>
                <input
                  id="challenge-link"
                  readOnly
                  value={match.inviteUrl}
                  onFocus={(e) => e.target.select()}
                />
                <button className="button button-dark" onClick={copy}>
                  {copied ? <Check size={16} /> : <Copy size={16} />}{' '}
                  {copied ? 'Link copied!' : 'Copy challenge link'}
                </button>
                {copyError && <small role="status">{copyError}</small>}
                <small>
                  <Clock3 size={13} /> One friend · Expires{' '}
                  {new Date(match.expiresAt).toLocaleDateString()}
                </small>
              </section>
            )}
            <div className="tip-card">
              <span>✳</span>
              <p>
                <strong>A little spatial thinking.</strong>The cubes you can’t see still count.
                Imagine what’s holding the stack up.
              </p>
            </div>
          </aside>
        </div>
      </main>
      <Footer />
    </>
  );
}
