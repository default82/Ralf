
# Local AI Hybrid Guide

> **Hinweis:** Dieser Guide ergänzt die Proxmox-First-Installation über [`automation/ralf/build_local_ai_lxc.sh`](../automation/ralf/build_local_ai_lxc.sh) und beschreibt, wie bestehende Hybrid-Deployments migriert oder parallel betrieben werden können.

## Architecture Overview
The Ralf hybrid platform balances on-device execution for latency-sensitive inference with cloud capacity for burst workloads.

- **Local edge nodes** sind bevorzugt als Proxmox-LXC mittels `automation/ralf/build_local_ai_lxc.sh` aufgebaut. Bestehende Docker-basierte Knoten gelten als Legacy, lassen sich aber weiterhin über `scripts/setup_local_ai.sh` betreiben.
- **Hybrid gateway** routes traffic between local and cloud targets. Locally it runs as a Docker compose stack; in the cloud it is provisioned by Terraform using `scripts/deploy_cloud_stack.sh`.
- **Cloud control plane** hosts monitoring, autoscaling policies, and a secure artifact registry for model snapshots. It integrates with the gateway through authenticated webhooks (credentials are provided at runtime via environment variables; never commit secrets).

Data never leaves the secure perimeter without encryption and observability hooks, ensuring compliance with enterprise guardrails.

## Setup Flow
Follow the steps below on a fresh workstation.

1. **Install prerequisites**
   - Proxmox host with Zugriff auf `automation/ralf/build_local_ai_lxc.sh`
   - Optional (Legacy): Docker/Podman for bestehende Hybrid-Gateways, Terraform für Cloud-Stacks
   - [Ollama](https://ollama.ai/) (auf Proxmox-LXC bereits durch das Skript installiert)
   - `direnv` oder ähnliches Tooling, falls Secrets für Cloud-Bestandteile injiziert werden müssen
2. **Clone the repository**
   ```bash
   git clone <your-fork-url>
   cd Ralf
   ```
3. **Bootstrap the local model runtime**
   - **Proxmox-First:**
     ```bash
     automation/ralf/build_local_ai_lxc.sh --dry-run
     sudo automation/ralf/build_local_ai_lxc.sh
     pct enter 10060 && ollama pull llama3:8b
     ```
     Der Container bringt Ollama & Wrapper bereits mit; weitere Konfiguration erfolgt in `/srv/ralf`.
   - **Legacy Docker Node:**
     ```bash
     ./scripts/setup_local_ai.sh llama3:8b
     ```
     Dieser Pfad bleibt für Übergangsphasen verfügbar, wird jedoch nicht mehr aktiv weiterentwickelt.
4. **Start supporting services (Legacy Gateway)**
   ```bash
   docker compose up -d
   ```
5. **(Optional) Prepare the cloud stack (Legacy Terraform)**
   ```bash
   export TF_VAR_environment=staging
   ./scripts/deploy_cloud_stack.sh -auto-approve
   ```
   The script expects credentials to be sourced from your shell session (e.g., `AWS_PROFILE`, `GOOGLE_APPLICATION_CREDENTIALS`). Do not commit secrets to the repo.

## Usage Examples

### Local inference
```bash
curl -s \
  -X POST http://localhost:11434/api/generate \
  -d '{"model": "llama3:8b", "prompt": "Summarize the latest build status."}'
```
Expect a JSON response containing the generated summary.

### Cloud burst routing
Once the Terraform stack is live, point the gateway at the cloud endpoint:
```bash
gatewayctl set-backend \
  --local http://localhost:11434 \
  --cloud https://<cloud-endpoint>/v1/llm
```
Use the provided runbook to rotate credentials; never hardcode tokens in configuration files.

## Troubleshooting
- **`ollama pull` fails with network timeout**: confirm outbound access and retry with `OLLAMA_HOST=https://proxy.yourdomain` if routing through a proxy.
- **Docker compose services crash**: inspect logs via `docker compose logs -f <service>` and ensure GPU drivers (if applicable) are installed.
- **Terraform apply prompts for credentials**: export the required environment variables before running `scripts/deploy_cloud_stack.sh`; check your secret manager if unsure.
- **Gateway latency spikes**: verify the local node has GPU resources free; otherwise switch routing to the cloud backend temporarily using `gatewayctl`.

## PR Merge Checklist
Before requesting a merge into `main`, confirm the following:

- [ ] Local bootstrap completes: `./scripts/setup_local_ai.sh llama3:8b`
- [ ] `docker compose up -d` succeeds and health checks pass
- [ ] Cloud infrastructure plan reviewed: `./scripts/deploy_cloud_stack.sh -plan`
- [ ] Automated tests (unit/integration) executed and recorded
- [ ] Security scan outputs attached (no secrets committed)
- [ ] Documentation updated with any new endpoints or scripts
- [ ] Merge target confirmed: `feature/local-ai-hybrid` → `main`

