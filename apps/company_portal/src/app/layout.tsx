import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Omelo for Employers',
  description:
    'Post a job, reach workers near you, and hire without an HR department.',
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
