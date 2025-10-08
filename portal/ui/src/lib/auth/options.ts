import type { NextAuthOptions } from 'next-auth';
import KeycloakProvider from 'next-auth/providers/keycloak';

type ProviderOverrides = {
  authorization?: string;
};

const requireEnv = (value: string | undefined, name: string) => {
  if (!value) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error(`${name} must be defined to configure authentication.`);
    }

    console.warn(`[auth] Missing ${name}; falling back to placeholder value.`);
    return `missing-${name.toLowerCase()}`;
  }

  return value;
};

const issuer = requireEnv(process.env.AUTH_ISSUER_URL, 'AUTH_ISSUER_URL');
const clientId = requireEnv(process.env.AUTH_CLIENT_ID, 'AUTH_CLIENT_ID');
const clientSecret = requireEnv(process.env.AUTH_CLIENT_SECRET, 'AUTH_CLIENT_SECRET');

const providerOverrides: ProviderOverrides = {};

if (process.env.AUTH_AUTHORIZATION_URL) {
  providerOverrides.authorization = process.env.AUTH_AUTHORIZATION_URL;
}

export const authOptions: NextAuthOptions = {
  providers: [
    KeycloakProvider({
      issuer,
      clientId,
      clientSecret,
      authorization: providerOverrides.authorization
    })
  ],
  session: {
    strategy: 'jwt'
  },
  callbacks: {
    async redirect({ url, baseUrl }) {
      const configuredBaseUrl = process.env.PORTAL_BASE_URL ?? baseUrl;

      if (url.startsWith('/')) {
        return `${configuredBaseUrl}${url}`;
      }

      try {
        const targetUrl = new URL(url);
        const allowedOrigins = [configuredBaseUrl, baseUrl];

        if (allowedOrigins.includes(targetUrl.origin)) {
          return url;
        }
      } catch (error) {
        console.warn('[auth] Failed to parse redirect URL', error);
      }

      return configuredBaseUrl;
    },
    session({ session, token }) {
      if (token && session.user) {
        session.user.id = token.sub ?? session.user.email ?? 'user';
      }
      return session;
    }
  },
  trustHost: true,
  secret: process.env.AUTH_SECRET
};

export type { NextAuthOptions };
