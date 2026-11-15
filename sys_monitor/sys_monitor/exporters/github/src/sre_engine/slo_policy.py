from dataclasses import dataclass
from typing import Literal


# ============================================================
# SLI SOURCES (REAL SRE CONCEPT)
# ============================================================

SLISource = Literal[
    "workflow_run_success_rate"
]


# ============================================================
# SLO POLICY (DECLARATIVE CONTRACT)
# ============================================================

@dataclass
class SLOPolicy:
    """
    Defines WHAT we measure, NOT HOW we compute it.

    This is a declarative SRE contract.
    """

    name: str

    # SLO target (e.g. 0.95 = 95% success rate)
    success_threshold: float = 0.95

    # What signal defines reliability
    sli_source: SLISource = "workflow_run_success_rate"

    # Evaluation window in seconds (used by worker)
    window_seconds: int = 300

    def is_valid(self) -> bool:
        """
        Basic sanity checks for policy correctness.
        """
        return (
            0.0 < self.success_threshold <= 1.0
            and self.window_seconds > 0
        )
