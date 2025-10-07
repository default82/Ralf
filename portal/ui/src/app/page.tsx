import { getServerSession } from 'next-auth';
import Layout from '@/components/Layout';
import HomePageContent, { type ServiceLink } from './homeContent';
import styles from './page.module.css';
import { authOptions } from '@/lib/auth/options';

const services: ServiceLink[] = [
  {
    name: 'Automation Runner',
    description: 'Executes GitOps workflows and infrastructure pipelines.',
    href: 'https://git.example.com/automation'
  },
  {
    name: 'Observability Stack',
    description: 'Dashboards and alerts for fleet and backup monitoring.',
    href: 'https://grafana.example.com'
  },
  {
    name: 'Knowledge Base',
    description: 'Runbooks and troubleshooting guides for on-call responders.',
    href: 'https://docs.example.com/runbooks'
  }
];

const HomePage = async () => {
  const session = await getServerSession(authOptions);

  return (
    <Layout>
      <HomePageContent session={session} services={services} styles={styles} />
    </Layout>
  );
};

export default HomePage;
