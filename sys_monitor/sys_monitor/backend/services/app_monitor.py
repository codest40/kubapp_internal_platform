import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


STATE_FILE = (
    Path(__file__).resolve().parents[1]
    / "state"
    / "app_endpoints.json"
)

REQUEST_TIMEOUT = 5


def load_app_endpoints():
    """Load registered application endpoints from the state file."""

    if not STATE_FILE.is_file():
        raise FileNotFoundError(
            f"Application endpoint registry not found: {STATE_FILE}"
        )

    with STATE_FILE.open() as file:
        data = json.load(file)

    if not isinstance(data, dict):
        raise ValueError(
            "Application endpoint registry must contain a JSON object"
        )

    apps = data.get("apps")

    if not isinstance(apps, dict):
        raise ValueError(
            "Application endpoint registry must contain an apps object"
        )

    return apps


def check_endpoint(url):
    """
    Any 2xx response is considered successful.
    """

    if not isinstance(url, str) or not url.strip():
        return {
            "status": "unknown",
            "status_code": None,
            "error": "Endpoint URL is missing",
        }

    request = Request(
        url,
        headers={
            "User-Agent": "sys_monitor/0.1.0",
            "Accept": "application/json",
        },
        method="GET",
    )

    try:
        with urlopen(
            request,
            timeout=REQUEST_TIMEOUT,
        ) as response:
            status_code = response.status

            return {
                "status": (
                    "healthy"
                    if 200 <= status_code < 300
                    else "unhealthy"
                ),
                "status_code": status_code,
                "error": None,
            }

    except HTTPError as exc:
        return {
            "status": "unhealthy",
            "status_code": exc.code,
            "error": f"HTTP {exc.code}",
        }

    except (URLError, TimeoutError, OSError) as exc:
        return {
            "status": "unhealthy",
            "status_code": None,
            "error": str(exc),
        }


async def check_app(app_name, endpoints, environment=None):
    """Check readiness first, then liveness when configured."""

    if not isinstance(endpoints, dict):
        return {
            "name": app_name,
            "status": "unknown",
            "readiness": None,
            "liveness": None,
            "error": "Application endpoint configuration must be an object",
        }

    readiness_url = endpoints.get("readiness")
    liveness_url = endpoints.get("liveness")

    readiness_result = None
    liveness_result = None

    if readiness_url:
        readiness_result = await asyncio.to_thread(
            check_endpoint,
            readiness_url,
        )

    if liveness_url:
        liveness_result = await asyncio.to_thread(
            check_endpoint,
            liveness_url,
        )

    if readiness_url:
        if readiness_result["status"] != "healthy":
            overall_status = "unhealthy"
        elif liveness_url and liveness_result["status"] != "healthy":
            overall_status = "unhealthy"
        else:
            overall_status = "healthy"
    elif liveness_url:
        overall_status = liveness_result["status"]
    else:
        overall_status = "unknown"

    return {
        "name": app_name,
        "url": endpoints.get("url"),
        "status": overall_status,
        "readiness": (
            {
                "url": readiness_url,
                **readiness_result,
            }
            if readiness_result is not None
            else None
        ),
        "liveness": (
            {
                "url": liveness_url,
                **liveness_result,
            }
            if liveness_result is not None
            else None
        ),
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }



async def get_application_status():
    """Return monitoring results for all registered applications."""
    data = json.loads(STATE_FILE.read_text())

    if not isinstance(data, dict):
        raise ValueError(
            "Application endpoint registry must contain a JSON object"
        )

    apps = data.get("apps")
    if not isinstance(apps, dict):
        raise ValueError(
            "Application endpoint registry must contain an apps object"
        )

    environment = data.get("env")

    results = await asyncio.gather(
        *[
            check_app(app_name, endpoints, environment)
            for app_name, endpoints in apps.items()
        ]
    )

    return {
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "environment": environment,
        "total": len(results),
        "healthy": sum(
            result["status"] == "healthy"
            for result in results
        ),
        "unhealthy": sum(
            result["status"] == "unhealthy"
            for result in results
        ),
        "unknown": sum(
            result["status"] == "unknown"
            for result in results
        ),
        "applications": results,
    }
