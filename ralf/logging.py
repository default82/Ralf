"""Zentrale Logging-Konfiguration für Ralf."""
from __future__ import annotations

import logging
import logging.handlers
import os
from pathlib import Path

from .config import LoggingConfig


DEFAULT_LOG_FORMAT = "%(asctime)s [%(levelname)s] %(name)s - %(message)s"


def configure_logging(config: LoggingConfig) -> None:
    """Initialisiert das Logging gemäß der Konfiguration."""
    if not config.enabled:
        logging.disable(logging.CRITICAL)
        return

    log_path = Path(config.log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    root_logger = logging.getLogger()
    root_logger.setLevel(getattr(logging, config.level.upper(), logging.INFO))
    root_logger.handlers.clear()

    formatter = logging.Formatter(DEFAULT_LOG_FORMAT)

    file_handler = logging.handlers.RotatingFileHandler(
        log_path,
        maxBytes=config.max_bytes,
        backupCount=config.backup_count,
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    root_logger.addHandler(file_handler)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)

    if config.release_mode:
        # In der Release-Version kann das Logging über eine Umgebungsvariable deaktiviert werden
        release_flag = os.getenv("RALF_RELEASE_LOGGING", "on").lower()
        if release_flag in {"off", "0", "false"}:
            logging.getLogger(__name__).info("Logging wurde für den Release-Betrieb deaktiviert")
            logging.disable(logging.CRITICAL)

    logging.getLogger(__name__).debug("Logging initialisiert: Datei=%s, Level=%s", log_path, config.level)
