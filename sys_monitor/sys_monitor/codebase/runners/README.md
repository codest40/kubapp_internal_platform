# Runners

The `runners/` directory contains the execution engines responsible for
analyzing the KubApp codebase and converting the resulting evidence into
Prometheus metrics.

Each runner has a focused responsibility. Shared runtime and JSON
functionality is provided through `../lib/`, while generated evidence is
stored in the codebase `evidence/` directory.

## Structure

    runners/
    ├── architecture.sh
    ├── discovery.sh
    ├── drift.sh
    ├── filesystem.sh
    ├── filesystem_drift.sh
    ├── metrics.sh
    ├── security.sh
    ├── validation.sh
    ├── runner.sh
    │
    ├── Dockerfile
    ├── requirements.txt
    │
    └── src/
        └── app.py

## Runner Responsibilities

| Runner | Responsibility |
|---|---|
| `discovery.sh` | Discovers the repository and creates the canonical `inventory.json`. |
| `filesystem.sh` | Collects filesystem metadata for files known by the inventory. |
| `filesystem_drift.sh` | Compares the current filesystem snapshot with the previous snapshot. |
| `drift.sh` | Validates the current repository against the discovery inventory. |
| `architecture.sh` | Evaluates architectural and structural rules. |
| `security.sh` | Performs repository security checks. |
| `validation.sh` | Performs repository validation checks. |
| `metrics.sh` | Converts evidence into Prometheus metrics and calculates health scores. |
| `runner.sh` | Coordinates execution of the analysis runners. |
| `src/app.py` | Serves the generated Prometheus metrics over HTTP. |

## Shared Runtime

The runners load the shared libraries:

    ../lib/runtime.sh
    ../lib/json.sh

`runtime.sh` provides common execution functionality including:

- Project paths.
- Evidence paths.
- Logging.
- Runtime variables.
- Binary requirements.
- Path resolution.
- Common execution helpers.

`json.sh` provides shared JSON-generation helpers used by the analysis
engines.

This keeps runtime and JSON handling consistent across runners instead of
requiring each runner to implement its own version.

## Execution Flow

The runners follow a dependency-oriented execution model.

    Repository
        |
        v
    discovery.sh
        |
        v
    evidence/inventory.json
        |
        +-------------------+-------------------+
        |                   |                   |
        v                   v                   v
    filesystem.sh       drift.sh        architecture.sh
        |
        v
    filesystem.json
        |
        | previous snapshot
        v
    filesystem_older.json
        |
        v
    filesystem_drift.sh
        |
        +-------------------+
                            |
                   +--------+--------+
                   |                 |
                   v                 v
               security.sh     validation.sh
                   |                 |
                   +--------+--------+
                            |
                            v
                      Evidence JSON
                            |
                            v
                        metrics.sh
                            |
                            v
                     evidence/metrics.prom
                            |
                            v
                         src/app.py
                            |
                            v
                         /metrics
                            |
                            v
                        Prometheus

The important distinction is that the analysis runners generate evidence,
while `metrics.sh` consumes that evidence and converts it into
observability data.

# Discovery

`discovery.sh` establishes the canonical repository inventory.

It discovers repository objects including:

- Repository files.
- Shell scripts.
- Terraform roots.
- Terraform modules.
- GitHub Actions workflows.
- Dockerfiles.
- Kubernetes manifests.
- Helm files.
- Prometheus configuration.
- Argo CD configuration.
- Documentation.
- Application configuration.

The resulting inventory is written to:

    evidence/inventory.json

The inventory acts as the structural source of truth for runners that need
to reason about repository contents.

# Filesystem Collection

`filesystem.sh` consumes the discovery inventory and collects filesystem
metadata for the discovered files.

Collected metadata includes:

- Size.
- Inode.
- Permissions.
- UID.
- GID.
- Access time.
- Modification time.
- Change time.
- Birth time where supported.

The current snapshot is written to:

    evidence/filesystem.json

Before the new snapshot is created, the previous snapshot is preserved as:

    evidence/filesystem_older.json

The older snapshot provides the historical state required by
`filesystem_drift.sh`.

# Filesystem Drift

`filesystem_drift.sh` compares:

    evidence/filesystem_older.json

with:

    evidence/filesystem.json

and produces:

    evidence/filesystem_drift.json

It identifies changes including:

| Change | Metric |
|---|---|
| Modified files | `kubapp_filesystem_drift_modified` |
| Removed files | `kubapp_filesystem_drift_removed` |
| Size changes | `kubapp_filesystem_size_changed` |
| Permission changes | `kubapp_filesystem_permissions_changed` |
| UID changes | `kubapp_filesystem_uid_changed` |
| GID changes | `kubapp_filesystem_gid_changed` |
| Access-time changes | `kubapp_filesystem_access_changed` |
| Modification-time changes | `kubapp_filesystem_mtime_changed` |
| Change-time changes | `kubapp_filesystem_ctime_changed` |

The historical snapshot is used only as a comparison source. It is not
treated as active evidence.

# Inventory Drift

`drift.sh` performs structural drift validation against:

    evidence/inventory.json

It does not compare filesystem metadata snapshots.

Instead, it verifies that repository objects recorded during discovery
still exist.

Examples include:

- Missing files.
- Missing Terraform roots.
- Missing Terraform modules.
- Other repository objects represented by the inventory.

This gives KubApp two separate forms of drift detection:

| Runner | Purpose |
|---|---|
| `drift.sh` | Validates repository structure against the discovery inventory. |
| `filesystem_drift.sh` | Detects changes between filesystem metadata snapshots. |

The distinction is important: one validates whether expected repository
objects still exist, while the other detects changes to filesystem
attributes.

# Architecture

`architecture.sh` evaluates the repository against architectural rules.

Current checks include:

- Sample isolation.
- `sys_monitor` boundaries.
- Duplicate tooling.
- Infrastructure coupling.
- Workflow and script balance.

The runner produces structured JSON evidence containing its findings.

It also calculates an architecture score based on the detected issues.

The architecture evidence is later consumed by `metrics.sh`.

# Security

`security.sh` performs repository-level security checks and produces
structured findings.

Examples include:

- Plaintext credentials.
- Secret manifest locations.
- Other repository security violations implemented by the runner.

Security findings are consumed by `metrics.sh` when calculating the
security module score.

# Validation

`validation.sh` performs repository validation checks.

It produces structured findings for conditions such as:

- JavaScript syntax errors.
- Unknown file types.
- Other validation conditions implemented by the engine.

The resulting evidence is consumed by `metrics.sh` for validation scoring
and Prometheus metrics.

# Metrics

`metrics.sh` is the final processing stage of the analysis pipeline.

It reads the generated evidence and produces:

    evidence/metrics.prom

The metrics layer exposes information about:

- Module status.
- Files checked.
- Findings.
- Critical findings.
- Warnings.
- Errors.
- Finding types.
- Filesystem state.
- Filesystem drift.
- Repository inventory.
- Module scores.
- Overall platform health.

Examples include:

    kubapp_module_status{module="architecture"} 1
    kubapp_total_checked{module="architecture"} 224
    kubapp_findings_total{module="architecture"} 7
    kubapp_module_score{module="architecture"} 79

    kubapp_filesystem_total 348
    kubapp_filesystem_drift_modified 9
    kubapp_filesystem_drift_removed 0
    kubapp_filesystem_size_changed 2

    kubapp_platform_health 79

## Historical Evidence

The metrics engine ignores historical evidence files matching:

    *older*

For example:

    evidence/filesystem_older.json

is excluded from active metrics processing.

This prevents historical snapshots from being interpreted as independent
evidence sources and avoids duplicate metrics.

The rule is intentionally generic so additional historical snapshots can
be introduced without requiring changes to the metrics engine for every
new `*_older.json` file.

# Module Health

`metrics.sh` calculates a score for each analysis module.

| Module | Score Source |
|---|---|
| `architecture` | Architecture evidence score. |
| `security` | Critical and warning findings. |
| `validation` | Validation warnings. |
| `drift` | Successful inventory validation. |
| `filesystem` | Successful filesystem collection. |
| `filesystem_drift` | Successful filesystem drift analysis. |
| `discovery` | Inventory generation; excluded from platform health. |

The individual module scores are combined into:

    kubapp_platform_health

`discovery` is excluded from the platform-health average because its
purpose is to establish the repository inventory rather than evaluate
repository health.

# Metrics Service

`src/app.py` is a small Flask application responsible only for serving
the generated metrics.

It does not perform repository analysis.

The service exposes:

| Endpoint | Purpose |
|---|---|
| `/` | Basic service/status page. |
| `/health` | Service health endpoint. |
| `/metrics` | Prometheus metrics endpoint. |

The application reads the generated metrics file through:

    METRICS_FILE

If `METRICS_FILE` is not supplied, the default is:

    /evidence/metrics.prom

The final observability path is:

    Analysis Runners
          |
          v
      Evidence JSON
          |
          v
       metrics.sh
          |
          v
      metrics.prom
          |
          v
      Flask /metrics
          |
          v
       Prometheus

# Design Principles

## Single Discovery Source

`discovery.sh` establishes the repository inventory.

Downstream analysis engines use that inventory when repository structure
is required instead of independently redefining what exists in the
repository.

This creates a consistent structural view across the analysis system.

## Separate Evidence From Metrics

Analysis runners generate structured JSON evidence.

`metrics.sh` consumes that evidence and converts it into Prometheus
metrics.

    Runner
      |
      v
    Evidence
      |
      v
    Metrics

This keeps analysis logic separate from observability output.

## Separate Structural and Filesystem Drift

Structural drift and filesystem attribute changes are intentionally
handled by different runners.

Structural analysis follows:

    inventory.json
        |
        v
    drift.sh

Filesystem history follows:

    filesystem_older.json
        |
        v
    filesystem.json
        |
        v
    filesystem_drift.sh

Each runner therefore has one clear type of drift analysis.

## Historical Snapshots Are Not Active Evidence

Historical files exist for comparison only.

They are excluded from metrics processing so that previous snapshots do not
become duplicate evidence modules or duplicate Prometheus metrics.

## Metrics Are Derived From Evidence

`metrics.sh` does not independently perform repository analysis.

Its responsibility is to transform existing evidence into a standard
observability format:

    Evidence JSON
         |
         v
      metrics.sh
         |
         v
    Prometheus exposition format

This keeps the metrics layer deterministic and prevents analysis logic from
being duplicated inside the metrics engine.
