import type { NextConfig } from 'next';
import { config } from 'dotenv';
import { resolve } from 'node:path';
config({ path: resolve(process.cwd(), '../../.env'), quiet: true });
const nextConfig: NextConfig = {
  devIndicators: false,
  poweredByHeader: false,
  transpilePackages: ['@brain/shared'],
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: `${process.env.API_URL ?? 'http://127.0.0.1:4000'}/api/:path*`,
      },
      {
        source: '/socket.io/:path*',
        destination: `${process.env.API_URL ?? 'http://127.0.0.1:4000'}/socket.io/:path*`,
      },
    ];
  },
};
export default nextConfig;
