# NOTE: legacy / unused in runtime worker (SQLite is source of truth)
from sre_engine.slo_policy import SLOPolicy


class SLOEvaluator:
    def __init__(self, policy: SLOPolicy):
        self.policy = policy

    def success_rate(self, success_count: int, total_count: int):
        if total_count == 0:
            return 1.0
        return success_count / total_count

    def is_breached(self, success_count: int, total_count: int):
        return self.success_rate(success_count, total_count) < self.policy.success_threshold

    def error_budget_remaining(self, success_count: int, total_count: int):
        sr = self.success_rate(success_count, total_count)
        return max(0.0, self.policy.success_threshold - sr)

    def burn_rate(self, success_count: int, total_count: int):
        sr = self.success_rate(success_count, total_count)

        if self.policy.success_threshold == 0:
            return 0.0

        return (1 - sr) / self.policy.success_threshold
