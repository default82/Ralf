"""Installer package for the R.A.L.F. homelab ecosystem."""

from importlib import metadata

__all__ = ["__version__"]


def __getattr__(name: str):
    if name == "__version__":
        return metadata.version("ralf-installer")
    raise AttributeError(name)
