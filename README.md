# RALF – Reproducible Automation for Lab Facilities

RALF is an infrastructure-as-code blueprint for running a service-rich homelab on Proxmox VE with an LXC-first approach. The repository targets hardware-agnostic installations and focuses on reproducible automation, GitOps operations, and self-service tooling so that any Proxmox host can be promoted into the lab with minimal manual steps.

## Project Goals
- **LXC-first orchestration** with optional VMs for storage controllers or special workloads.
- **GitOps pull pipeline** providing idempotent deployments and policy enforcement.
- **Autonomous services** such as local DNS, reverse proxy, observability, and backups.
- **Governance and UX** through a portal, CLI tooling, and documented runbooks.

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
│       └── homeassistant/
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
│   └── hardening.sh
└── .gitignore
```

Each directory aligns with the deliverables defined in `architecture.yaml`, giving operators a single source of truth for network, storage, and automation standards.

## Architecture Manifest
The [`architecture.yaml`](architecture.yaml) file captures the guiding principles, service roles, policy flags, storage classes, and GitOps runner configuration. Update this manifest when introducing new services or changing governance requirements so downstream tooling (portal, documentation generators, CI validation) stays in sync.

## Network & Storage Blueprints
- [`network/vlan-plan.yaml`](network/vlan-plan.yaml) defines the 10.23.0.0/16 address space segmented into management, services, storage, and DMZ VLANs along with internal DNS defaults and Caddy ingress policy.
- [`network/proxmox-bridges.yaml`](network/proxmox-bridges.yaml) maps Proxmox bridge interfaces and LXC defaults (unprivileged containers with nesting).
- ZFS storage tiers (fast, bulk, secure) plus backup encryption expectations are documented in the architecture manifest.

## Automation Toolchain
- **Packer Golden Images** – Files under `images/golden/` generate hardened Debian Bookworm LXC templates and VM images for Proxmox. Customize `vars.pkr.hcl.example` with real API credentials and keys or copy it to `vars.pkr.hcl` for local overrides.
- **Ansible Configuration Management** – Playbooks in `ansible/playbooks/` orchestrate bootstrap, core services (DNS, Caddy, Auth, Monitoring, Backups), service catalog deployments (Vaultwarden, Mail, Home Assistant), and backup verification.
- **GitOps Pull Runner** – `ci/gitops-pull.sh` paired with the `gitops-runner.service` and `gitops-runner.timer` units polls the repository every five minutes (per `architecture.yaml`) to run `make check` and `make apply` idempotently.
- **Secrets Management** – `secrets/.sops.yaml` enforces SOPS/age encryption for sensitive Ansible data. Store age keys in `secrets/age-keys/` (ignored from Git).
- **CLI & Portal** – `cli/ralf.sh` provides quick entrypoints for bootstrap, image builds, deployments, and health checks, while the `portal/` directory hosts the UI/API scaffold for self-service operations.

## Prerequisites
- Proxmox VE host(s) with VLAN tagging configured and ZFS pools for fast, bulk, and secure storage tiers.
- Administrative workstation with Ansible, Packer, Git, and SOPS installed.
- SSH key pairs staged on each Proxmox node in `/root/keys/` for passwordless automation.
- Age key pair for SOPS encryption stored locally and referenced via `secrets/.sops.yaml`.
- Valid domain and ACME email for Caddy (`admin@homelab.lan` placeholder) plus upstream DNS forwarders.

## Quickstart Workflow
1. **Clone & Configure** – Fork this repository, copy `images/golden/vars.pkr.hcl.example` to `vars.pkr.hcl`, and update inventory files with real IPs, domain, ACME email, and secrets.
2. **Generate Golden Images** – Run `make images` (or `cli/ralf.sh images`) to build the LXC and VM templates on your target Proxmox node.
3. **Bootstrap Proxmox** – Execute `make bootstrap` to apply bridge definitions, install the GitOps runner, and seed automation dependencies.
4. **Deploy Core Services** – Run `make apply` (or `cli/ralf.sh deploy-core`) to provision DNS, Caddy, authentication, monitoring, and backup orchestration in LXCs.
5. **Deploy Service Catalog** – Trigger `cli/ralf.sh deploy-services` once core services are healthy to launch Vaultwarden, Mail, and Home Assistant stacks.
6. **Validate Backups** – Schedule `make verify-backups` or use the GitOps runner to execute `ansible/playbooks/backups-verify.yaml` for automated restore tests.
7. **Operate via GitOps** – Let the systemd timer execute `ci/gitops-pull.sh`, or run it manually to ensure drift detection and remediation.

## Future Enhancements
Roadmap items tracked in `docs/` include:
- GPU-enabled Proxmox node for AI workloads and multi-agent automation assistance.
- Enhanced observability with anomaly detection and SLO dashboards.
- Extended portal capabilities (service catalog, onboarding checks, signed image listings).
- Additional runbooks for break-glass access, nightly security updates, and immutable dataset maintenance.

Contributions should update the manifest, inventories, and documentation to maintain the repository as the authoritative description of the RALF platform.
