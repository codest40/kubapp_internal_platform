# app/sre/logger.py
import logging
import os
from logging.handlers import RotatingFileHandler

# Decide log path based on environment
if os.getenv("CI", "GITHUB").lower() in ("true", "yes", "1"):
    LOG_PATH = "/tmp/edgepaas/app/logger.log"
else:
    # Expand $HOME for local/development
    LOG_PATH = os.path.join(os.path.expanduser("~"), "tmp", "edgepaas", "logs", "logger.log")

# Ensure directory exists
os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)

# Log level from env or default INFO
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

# Create logger
logger = logging.getLogger("edgepaas")
logger.setLevel(LOG_LEVEL)

# Formatter with timestamp
formatter = logging.Formatter(
    fmt="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# File handler with rotation
file_handler = RotatingFileHandler(
    LOG_PATH,
    maxBytes=5 * 1024 * 1024,  # 5 MB
    backupCount=5,
)
file_handler.setFormatter(formatter)

# Console handler
console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)

# Add handlers only once
if not logger.handlers:
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)

# Test print
logger.debug(f"Logger initialized. Logging to {LOG_PATH}")
