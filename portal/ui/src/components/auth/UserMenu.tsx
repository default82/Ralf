'use client';

import { signIn, signOut, useSession } from 'next-auth/react';
import styles from '../Layout.module.css';

const UserMenu = () => {
  const { data: session, status } = useSession();

  if (status === 'loading') {
    return <span className={styles.userStatus}>Validating session…</span>;
  }

  if (!session) {
    return (
      <button type="button" className={styles.userAction} onClick={() => signIn()}>
        Sign in
      </button>
    );
  }

  const displayName = session.user?.name ?? session.user?.email ?? 'Authenticated user';

  return (
    <div className={styles.userMenu}>
      <span className={styles.userStatus}>{displayName}</span>
      <button type="button" className={styles.userAction} onClick={() => signOut()}>
        Sign out
      </button>
    </div>
  );
};

export default UserMenu;
