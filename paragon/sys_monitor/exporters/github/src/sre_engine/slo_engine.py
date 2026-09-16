# NOTE: legacy / unused in runtime worker (SQLite is source of truth)
from dataclasses import dataclass


@dataclass
class ErrorBudgetState:

    total: int = 0
    good: int = 0

    def record(self, success: bool):
        self.total += 1
        if success:
            self.good += 1

    def success_rate(self):
        if self.total == 0:
            return 1.0
        return self.good / self.total
