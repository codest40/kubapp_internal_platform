import os
from pathlib import Path
import subprocess
import time
from datetime import datetime
import uuid

def get_latest_commit_id():
    id = subprocess.run(["git", "rev-parse", "HEAD"],
         capture_output=True, text=True)
    if id.returncode != 0:
        id = f"{uuid.uuid4().hex[:5]}-uuid"
    return id.stdout.strip()[:10]

def get_timestamp():
    TS = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    return TS

def get_root():
  b = subprocess.run(["git", "rev-parse", "--show-toplevel"],
      capture_output=True, text=True)
  if b.returncode != 0:
    return False
  return Path(b.stdout.strip())

def start_timer():
    return time.perf_counter()

print(get_root())
