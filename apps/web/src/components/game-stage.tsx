'use client';
import dynamic from 'next/dynamic';
import { useEffect } from 'react';
import { Box, EyeOff } from 'lucide-react';
import type { Puzzle } from '@brain/shared';
const Cubes = dynamic(() => import('./cubes'), {
  ssr: false,
  loading: () => <div className="stage-loading">Getting the cubes ready…</div>,
});
export interface MiniGameStageProps {
  puzzle?: Puzzle;
  visible: boolean;
}
function CountingBoxesStage({ puzzle, visible }: MiniGameStageProps) {
  useEffect(() => {
    void import('./cubes');
  }, []);
  return (
    <div className={`game-stage ${visible ? 'is-visible' : ''}`}>
      {visible && puzzle ? (
        <Cubes puzzle={puzzle} />
      ) : (
        <div className="hidden-puzzle">
          <span>{visible ? <Box size={40} /> : <EyeOff size={36} />}</span>
          <h3>{visible ? 'Ready when you are.' : 'Picture it. Then count it.'}</h3>
          <p>{visible ? 'Your puzzle will appear here.' : 'Include the cubes you couldn’t see.'}</p>
        </div>
      )}
    </div>
  );
}
export const gameRenderers = { 'counting-boxes': CountingBoxesStage };
