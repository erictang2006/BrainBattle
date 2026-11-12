'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import {
  ArrowRight,
  ArrowUpRight,
  Box,
  Check,
  Clock3,
  Copy,
  Flame,
  Grid3X3,
  Link2,
  LoaderCircle,
  MousePointer2,
  Play,
  Sparkles,
  Swords,
  Users,
  X,
  Zap,
} from 'lucide-react';
import type { MatchSummary, MatchView, Profile } from '@brain/shared';
import { Header, Footer } from '../components/shell';
import { CubeArt } from '../components/cubes';
import { api, ensureSession } from '../lib/api';

export default function Home() {
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [recent, setRecent] = useState<MatchSummary[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [modal, setModal] = useState<'live' | 'profile' | null>(null);
  const [name, setName] = useState('');
  async function connect() {
    try {
      const p = await ensureSession();
      setProfile(p);
      setName(p.name);
      setRecent(await api<MatchSummary[]>('/matches'));
      setError('');
    } catch (e) {
      setError((e as Error).message);
    }
  }
  useEffect(() => {
    void connect();
  }, []);
  async function create(mode: 'challenge' | 'solo') {
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      if (!profile) setProfile(await ensureSession());
      const match = await api<MatchView>('/matches', 'POST', { mode });
      router.push(`/match/${match.id}`);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }
  return (
    <>
      <Header profile={profile} onProfile={() => setModal('profile')} />
      <main className="home-main">
        <section className="hero">
          <div className="hero-copy">
            <div className="eyebrow">
              <span className="status-dot" /> A LITTLE COMPETITION. A LOT OF BRAIN POWER.
            </div>
            <h1>
              Small games.
              <br />
              Big <span className="highlight-word">brain</span>
              <br className="desktop-break" /> energy<span className="orange-period">.</span>
            </h1>
            <p className="hero-description">
              Give your brain a playful workout. Challenge your friends, beat your best, and make
              every little victory count.
            </p>
            <button
              className="button button-dark hero-cta"
              onClick={() => create('challenge')}
              disabled={busy}
            >
              {busy ? <LoaderCircle className="spin" size={19} /> : <Swords size={19} />} Challenge
              a friend <ArrowUpRight size={19} />
            </button>
            <div className="hero-footnote">
              <span>
                <Check size={14} /> No sign-up needed
              </span>
              <span>
                <Clock3 size={14} /> Just a few minutes
              </span>
            </div>
          </div>
          <div className="hero-art" aria-label="Counting Boxes game illustration">
            <div className="art-grid" />
            <div className="orbit orbit-one" />
            <div className="orbit orbit-two" />
            <span className="art-label">
              <span className="mini-dot" /> YOUR NEXT FRIENDLY RIVALRY
            </span>
            <div className="floating-label label-count">
              <Box size={19} />
              <div>
                <small>LOOK CLOSELY</small>
                <strong>Count every cube.</strong>
              </div>
              <Sparkles size={18} />
            </div>
            <CubeArt hero />
            <div className="floating-label label-you">
              <span className="avatar purple">Y</span>
              <div>
                <small>YOU vs. YOUR FRIEND</small>
                <strong>Let the brain battle begin.</strong>
              </div>
              <span className="little-lightning">
                <Zap size={17} fill="currentColor" />
              </span>
            </div>
            <span className="art-spark spark-one">✳</span>
            <span className="art-spark spark-two">✦</span>
            <span className="art-corner">01 / COUNTING BOXES</span>
          </div>
        </section>
        <section className="play-section" aria-labelledby="play-heading">
          <div className="section-top">
            <div>
              <span className="eyebrow muted">READY, SET, THINK.</span>
              <h2 id="play-heading">Pick your kind of competition.</h2>
            </div>
            <span className="section-aside">One brain. Plenty of ways to play.</span>
          </div>
          <div className="mode-grid">
            <button className="mode-card live-card" onClick={() => setModal('live')}>
              <span className="mode-icon">
                <Swords size={24} />
              </span>
              <span className="mode-kicker">
                IN THE MOMENT <span className="coming-pill">COMING SOON</span>
              </span>
              <h3>Live Battle</h3>
              <p>
                Same room. Same clock.
                <br />A real-time race with your people.
              </p>
              <span className="card-bottom">
                <span>
                  <Users size={14} /> 2–8 players
                </span>
                <span className="circle-arrow">
                  <ArrowUpRight size={20} />
                </span>
              </span>
            </button>
            <button
              className="mode-card challenge-card"
              onClick={() => create('challenge')}
              disabled={busy}
            >
              <span className="mode-icon">
                <Link2 size={24} />
              </span>
              <span className="mode-kicker">
                YOUR FRIEND. THEIR OWN TIME. <span className="available-dot" />
              </span>
              <h3>Challenge Friend</h3>
              <p>
                Set the score. Send a link.
                <br />
                See who comes out on top.
              </p>
              <span className="card-bottom">
                <span>
                  <Users size={14} /> 1 vs. 1 · Play anytime
                </span>
                <span className="circle-arrow">
                  <ArrowUpRight size={20} />
                </span>
              </span>
            </button>
            <button className="mode-card solo-card" onClick={() => create('solo')} disabled={busy}>
              <span className="mode-icon">
                <Flame size={24} />
              </span>
              <span className="mode-kicker">YOU vs. YOU</span>
              <h3>Solo Practice</h3>
              <p>
                A little warm-up goes a long way.
                <br />
                Find your focus and beat your best.
              </p>
              <span className="card-bottom">
                <span>
                  <Play size={14} /> No pressure. Just progress.
                </span>
                <span className="circle-arrow">
                  <ArrowUpRight size={20} />
                </span>
              </span>
            </button>
          </div>
        </section>
        {error && (
          <div className="error-banner" role="alert">
            {error}
            <button onClick={connect}>Reconnect</button>
          </div>
        )}
        {recent.length > 0 && (
          <section className="recent-section">
            <div className="section-top">
              <h2>Pick up where you left off.</h2>
              <span className="section-aside">Your recent battles</span>
            </div>
            <div className="recent-list">
              {recent.map((m) => (
                <Link href={`/match/${m.id}`} key={m.id}>
                  <span className="recent-icon">
                    <Box size={19} />
                  </span>
                  <span>
                    <strong>
                      {m.mode === 'solo'
                        ? 'Solo practice'
                        : m.opponent
                          ? `You vs. ${m.opponent}`
                          : 'Your open challenge'}
                    </strong>
                    <small>Counting Boxes · {new Date(m.createdAt).toLocaleDateString()}</small>
                  </span>
                  <ArrowRight size={19} />
                </Link>
              ))}
            </div>
          </section>
        )}
        <section className="games-section" id="games">
          <div className="section-top">
            <div>
              <span className="eyebrow muted">TINY CHALLENGES. BIG SATISFACTION.</span>
              <h2>Meet your brain’s new playground.</h2>
            </div>
            <span className="games-count">01 AVAILABLE / 03 IN THE MAKING</span>
          </div>
          <div className="games-grid">
            <button className="game-tile" onClick={() => create('solo')} disabled={busy}>
              <span className="game-tile-art cubes-mini">
                <Box size={54} strokeWidth={1.3} />
                <span className="game-live-badge">PLAY NOW</span>
              </span>
              <span className="game-tile-info">
                <span>
                  <strong>Counting Boxes</strong>
                  <small>Spatial reasoning · Attention</small>
                </span>
                <ArrowUpRight size={19} />
              </span>
            </button>
            <div className="game-tile upcoming">
              <span className="game-tile-art reaction-mini">
                <Zap size={58} strokeWidth={1.3} />
                <span className="game-live-badge">COMING SOON</span>
              </span>
              <span className="game-tile-info">
                <span>
                  <strong>Reaction Time</strong>
                  <small>Speed · Reflexes</small>
                </span>
                <Clock3 size={17} />
              </span>
            </div>
            <div className="game-tile upcoming">
              <span className="game-tile-art sequence-mini">
                <Grid3X3 size={58} strokeWidth={1.3} />
                <span className="game-live-badge">COMING SOON</span>
              </span>
              <span className="game-tile-info">
                <span>
                  <strong>Sequence Memory</strong>
                  <small>Memory · Focus</small>
                </span>
                <Clock3 size={17} />
              </span>
            </div>
          </div>
        </section>
        <div className="friendly-note">
          <span className="note-icon">✳</span>
          <p>
            A sharper mind is great.
            <br />
            <strong>Bragging rights are a nice bonus.</strong>
          </p>
          <span className="note-line" />
          <span className="note-detail">
            5 quick rounds. A fresh challenge every time.
            <br />
            Bring a friend. We’ll bring the cubes.
          </span>
        </div>
      </main>
      <Footer />
      {modal && (
        <div className="modal-backdrop" onClick={() => setModal(null)}>
          <section
            role="dialog"
            aria-modal="true"
            aria-labelledby="modal-title"
            className="modal"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              className="modal-close"
              aria-label="Close dialog"
              onClick={() => setModal(null)}
            >
              <X size={20} />
            </button>
            {modal === 'live' ? (
              <>
                <span className="mode-icon">
                  <Swords size={26} />
                </span>
                <h2 id="modal-title">Good things take a little thinking.</h2>
                <p>
                  Live rooms for 2–8 players are coming next. For now, send a friend a five-round
                  Counting Boxes challenge and play on your own schedules.
                </p>
                <button
                  className="button button-dark"
                  onClick={() => {
                    setModal(null);
                    void create('challenge');
                  }}
                >
                  Create a challenge <ArrowRight size={17} />
                </button>
              </>
            ) : (
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  try {
                    setProfile(await api<Profile>('/profile', 'PATCH', { name }));
                    setModal(null);
                  } catch (e) {
                    setError((e as Error).message);
                  }
                }}
              >
                <h2 id="modal-title">Make a name for yourself.</h2>
                <p>
                  Your guest profile stays with this browser. Pick a name your friends will
                  recognize.
                </p>
                <label className="field-label" htmlFor="player-name">
                  PLAYER NAME
                </label>
                <input
                  id="player-name"
                  autoFocus
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  minLength={2}
                  maxLength={24}
                  required
                />
                <button className="button button-dark" type="submit">
                  Save player name <Check size={17} />
                </button>
              </form>
            )}
          </section>
        </div>
      )}
    </>
  );
}
