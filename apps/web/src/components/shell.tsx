'use client';
import Link from 'next/link';
import { ArrowUpRight, Brain, ChevronRight, Sparkles } from 'lucide-react';
import type { Profile } from '@brain/shared';
export function Header({
  profile,
  onProfile,
}: {
  profile?: Profile | null;
  onProfile?: () => void;
}) {
  return (
    <header className="site-header">
      <Link href="/" className="brand" aria-label="Brain Battle home">
        <span className="brand-icon">
          <Brain size={24} />
        </span>
        brain<span className="brand-second">battle</span>
        <span className="brand-dot">®</span>
      </Link>
      <nav aria-label="Main navigation">
        <Link href="/#games" className="nav-games">
          The games
        </Link>
        <span className="beta-tag">EARLY ACCESS</span>
        <button className="profile-button" onClick={onProfile} disabled={!onProfile}>
          <span className="avatar">{profile?.name[0]?.toUpperCase() ?? 'G'}</span>
          <span>{profile?.name ?? 'Guest player'}</span>
          <ChevronRight size={15} />
        </button>
      </nav>
    </header>
  );
}
export function Footer() {
  return (
    <footer className="site-footer">
      <Link href="/" className="footer-brand">
        <Brain size={19} /> A little friendly brain power.
      </Link>
      <span>
        Built for curious minds <Sparkles size={14} />
      </span>
      <a href="https://humanbenchmark.com" target="_blank" rel="noreferrer">
        Inspired by brain-training classics <ArrowUpRight size={13} />
      </a>
    </footer>
  );
}
