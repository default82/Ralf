import styles from './page.module.css';
import Layout from '@/components/Layout';

const services = [
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

const HomePage = () => (
  <Layout>
    <section className={styles.section}>
      <h2>Featured Services</h2>
      <ul className={styles.list}>
        {services.map((service) => (
          <li key={service.name} className={styles.card}>
            <a href={service.href}>
              <strong>{service.name}</strong>
              <p>{service.description}</p>
            </a>
          </li>
        ))}
      </ul>
    </section>
  </Layout>
);

export default HomePage;
