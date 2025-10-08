# RALF Portal
The portal provides a lightweight UI for service discovery, status visibility, and runbook links.

- `ui/` – Static site or SSG output (Next.js) that lists services, health indicators, and documentation links.
- `api/` – Optional microservice for aggregating health data from Prometheus, GitOps runner status, and backup reports.

## Getting started

### Prerequisites
- [Node.js](https://nodejs.org/) 20+
- [pnpm](https://pnpm.io/) (Corepack-enabled Node versions work out of the box)

### Environment variables
Create a `.env.local` file in `portal/ui/` (not committed) and provide the following values. An annotated template is available at the repository root as `.env.example`.

| Variable | Description | Example |
| --- | --- | --- |
| `AUTH_ISSUER_URL` | OIDC issuer URL for your Keycloak realm or Authelia deployment. | `https://id.example.com/realms/operations` |
| `AUTH_CLIENT_ID` | Client ID configured in the identity provider for the portal. | `ralf-portal` |
| `AUTH_CLIENT_SECRET` | Confidential client secret issued by the provider. | `super-secret` |
| `AUTH_SECRET` | Random 32+ byte string used by NextAuth for session encryption. | `generate-with-openssl` |
| `PORTAL_BASE_URL` | Public base URL of the portal; used for redirect validation. | `https://portal.example.com` |
| `NEXTAUTH_URL` | Optional override if the portal is served behind a proxy. | `https://portal.example.com` |

Existing UI variables such as `NEXT_PUBLIC_STATUS_API` remain supported for downstream integrations.

### Authentication setup

1. **Create an OIDC client** in your identity provider.
   - **Keycloak**
     - Realm: select the realm that should house the portal.
     - Client type: `OpenID Connect` → `Confidential`.
     - Access type: enable `Standard Flow` and `Refresh Tokens`.
     - Redirect URIs: add `https://<portal-host>/api/auth/callback/keycloak` and the local development URL `http://localhost:3000/api/auth/callback/keycloak`.
     - Web origins: include the portal origin (e.g. `https://portal.example.com`).
   - **Authelia**
     - Define a client in `configuration.yml` with `authorization_policy: two_factor` (or appropriate policy).
     - Set `redirect_uris` to `https://<portal-host>/api/auth/callback/keycloak` and `http://localhost:3000/api/auth/callback/keycloak`.
     - Ensure the client `scopes` include `openid`, `profile`, and `email` so user details are propagated into the session.
2. **Configure credentials** by copying `.env.example` to `.env.local` and filling the values described above.
3. **Token renewal**
   - The portal uses JWT sessions backed by NextAuth. Refresh tokens from Keycloak/Authelia are stored server-side and exchanged automatically when they expire.
   - To force eager renewal (e.g. before 5 minutes of expiry) configure Keycloak `Access Token Lifespan` or Authelia `access_token_lifespan` accordingly; NextAuth will refresh when the identity provider indicates expiration.
4. **Testing callbacks**
   - Start the UI via `pnpm dev` and browse to `http://localhost:3000`.
   - Trigger the login flow; successful authentication should redirect back to the catalog and display the signed-in identity in the header menu.

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
- [x] Integrate authentication (Keycloak/Authelia)
