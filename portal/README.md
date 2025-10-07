# RALF Portal
The portal provides a lightweight UI for service discovery, status visibility, and runbook links.

- `ui/` – Static site or SSG output (Next.js) that lists services, health indicators, and documentation links.
- `api/` – Optional microservice for aggregating health data from Prometheus, GitOps runner status, and backup reports.

## Getting started

### Prerequisites
- [Node.js](https://nodejs.org/) 20+
- [pnpm](https://pnpm.io/) (Corepack-enabled Node versions work out of the box)

### Environment variables
Create a `.env.local` file in `portal/ui/` (not committed) and provide the following values:

| Variable | Description | Example |
| --- | --- | --- |
| `NEXT_PUBLIC_STATUS_API` | Base URL used by the UI to fetch health summaries. | `https://status.example.com/api` |
| `PORTAL_AUTH_PROVIDER` | Identifier for the authentication provider that should be highlighted to operators. | `keycloak` |

Additional variables can be added as integrations evolve; defaults are safe for static builds.

### Local development workflow
1. Install dependencies:
   ```bash
   cd portal/ui
   pnpm install
   ```
2. Start the development server with hot reload:
   ```bash
   pnpm dev
   ```
3. Run quality gates before committing:
    ```bash
    pnpm run lint
    pnpm run lint:catalog
    pnpm run typecheck
    pnpm test
    pnpm run build
    ```

### Service catalog data model

Service metadata for the UI is defined as YAML in `ui/data/services.yaml` and must conform to the JSON Schema published at `api/schema/service_catalog.schema.json`. Validate changes locally with:

```bash
pnpm run lint:catalog
```

Schema evolution should be accompanied by fixtures and tests (`pnpm test`) to keep the catalog maintainable.

## Automation
- `make portal-build` – Install dependencies and produce a production build of the UI (`pnpm install --frozen-lockfile && pnpm run build`).

## TODO
- [ ] Implement UI build pipeline
- [ ] Integrate authentication (Keycloak/Authelia)
