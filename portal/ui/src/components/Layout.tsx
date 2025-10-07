import type { PropsWithChildren, ReactNode } from 'react';
import Link from 'next/link';
import styles from './Layout.module.css';

type LayoutProps = PropsWithChildren<{
  title?: ReactNode;
  description?: ReactNode;
}>;

const Layout = ({ children, title, description }: LayoutProps) => (
  <div className={styles.wrapper}>
    <header className={styles.header}>
      <Link href="/" className={styles.brand}>
        RALF Portal
      </Link>
      <div className={styles.meta}>
        {title ? <h1>{title}</h1> : <h1>Service Catalog</h1>}
        {description ? <p>{description}</p> : <p>Discover services and operational runbooks.</p>}
      </div>
    </header>
    <main className={styles.main}>{children}</main>
    <footer className={styles.footer}>Built with Next.js • {new Date().getFullYear()}</footer>
  </div>
);

export default Layout;
