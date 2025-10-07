'use client';

import type { PropsWithChildren } from 'react';
import { SessionProvider as NextAuthSessionProvider } from 'next-auth/react';
import type { Session } from 'next-auth';

type SessionProviderProps = PropsWithChildren<{
  session: Session | null;
}>;

const SessionProvider = ({ children, session }: SessionProviderProps) => (
  <NextAuthSessionProvider session={session}>{children}</NextAuthSessionProvider>
);

export default SessionProvider;
