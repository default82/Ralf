import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import type { PropsWithChildren } from 'react';
import '../styles/globals.css';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'RALF Portal',
  description: 'Operational portal for services, runbooks, and health insights.'
};

const RootLayout = ({ children }: PropsWithChildren) => (
  <html lang="en" className={inter.className}>
    <body>{children}</body>
  </html>
);

export default RootLayout;
