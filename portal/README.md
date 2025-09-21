# RALF Portal

The portal provides a lightweight UI for service discovery, status visibility, and runbook links.

- `ui/` – Static site or SSG output (e.g., Next.js) that lists services, health indicators, and documentation links.
- `api/` – Optional microservice for aggregating health data from Prometheus, GitOps runner status, and backup reports.

## TODO
- [ ] Implement UI build pipeline
- [ ] Define service catalog schema
- [ ] Integrate authentication (Keycloak/Authelia)
