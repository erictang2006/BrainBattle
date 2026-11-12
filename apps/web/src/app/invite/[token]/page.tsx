'use client';
import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { ArrowRight, Clock3, LoaderCircle, Swords } from 'lucide-react';
import type { InvitationView, MatchView, Profile } from '@brain/shared';
import { api, ensureSession } from '../../../lib/api';
import { Header, Footer } from '../../../components/shell';
import { CubeArt } from '../../../components/cubes';
export default function InvitationPage() {
  const { token } = useParams<{ token: string }>();
  const router = useRouter();
  const [invitation, setInvitation] = useState<InvitationView | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    void Promise.all([api<InvitationView>(`/invitations/${token}`), ensureSession()])
      .then(([i, p]) => {
        setInvitation(i);
        setProfile(p);
      })
      .catch((e) => setError(e.message));
  }, [token]);
  return (
    <>
      <Header profile={profile} />
      <main className="invite-main">
        <section className="invite-card">
          <div className="invite-art">
            <CubeArt hero />
            <span className="invite-spark">✳</span>
          </div>
          <div className="invite-content">
            <span className="eyebrow muted">A FRIENDLY CHALLENGE HAS ARRIVED</span>
            <h1>
              {invitation
                ? `${invitation.hostName} thinks you’re up for it.`
                : 'A little brain battle?'}
            </h1>
            <p>
              Five rounds of Counting Boxes. The same puzzles, your own clock. Think you can take
              the top spot?
            </p>
            <div className="invite-facts">
              <span>
                <Swords size={17} /> 1 vs. 1
              </span>
              <span>
                <Clock3 size={17} /> Play on your own time
              </span>
            </div>
            {error && (
              <div className="error-banner" role="alert">
                {error}
              </div>
            )}
            {invitation?.expired ? (
              <p className="expired-message">
                This invitation has expired. Ask your friend for a rematch.
              </p>
            ) : (
              <button
                className="button button-dark"
                disabled={!invitation || !profile || busy}
                onClick={async () => {
                  setBusy(true);
                  try {
                    const match = await api<MatchView>(`/invitations/${token}/claim`, 'POST');
                    router.push(`/match/${match.id}`);
                  } catch (e) {
                    setError((e as Error).message);
                    setBusy(false);
                  }
                }}
              >
                {busy ? <LoaderCircle size={18} className="spin" /> : <Swords size={18} />}{' '}
                {invitation?.claimed ? 'Open this challenge' : 'Challenge accepted'}
                <ArrowRight size={18} />
              </button>
            )}
            <small>
              {invitation?.claimed
                ? 'This link has been claimed. Only the two players can open the match.'
                : 'No account needed. One link, one challenger.'}
            </small>
            <Link className="back-link" href="/">
              Back to the playground
            </Link>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
