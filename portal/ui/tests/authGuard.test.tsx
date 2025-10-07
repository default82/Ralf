import { describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import { createElement, type ReactNode } from 'react';
import HomePageContent, { type ServiceLink } from '@/app/homeContent';

vi.mock('next/link', () => ({
  default: ({ children, href }: { children: ReactNode; href: string }) => createElement('a', { href }, children)
}));

const styles = {
  section: 'section',
  list: 'list',
  card: 'card',
  prompt: 'prompt',
  promptActions: 'promptActions',
  promptCta: 'promptCta'
} as const;

const services: ServiceLink[] = [
  {
    name: 'Automation Runner',
    description: 'Executes GitOps workflows and infrastructure pipelines.',
    href: 'https://git.example.com/automation'
  }
];

describe('HomePageContent', () => {
  it('renders a sign in prompt when no session exists', () => {
    const html = renderToStaticMarkup(
      HomePageContent({ session: null, services, styles })
    );

    expect(html).toContain('Sign in to view the service catalog');
    expect(html).toContain('/api/auth/signin');
  });

  it('renders services when the user is authenticated', () => {
    const html = renderToStaticMarkup(
      HomePageContent({
        session: {
          expires: new Date().toISOString(),
          user: {
            name: 'Portal User'
          }
        },
        services,
        styles
      })
    );

    expect(html).toContain('Featured Services');
    expect(html).toContain('Automation Runner');
    expect(html).not.toContain('Sign in to view the service catalog');
  });
});
