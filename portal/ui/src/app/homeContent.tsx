import type { Session } from 'next-auth';
import Link from 'next/link';

type ServiceLink = {
  name: string;
  description: string;
  href: string;
};

type Styles = {
  section: string;
  list: string;
  card: string;
  prompt: string;
  promptActions: string;
  promptCta: string;
};

type HomePageContentProps = {
  session: Session | null;
  services: ServiceLink[];
  styles: Styles;
};

const HomePageContent = ({ session, services, styles }: HomePageContentProps) => {
  if (!session) {
    return (
      <section className={styles.section} aria-labelledby="catalog-heading">
        <div className={styles.prompt}>
          <h2 id="catalog-heading">Sign in to view the service catalog</h2>
          <p>
            The catalog contains runbooks, ownership information, and operational tooling that is only
            available to authenticated team members.
          </p>
          <div className={styles.promptActions}>
            <Link className={styles.promptCta} href="/api/auth/signin">
              Continue with single sign-on
            </Link>
            <p>
              Need access? Contact your Keycloak or Authelia administrator to be assigned to the RALF Portal
              client.
            </p>
          </div>
        </div>
      </section>
    );
  }

  return (
    <section className={styles.section} aria-labelledby="catalog-heading">
      <h2 id="catalog-heading">Featured Services</h2>
      <ul className={styles.list}>
        {services.map((service) => (
          <li key={service.name} className={styles.card}>
            <Link href={service.href}>
              <strong>{service.name}</strong>
              <p>{service.description}</p>
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
};

export type { ServiceLink };
export default HomePageContent;
