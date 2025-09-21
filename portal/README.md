# RALF Portal

The portal provides a lightweight UI for service discovery, status visibility, and runbook links.

- `ui/` – Static site or SSG output (e.g., Next.js) that lists services, health indicators, and documentation links.
- `api/` – Optional microservice for aggregating health data from Prometheus, GitOps runner status, and backup reports.

## Implementation blueprint

* **UI build pipeline** – The `portal/ui` directory is designed for a static site generator. Add a `package.json` with build scripts (`npm run build`), then reference the output in the Makefile under a `portal-build` target to publish into the GitOps repo.
* **Service catalog schema** – Define `portal/ui/src/data/services.yaml` describing name, description, icon, URL, and SLO metadata. The site should parse the YAML and render cards grouped by domain (Core, Security, Observability, Automation).
* **Authentication integration** – Front the portal with Caddy + Authelia using the existing `auth` role policies. The UI should expect OIDC-provided headers (e.g., `X-Auth-User`) and render profile status accordingly. Document the wiring in `docs/runbooks/portal.md`.

Filling in these elements will allow the portal to surface the GitOps-managed service catalog with single sign-on.
