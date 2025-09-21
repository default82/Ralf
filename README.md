# Ralf

## Project Purpose
Ralf documents the home lab virtualization cluster that hosts mixed workloads across
containerized, virtualized, and bare-metal services. The goal of the project is to
capture the infrastructure topology, automation entrypoints, and operational
runbooks so the environment can be rebuilt or expanded without reverse engineering
legacy hosts.

## Hardware Layout
The lab is organized around three Proxmox VE nodes with distinct roles:

- **ralf-prox01** – primary compute node for production LXC containers and VMs.
- **ralf-prox02** – secondary compute node that balances development and staging
  workloads, and provides failover capacity.
- **ralf-prox-storage** – storage-focused node with HBA passthrough for ZFS pools and
  backup repositories.

### Storage Pools
- `tank` – mirrored SSD pool dedicated to low-latency virtual disks.
- `bulk` – RAID-Z2 HDD pool for archival data, media, and nightly backups.
- `vm-backups` – external iSCSI target mounted on all nodes for Proxmox scheduled
  backups and ISO templates.

## Network Schema
The cluster uses a segmented layer-2 design:

- **Management VLAN (10.10.10.0/24)** – Proxmox GUI/API, IPMI, and out-of-band access.
- **Production VLAN (10.20.20.0/24)** – tenant services exposed to the LAN and
  reverse proxy.
- **Storage VLAN (10.30.30.0/24)** – ZFS replication, NFS/SMB, and backup traffic.
- **Lab VLAN (10.40.40.0/24)** – disposable testing workloads and nested
  virtualization.

Inter-VLAN routing is provided by the core router, while Proxmox bridges (vmbr0,
vmbr1, vmbr2) tag traffic to the appropriate networks. A WireGuard tunnel is used
for secure remote administration when offsite.

## Automation Approach
Infrastructure-as-code keeps the environment reproducible:

- **Proxmox provisioning** – The `scripts/lisa_build_lxc.sh` helper script prepares
  LXC templates, sets resource quotas, and registers them with the cluster via the
  Proxmox API.
- **Configuration management** – Ansible playbooks (tracked in the `ansible/`
  directory of the automation toolkit) apply host-specific roles, manage packages,
  and push secrets from Vault.
- **Credential distribution** – Each hypervisor maintains a `/root/keys/` folder
  populated during bootstrap with SSH public keys and cloud-init snippets so new
  nodes inherit the correct access controls.

## Key Services
- **Reverse proxy stack** (Caddy + Cloudflare tunnel) routing inbound HTTPS
  traffic.
- **Observability** (Prometheus, Grafana, Loki) capturing metrics, logs, and
  alerts.
- **CI/CD runners** for container image builds and infrastructure validation.
- **Home automation** services (Home Assistant, Zigbee2MQTT) housed in hardened
  LXCs on the production VLAN.
- **Data services** including PostgreSQL, MinIO, and an NFS gateway backed by the
  `bulk` pool.

## Prerequisites
Before reproducing the environment, ensure the following prerequisites are met:

1. Access to Proxmox VE 8.x nodes with nested virtualization enabled and IPMI
   configured on the management VLAN.
2. A workstation with Bash, Ansible, and the Proxmox `pve-cli` utilities installed.
3. SSH connectivity to each node using the keys staged in `/root/keys/`.
4. The automation toolkit cloned locally, including the `scripts/lisa_build_lxc.sh`
   script and supporting Ansible inventories.
5. Secrets and certificates exported from Vault to the secure secrets store defined
   in the automation playbooks.

## High-Level Setup Steps
1. **Prepare Proxmox nodes** – Install Proxmox VE, configure networking bridges for
   each VLAN, and attach storage pools (`tank`, `bulk`, `vm-backups`).
2. **Bootstrap access** – Copy the provisioning SSH keys into `/root/keys/` on each
   node, verify passwordless login, and configure IPMI users.
3. **Run base automation** – Execute `scripts/lisa_build_lxc.sh` to create LXC
   templates, then apply the Ansible bootstrap playbook to install core packages
   and enable monitoring agents.
4. **Deploy services** – Use the service-specific playbooks (e.g.,
   `ansible/site.yml`) to launch the reverse proxy, observability stack, and data
   services. Apply Terraform or Proxmox API calls where necessary for VM
   orchestration.
5. **Validate observability and backups** – Confirm metrics ingestion, dashboard
   availability, and backup jobs targeting `vm-backups`.

## Detailed Configurations & Future Expansion
Detailed service configurations, including Proxmox host vars, playbook roles, and
container manifests, live in the `docs/` and `ansible/` directories of the broader
infrastructure repository. This README links the high-level topology; deep dive
configuration guides, secrets management workflows, and day-2 operations will be
tracked there.

Planned expansions include:

- **GPU-enabled node** for AI and ML workloads, integrating NVIDIA GPUs with
  passthrough-ready Proxmox templates.
- **Dedicated AI workload stack** leveraging the GPU node for model training,
  inference services, and dataset storage optimizations.
- **Disaster recovery runbooks** for replicating the cluster to an offsite Proxmox
  backup server.

As these components are implemented, detailed documentation will be added to the
`docs/expansion/` section alongside the automation artifacts.
