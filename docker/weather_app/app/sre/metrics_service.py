# sre/metrics_service.py
from prometheus_client import Counter, Histogram, Gauge

# ---------------- Counters ----------------
weather_requests_total = Counter(
    "weather_requests_total",
    "Total number of weather requests",
    ["status_code"]
)
preferences_saved_total = Counter(
    "preferences_saved_total",
    "Total number of preferences saved"
)
failed_weather_requests_total = Counter(
    "failed_weather_requests_total",
    "Total failed weather API requests",
    ["status_code"]
)

# ---------------- Histograms ----------------
request_latency_seconds = Histogram(
    "request_latency_seconds",
    "Time spent processing requests",
    ["endpoint"]
)

# ---------------- Gauges ----------------
active_users = Gauge("active_users", "Number of currently active users")
cpu_percent = Gauge("cpu_percent", "CPU usage percent")
memory_percent = Gauge("memory_percent", "Memory usage percent")
disk_percent = Gauge("disk_percent", "Disk usage percent")
