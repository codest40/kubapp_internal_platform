# app/sre/system_health.py
import os
import sys
from fastapi import APIRouter, status
from fastapi.responses import JSONResponse
import psutil

sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from logger import logger
from send_alert import send_alert
from sre.metrics_service import cpu_percent, memory_percent, disk_percent

router = APIRouter()

# Thresholds (can be adjusted via env vars)
CPU_THRESHOLD = float(os.getenv("SYS_CPU_THRESHOLD", 85))       # percent
MEM_THRESHOLD = float(os.getenv("SYS_MEM_THRESHOLD", 90))       # percent
DISK_THRESHOLD = float(os.getenv("SYS_DISK_THRESHOLD", 90))     # percent
MONITOR_PATH = os.getenv("SYS_DISK_PATH", "/tmp")               # path to monitor disk

@router.get("/health/system")
def system_health():
    """
    System-level health probe.
    Checks CPU, memory, and disk usage.
    Triggers alert if any thresholds are breached.
    """
    cpu = psutil.cpu_percent(interval=0.5)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage(MONITOR_PATH)

    cpu_percent.set(cpu)
    memory_percent.set(mem.percent)
    disk_percent.set(disk.percent)
    router = APIRouter()

    alerts = []

    if cpu > CPU_THRESHOLD:
        alerts.append(f"High CPU usage: {cpu:.1f}% (>{CPU_THRESHOLD}%)")
    if mem.percent > MEM_THRESHOLD:
        alerts.append(f"High Memory usage: {mem.percent:.1f}% (>{MEM_THRESHOLD}%)")
    if disk.percent > DISK_THRESHOLD:
        alerts.append(f"High Disk usage ({MONITOR_PATH}): {disk.percent:.1f}% (>{DISK_THRESHOLD}%)")

    if alerts:
        message = " | ".join(alerts)
        logger.error(f"System Health WARNING ❌: {message}")
        send_alert(f"[SYSTEM ALERT] {message}", use_fallback_db=False)
        status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        health_status = "unhealthy"
    else:
        logger.info(f"System Health OK ✅: CPU={cpu:.1f}%, Mem={mem.percent:.1f}%, Disk={disk.percent:.1f}%")
        message = "System OK ✅"
        status_code = status.HTTP_200_OK
        health_status = "healthy"

    return JSONResponse(
        status_code=status_code,
        content={
            "status": health_status,
            "cpu_percent": cpu,
            "memory_percent": mem.percent,
            "disk_percent": disk.percent,
            "message": message
        }
    )
