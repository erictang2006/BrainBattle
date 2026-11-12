import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  title: 'Brain Battle — A little friendly brain power',
  description:
    'Five quick rounds. One friendly rivalry. Challenge a friend to Counting Boxes and see whose brain comes out on top.',
  referrer: 'same-origin',
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
