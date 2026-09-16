class SLOState:

    def __init__(self):
        self.total = 0
        self.success = 0

    def record(self, success: bool):
        self.total += 1
        if success:
            self.success += 1

    def success_rate(self):
        if self.total == 0:
            return 1.0
        return self.success / self.total
