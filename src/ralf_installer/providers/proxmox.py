"""Helpers that emulate Proxmox provisioning steps."""

from __future__ import annotations

from typing import Iterable, Mapping


def execute(operation: str, options: dict[str, object], dry_run: bool) -> None:
    """Execute a proxmox operation."""

    operations = {
        "create_lxc": _create_lxc,
        "create_vm": _create_vm,
        "configure_network": _configure_network,
        "run_commands": _run_commands,
    }

    try:
        handler = operations[operation]
    except KeyError as exc:  # pragma: no cover - defensive
        raise RuntimeError(f"Unsupported proxmox operation '{operation}'") from exc

    handler(options, dry_run=dry_run)


def _create_lxc(options: Mapping[str, object], *, dry_run: bool) -> None:
    vmid = _require(options, "vmid")
    node = _require(options, "node")
    template = _require(options, "template")
    hostname = _require(options, "hostname")
    cores = options.get("cores", 2)
    memory = options.get("memory", 2048)
    disk_size = options.get("disk_size_gb", 20)
    storage = options.get("storage", "local-lvm")

    _emit(
        dry_run,
        "proxmox",
        "create_lxc",
        f"vmid={vmid} node={node} template={template} hostname={hostname} "
        f"cores={cores} memory={memory}MB disk={disk_size}GiB storage={storage}",
    )


def _create_vm(options: Mapping[str, object], *, dry_run: bool) -> None:
    vmid = _require(options, "vmid")
    node = _require(options, "node")
    iso = _require(options, "iso")
    hostname = _require(options, "hostname")
    cores = options.get("cores", 4)
    sockets = options.get("sockets", 1)
    memory = options.get("memory", 4096)
    disk_size = options.get("disk_size_gb", 40)
    storage = options.get("storage", "local-lvm")

    _emit(
        dry_run,
        "proxmox",
        "create_vm",
        f"vmid={vmid} node={node} iso={iso} hostname={hostname} cores={cores} "
        f"sockets={sockets} memory={memory}MB disk={disk_size}GiB storage={storage}",
    )


def _configure_network(options: Mapping[str, object], *, dry_run: bool) -> None:
    vmid = _require(options, "vmid")
    networks = options.get("networks", [])
    if not isinstance(networks, Iterable):
        raise RuntimeError("'networks' option must be an iterable")

    for network in networks:
        if not isinstance(network, Mapping):
            raise RuntimeError("Network definitions must be mappings")
        name = _require(network, "name")
        ip = _require(network, "ip")
        gateway = network.get("gateway")
        bridge = network.get("bridge", "vmbr0")
        description = f"vmid={vmid} iface={name} bridge={bridge} ip={ip}"
        if gateway:
            description += f" gw={gateway}"
        _emit(dry_run, "proxmox", "configure_network", description)


def _run_commands(options: Mapping[str, object], *, dry_run: bool) -> None:
    vmid = _require(options, "vmid")
    commands = options.get("commands", [])
    if not isinstance(commands, Iterable):
        raise RuntimeError("'commands' option must be iterable")
    for command in commands:
        if not isinstance(command, str):
            raise RuntimeError("Each command must be a string")
        _emit(dry_run, "proxmox", "run_command", f"vmid={vmid} cmd={command}")


def _require(options: Mapping[str, object], key: str) -> object:
    try:
        value = options[key]
    except KeyError as exc:  # pragma: no cover - defensive
        raise RuntimeError(f"Missing required option '{key}'") from exc
    if value in (None, ""):
        raise RuntimeError(f"Option '{key}' must not be empty")
    return value


def _emit(dry_run: bool, provider: str, operation: str, description: str) -> None:
    prefix = "DRY-RUN" if dry_run else "EXEC"
    print(f"[{prefix}] {provider}:{operation} {description}")
