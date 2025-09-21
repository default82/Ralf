# RALF – Reproducible Automation for Lab Facilities

RALF provides an Infrastructure-as-Code blueprint to promote any Proxmox VE host into a service-rich homelab. The goal is to keep deployments hardware-agnostic, LXC-first, and fully automated so operators can rebuild the stack from Git with minimal manual work. Release `0.2` adds an interactive installer, automated network discovery, and a Matrix Synapse backbone to coordinate bots and operators.

## Project Purpose
- Deliver a **single source of truth** for networking, storage, automation, and service policies.
- Enable **GitOps-style pull operations** that keep Proxmox, LXCs, and supporting services converged on the declared state.
- Support **self-service UX** through a portal, CLI, and runbooks while maintaining strong governance (least privilege, encrypted secrets, signed artefacts).

## Hardware Layout
RALF targets a primary Proxmox node (`pve0`) but scales out to additional controllers as resources permit. The baseline inventory is defined in [`inventory/hosts.yaml`](inventory/hosts.yaml):

| Role            | Node  | Notes |
|-----------------|-------|-------|
| Automation Ctrl | pve0  | Runs GitOps runner, Semaphore/Foreman integrations, core LXCs |
| Storage         | pve0  | Provides ZFS pools; optional external TrueNAS VM via [`images/golden/vm-debian-bookworm.pkr.hcl`](images/golden/vm-debian-bookworm.pkr.hcl) |
| Ingress/DNS/Auth| LXC   | Containers scheduled on pve0 using golden image [`images/golden/lxc-debian-bookworm.pkr.hcl`](images/golden/lxc-debian-bookworm.pkr.hcl) |

Storage tiers are mapped in the architecture manifest and can be hosted on a single six-year-old pve0 as long as capacity planning is conservative:
- **fast** – encrypted, compressed ZFS pool for latency-sensitive services.
- **bulk** – encrypted capacity pool for general services.
- **secure** – optionally immutable datasets for backups and secrets.

Future expansion plans (GPU node, AI workloads, expanded Matrix bot swarms) are captured in [`docs/README.md`](docs/README.md) and will grow alongside dedicated runbooks/policies under [`docs/`](docs/).

## Network Schema
- [`network/vlan-plan.yaml`](network/vlan-plan.yaml) defines the 10.23.0.0/16 CIDR segmented into management, services, storage, and DMZ VLANs plus internal DNS defaults.
- [`network/proxmox-bridges.yaml`](network/proxmox-bridges.yaml) captures the bridge configuration (`vmbr0`) and LXC defaults (unprivileged with nesting) expected on each node.
- Caddy reverse-proxy templates reside in [`network/caddy/Caddyfile.tmpl`](network/caddy/Caddyfile.tmpl) and should be customised per service FQDN.

## Automation Approach
The repository layers several automation tools:
- **Packer** builds hardened golden images via the files under `images/golden/`.
- **Ansible** roles and playbooks in `ansible/` manage bootstrap, core services, catalogue workloads, and backup verification.
- **GitOps runner** (`ci/gitops-pull.sh` with corresponding systemd units) enforces pull-based reconciliation.
- **CLI wrapper** (`cli/ralf.sh`) offers friendly entrypoints for recurring workflows.
- **Supporting scripts** include:
  - [`scripts/lisa_build_lxc.sh`](scripts/lisa_build_lxc.sh) to prepare LXC templates prior to Ansible runs (callable from Semaphore UI or Foreman hooks).
  - [`scripts/ralf-installer.sh`](scripts/ralf-installer.sh) to collect install-time variables, generate age keys, and optionally launch bootstrap/apply flows.
  - [`scripts/ralf-net-scan.sh`](scripts/ralf-net-scan.sh) to inventory the declared homelab CIDR on a schedule and drop results in `reports/scans/`.
- **OpenTofu/Terraform** modules can be added under `automation/` (to be created) for declarative Proxmox resource management.

## Key Services
Core services deployed through `ansible/playbooks/deploy-core.yaml`:
- **DNS** – local authoritative servers for `homelab.lan`.
- **Caddy** – ACME-enabled reverse proxy enforcing HTTPS ingress.
- **Auth** – central identity provider (e.g., Authelia/Keycloak).
- **Monitoring** – metrics, alerts, dashboards, anomaly detection.
- **Backups** – orchestrated encrypted backup service with restore probes.
- **Matrix Synapse Backbone** – delivered via `ansible/playbooks/deploy-matrix.yaml` with PostgreSQL storage, Matrix bot bootstrap, and Caddy ingress. End-to-end encryption remains disabled by default to simplify bot automation flows.

Service catalogue (deployable via `ansible/playbooks/deploy-services.yaml`):
- Vaultwarden
- Mail gateway/services
- Home Assistant

Additional services, GPU workloads, and AI multi-agent platforms will be documented in `docs/runbooks/` and `docs/policies/` as they are added.

## Repository Structure
```
ralf/
├── README.md
├── Makefile
├── architecture.yaml
├── inventory/
│   ├── hosts.yaml
│   └── groups.yaml
├── network/
│   ├── vlan-plan.yaml
│   ├── proxmox-bridges.yaml
│   └── caddy/
│       └── Caddyfile.tmpl
├── images/
│   └── golden/
│       ├── lxc-debian-bookworm.pkr.hcl
│       ├── vm-debian-bookworm.pkr.hcl
│       └── vars.pkr.hcl.example
├── ansible/
│   ├── inventories -> ../inventory
│   ├── playbooks/
│   │   ├── site.yaml
│   │   ├── bootstrap-proxmox.yaml
│   │   ├── deploy-core.yaml
│   │   ├── deploy-services.yaml
│   │   ├── deploy-matrix.yaml
│   │   └── backups-verify.yaml
│   └── roles/
│       ├── base/
│       ├── dns/
│       ├── caddy/
│       ├── auth/
│       ├── backups/
│       ├── monitoring/
│       ├── mail/
│       ├── vaultwarden/
│       ├── homeassistant/
│       └── matrix_synapse/
├── secrets/
│   └── .sops.yaml
├── ci/
│   ├── gitops-runner.service
│   ├── gitops-runner.timer
│   ├── gitops-pull.sh
│   └── lint.yaml
├── portal/
│   ├── README.md
│   ├── ui/
│   └── api/
├── cli/
│   ├── ralf.sh
│   └── completions/
├── docs/
│   ├── README.md
│   ├── runbooks/
│   └── policies/
├── scripts/
│   ├── hardening.sh
│   ├── lisa_build_lxc.sh
│   ├── ralf-installer.sh
│   └── ralf-net-scan.sh
├── reports/
│   └── scans/
└── .gitignore
```

## Prerequisites
- Proxmox VE host(s) with VLAN tagging and ZFS pools (`fast`, `bulk`, `secure`) provisioned.
- Administrative workstation with Git, Ansible, Packer, SOPS/age, and OpenTofu (optional) installed.
- Helper tooling for automation scripts: `yq`, `jq`, `nmap`, and `age-keygen`.
- SSH key material staged on each Proxmox node under `/root/keys/` for passwordless automation.
- Age key pair stored locally and referenced by [`secrets/.sops.yaml`](secrets/.sops.yaml).
- Valid domain/ACME email for Caddy plus upstream DNS forwarders.
- Optional: Foreman and Semaphore UI instances for orchestration, plus local AI agents for observability/remediation tasks.

## High-Level Setup Steps
1. **Clone & Configure** – Fork/clone the repo, copy `images/golden/vars.pkr.hcl.example` to `vars.pkr.hcl`, and adjust `inventory/` host variables, VLAN definitions, and `architecture.yaml` metadata for your environment.
2. **Run the Installer** – Execute `scripts/ralf-installer.sh` to answer baseline questions (domain, VLAN IDs, Matrix admin/bot, backup targets, notifications) and generate age keys plus encrypted vars under `vars/`.
3. **Prepare LXC Templates** – Run `scripts/lisa_build_lxc.sh` (directly or via Semaphore UI) to seed required templates on Proxmox.
4. **Generate Golden Images** – Execute `make images` (or `cli/ralf.sh images`) to build LXC/VM templates using Packer with nightly security updates.
5. **Bootstrap Proxmox** – Run `make bootstrap` to apply network bridges, install the GitOps runner, register the network scanner service/timer, and stage automation prerequisites.
6. **Deploy Core Services** – Apply `make apply CORE_ONLY=true` or `cli/ralf.sh deploy-core` to provision DNS, Caddy, authentication, monitoring, and backups.
7. **Deploy Matrix Backbone** – Run `make deploy-matrix` (or `ansible/playbooks/deploy-matrix.yaml`) to configure PostgreSQL-backed Synapse, register the admin user, and wire Caddy ingress.
8. **Deploy Service Catalogue** – Trigger `cli/ralf.sh deploy-services` once core services are healthy to roll out Vaultwarden, Mail, and Home Assistant.
9. **Validate Backups** – Schedule `make verify-backups` or run `ansible/playbooks/backups-verify.yaml` manually for restore spot checks.
10. **Operate via GitOps** – Ensure `ci/gitops-pull.sh` and the accompanying timers (GitOps + network scanner) pull changes every five minutes and enforce drift remediation.

## Configuration & Documentation Pointers
- Detailed service variables live alongside each Ansible role under `ansible/roles/<service>/`.
- Operational runbooks, onboarding checklists, and policies will be expanded under `docs/runbooks/` and `docs/policies/`.
- Portal/UI specifications and API definitions reside in `portal/` and will host the self-service catalogue.
- Network scan reports are archived under `reports/scans/` for auditing and trend analysis.
- Matrix-specific configuration defaults live under `ansible/roles/matrix_synapse/` and will evolve as bots and rooms expand.
- Future GPU/AI integrations will include additional automation modules in `automation/` (planned) and accompanying documentation updates.

Contributions should keep the manifest, inventories, and documentation aligned so the repository remains the authoritative definition of the RALF platform.
