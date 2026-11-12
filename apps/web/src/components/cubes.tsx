'use client';
import { Canvas, useThree } from '@react-three/fiber';
import { BoxGeometry, EdgesGeometry } from 'three';
import { Component, useEffect, useMemo } from 'react';
import type { Puzzle } from '@brain/shared';

export const demoPuzzle: Puzzle = {
  cubes: [
    { x: 0, y: 0, z: 0 },
    { x: 1, y: 0, z: 0 },
    { x: 2, y: 0, z: 0 },
    { x: 1, y: 1, z: 0 },
    { x: 0, y: 0, z: 1 },
    { x: 1, y: 0, z: 1 },
    { x: 2, y: 0, z: 1 },
    { x: 1, y: 1, z: 1 },
    { x: 2, y: 1, z: 1 },
    { x: 0, y: 0, z: 2 },
    { x: 1, y: 0, z: 2 },
    { x: 2, y: 0, z: 2 },
    { x: 1, y: 1, z: 2 },
    { x: 2, y: 1, z: 2 },
    { x: 2, y: 2, z: 2 },
  ],
};
/** Orthographic SVG is also a readable fallback on devices without WebGL. */
export function CubeArt({
  puzzle = demoPuzzle,
  hero = false,
}: {
  puzzle?: Puzzle;
  hero?: boolean;
}) {
  const cubes = [...puzzle.cubes].sort((a, b) => b.x + b.z - a.x - a.z || a.y - b.y);
  return (
    <svg
      viewBox="-170 -200 340 340"
      role="img"
      aria-label="A stack of cubes. Count all cubes, including hidden ones."
      className={hero ? 'hero-cube-art' : 'fallback-cubes'}
    >
      <ellipse cx="0" cy="98" rx="130" ry="24" fill="#c1bce7" opacity=".25" />
      {puzzle.gridSize &&
        Array.from({ length: 25 }, (_, index) => {
          const x = index % 5,
            z = Math.floor(index / 5);
          return (
            <path
              key={`tile-${index}`}
              d="M0 32 31 16 0 0 -31 16Z"
              transform={`translate(${(x - z) * 31},${(3 - x - z) * 16 + 10})`}
              fill="#e6ddf0"
              stroke="#b7a8cd"
              opacity=".5"
            />
          );
        })}
      {cubes.map((c) => {
        const x = (c.x - c.z) * 31,
          y = (3 - c.x - c.z) * 16 - c.y * 35 + 10;
        return (
          <g
            key={`${c.x}:${c.y}:${c.z}`}
            transform={`translate(${x},${y})`}
            stroke={hero ? '#654324' : '#53499b'}
            strokeWidth="1.5"
            strokeLinejoin="round"
          >
            <path d="M0 -35 31 -19 0 -3 -31 -19Z" fill={hero ? '#ffc370' : '#d3ceff'} />
            <path d="M-31 -19 0 -3 0 32 -31 16Z" fill={hero ? '#f5a04b' : '#a99ff1'} />
            <path d="M0 -3 31 -19 31 16 0 32Z" fill={hero ? '#dc7c38' : '#8576d8'} />
          </g>
        );
      })}
    </svg>
  );
}
class RenderBoundary extends Component<
  { puzzle: Puzzle; children: React.ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? <CubeArt puzzle={this.props.puzzle} /> : this.props.children;
  }
}
function Camera() {
  const { camera, size } = useThree();
  useEffect(() => {
    camera.position.set(-7, 6, -7);
    camera.lookAt(0, 0.6, 0);
    if ('zoom' in camera) camera.zoom = Math.min(size.width / 8, size.height / 6);
    camera.updateProjectionMatrix();
  }, [camera, size]);
  return null;
}
function Stack({ puzzle, rotation }: { puzzle: Puzzle; rotation: number }) {
  const geometry = useMemo(() => new BoxGeometry(0.98, 0.98, 0.98), []);
  const edges = useMemo(() => new EdgesGeometry(geometry), [geometry]);
  const centerX = puzzle.gridSize
    ? (puzzle.gridSize - 1) / 2
    : Math.max(...puzzle.cubes.map((c) => c.x)) / 2;
  const centerZ = puzzle.gridSize
    ? (puzzle.gridSize - 1) / 2
    : Math.max(...puzzle.cubes.map((c) => c.z)) / 2;
  return (
    <group rotation={[0, rotation, 0]}>
      {puzzle.gridSize && (
        <gridHelper args={[5, 5, '#b5a4ce', '#cdbfdf']} position={[0, -0.51, 0]} />
      )}
      {puzzle.cubes.map((c) => (
        <mesh
          key={`${c.x}:${c.y}:${c.z}`}
          position={[c.x - centerX, c.y, c.z - centerZ]}
          geometry={geometry}
        >
          <meshStandardMaterial color="#aea2f4" roughness={0.65} />
          <lineSegments geometry={edges}>
            <lineBasicMaterial color="#51418c" />
          </lineSegments>
        </mesh>
      ))}
    </group>
  );
}
export default function CubeRenderer({ puzzle }: { puzzle: Puzzle }) {
  const rotation = 0;
  return (
    <div className="cube-renderer">
      <RenderBoundary puzzle={puzzle}>
        <Canvas
          orthographic
          camera={{ position: [-7, 6, -7], zoom: 50 }}
          dpr={[1, 2]}
          fallback={<CubeArt puzzle={puzzle} />}
          aria-label="Three dimensional stack of cubes"
        >
          <Camera />
          <ambientLight intensity={1.8} />
          <directionalLight position={[-4, 8, -5]} intensity={2.5} />
          <Stack puzzle={puzzle} rotation={rotation} />
        </Canvas>
      </RenderBoundary>
    </div>
  );
}
