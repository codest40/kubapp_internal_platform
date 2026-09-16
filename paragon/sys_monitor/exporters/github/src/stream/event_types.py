from dataclasses import dataclass
from typing import Dict, Any
from datetime import datetime

@dataclass
class GitHubEvent:
    event_type: str
    repo: str
    payload: Dict[str, Any]
    timestamp: datetime

