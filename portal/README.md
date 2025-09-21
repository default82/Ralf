# RALF Portal

The portal provides a lightweight UI for service discovery, status visibility, and runbook links.

- `ui/` – Static site or SSG output (e.g., Next.js) that lists services, health indicators, and documentation links.
- `api/` – Optional microservice for aggregating health data from Prometheus, GitOps runner status, and backup reports.

## TODO
- [ ] Scaffold a static UI build pipeline that renders the service catalogue from inventory data.
- [ ] Add authentication middleware that delegates to the central auth LXC.
- [ ] Surface health status badges sourced from monitoring and backup reports.

See [docs/TODO.md](../docs/TODO.md#portal) for the canonical backlog.
