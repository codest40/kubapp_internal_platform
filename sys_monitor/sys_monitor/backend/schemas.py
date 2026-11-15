from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


# ------------------------------------------------------------------
# Common enums
# ------------------------------------------------------------------

class HealthStatus(str, Enum):
    HEALTHY = "healthy"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"


class Severity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


# ------------------------------------------------------------------
# Common models
# ------------------------------------------------------------------

class Schema(BaseModel):
    """Base model shared by API schemas."""

    model_config = ConfigDict(
        extra="forbid",
        use_enum_values=True,
    )


class Observation(Schema):
    """A single monitoring observation."""

    name: str = Field(
        description="Name of the observed signal."
    )
    status: HealthStatus
    observed_at: datetime = Field(
        description="Time the observation was collected."
    )
    source: str = Field(
        description="System that produced the observation."
    )
    message: str | None = None
    value: float | int | str | bool | None = None
    unit: str | None = None


class HealthCheck(Schema):
    """Result of an individual health check."""

    name: str
    status: HealthStatus
    message: str | None = None
    checked_at: datetime
    source: str | None = None
    duration_ms: float | None = Field(
        default=None,
        ge=0,
    )


class ResourceReference(Schema):
    """Reference to a related infrastructure resource."""

    kind: str
    name: str
    namespace: str | None = None
    identifier: str | None = None


class Event(Schema):
    """Normalized event or alert."""

    id: str
    title: str
    message: str | None = None
    severity: Severity
    source: str
    occurred_at: datetime
    resource: ResourceReference | None = None
    resolved: bool = False


# ------------------------------------------------------------------
# Standard API response models
# ------------------------------------------------------------------

class ResponseMeta(Schema):
    """Metadata accompanying an API response."""

    request_id: str | None = None
    generated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    count: int | None = Field(
        default=None,
        ge=0,
    )
    next_cursor: str | None = None


class ApiResponse(Schema):
    """Standard successful JSON response."""

    data: Any
    meta: ResponseMeta = Field(
        default_factory=ResponseMeta
    )


class ApiErrorDetail(Schema):
    """Structured error information."""

    code: str
    message: str
    details: dict[str, Any] | None = None


class ApiErrorResponse(Schema):
    """Standard JSON error response."""

    error: ApiErrorDetail
    meta: ResponseMeta = Field(
        default_factory=ResponseMeta
    )


# ------------------------------------------------------------------
# Applications
# ------------------------------------------------------------------

class ApplicationSummary(Schema):
    """Summary of a deployed application."""

    id: str
    name: str
    namespace: str | None = None
    status: HealthStatus
    observed_at: datetime | None = None
    version: str | None = None
    endpoint: str | None = None
    checks: list[HealthCheck] = Field(
        default_factory=list
    )
    resources: list[ResourceReference] = Field(
        default_factory=list
    )


class ApplicationDetail(ApplicationSummary):
    """Detailed application information."""

    description: str | None = None
    observations: list[Observation] = Field(
        default_factory=list
    )
    events: list[Event] = Field(
        default_factory=list
    )


# ------------------------------------------------------------------
# Controllers and GitOps
# ------------------------------------------------------------------

class ControllerSummary(Schema):
    """Summary of a GitOps or Kubernetes controller."""

    id: str
    name: str
    kind: str
    namespace: str | None = None
    status: HealthStatus
    observed_at: datetime | None = None
    message: str | None = None
    checks: list[HealthCheck] = Field(
        default_factory=list
    )
    resources: list[ResourceReference] = Field(
        default_factory=list
    )


# ------------------------------------------------------------------
# Kubernetes resources
# ------------------------------------------------------------------

class KubernetesResourceSummary(Schema):
    """Summary of a Kubernetes resource."""

    id: str
    name: str
    kind: str
    namespace: str | None = None
    status: HealthStatus
    observed_at: datetime | None = None
    api_version: str | None = None
    details: dict[str, Any] = Field(
        default_factory=dict
    )


# ------------------------------------------------------------------
# KUBAPP platform
# ------------------------------------------------------------------

class PlatformComponent(Schema):
    """Health summary of an internal platform component."""

    id: str
    name: str
    component_type: str
    status: HealthStatus
    observed_at: datetime | None = None
    message: str | None = None
    checks: list[HealthCheck] = Field(
        default_factory=list
    )
    observations: list[Observation] = Field(
        default_factory=list
    )


class PlatformSummary(Schema):
    """Overall platform health summary."""

    status: HealthStatus
    observed_at: datetime | None = None
    components: list[PlatformComponent] = Field(
        default_factory=list
    )
    active_events: int = Field(
        default=0,
        ge=0,
    )


# ------------------------------------------------------------------
# Databases
# ------------------------------------------------------------------

class DatabaseSummary(Schema):
    """Summary of a monitored database."""

    id: str
    name: str
    engine: str
    provider: str
    status: HealthStatus
    observed_at: datetime | None = None
    region: str | None = None
    checks: list[HealthCheck] = Field(
        default_factory=list
    )


class DatabaseDetail(DatabaseSummary):
    """Detailed database monitoring information."""

    engine_version: str | None = None
    instance_identifier: str | None = None
    availability_zone: str | None = None
    multi_az: bool | None = None
    observations: list[Observation] = Field(
        default_factory=list
    )
    events: list[Event] = Field(
        default_factory=list
    )



class MetricPoint(Schema):
    """A single timestamped metric value."""

    timestamp: datetime
    value: float


class MetricSeries(Schema):
    """A time series for a monitored signal."""

    name: str
    unit: str | None = None
    points: list[MetricPoint] = Field(
        default_factory=list
    )


class MetricsResponse(Schema):
    """Collection of metric time series."""

    resource_id: str
    series: list[MetricSeries] = Field(
        default_factory=list
    )
    start_time: datetime | None = None
    end_time: datetime | None = None
