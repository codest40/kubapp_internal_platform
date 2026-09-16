import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone

def required_env(name):
    value = os.environ.get(name, "").strip()

    if not value:
        print(f"{name} is required")
        sys.exit(1)
    return value

ENV = required_env("ENV")
RUN_ID = required_env("RUN_ID")
WORKFLOW = required_env("WORKFLOW_ID")
STATE = required_env("MANIFEST")

state_path = Path(STATE)
state_path.mkdir(parents=True, exist_ok=True)
state_file = state_path / "current.json"

data = {
    "env": ENV,
    "run_id": RUN_ID,
    "workflow": WORKFLOW,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}

with state_file.open("w", encoding="utf-8") as file:
    json.dump(data, file, indent=2)
    file.write("\n")

print(f"file created! at {state_file}")
