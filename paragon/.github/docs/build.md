# KubApp Platform Registry Build

The Platform Registry Build workflow converts the application build output produced by CI into the platform registry consumed by downstream GitOps workflows.

The workflow is:

* [`build.yml`](../workflows/build.yml)

Its responsibility is **not to build Docker images**.

Application dependencies, tests, Docker image builds, image publishing, and application health checks are handled by the CI workflow.

This workflow takes the resulting CI state and builds the platform's deployment registry.

---

# Purpose

The Platform Registry Build performs five main tasks:

1. Build the application registry.
2. Build the platform service registry.
3. Validate the generated registry.
4. Generate the latest platform state.
5. Commit the resulting GitOps changes.

The flow is:

```text
CI
 │
 │  final_ci_data.json
 ▼
Build App Registry
 │
 ▼
Build Service Registry
 │
 ▼
Validate Registry
 │
 ▼
Create Latest State
 │
 ▼
Commit gitops/
 │
 ▼
Downstream GitOps Workflows
```

The important separation is:

```text
CI
 └── Builds and validates applications

Platform Build
 └── Converts CI output into platform/GitOps registry state

GitOps
 └── Consumes the registry and performs deployment
```

---

# Workflow Triggers

`build.yml` supports two execution modes.

## Manual Dispatch

The workflow can be started directly from GitHub Actions.

Available inputs:

| Input      | Required | Default           | Purpose                               |
| ---------- | -------- | ----------------- | ------------------------------------- |
| `env`      | No       | `dev`             | Target environment                    |
| `manifest` | No       | `gitops/state`    | Location of CI state                  |
| `registry` | No       | `gitops/registry` | Root directory for generated registry |

Example:

```text
Environment: dev
Manifest: gitops/state
Registry: gitops/registry
```

---

## Reusable Workflow

The workflow can also be called by another workflow.

```yaml
uses: ./.github/workflows/build.yml
with:
  env: dev
```

The reusable workflow requires:

```yaml
env:
  required: true
  type: string
```

The `manifest` and `registry` inputs are optional because they have defaults.

This allows the main pipeline to normally provide only:

```yaml
with:
  env: ${{ inputs.env }}
```

while still allowing the paths to be overridden when required.

---

# Permissions

The workflow requests:

```yaml
permissions:
  contents: write
  actions: read
```

### `contents: write`

Required because the workflow commits the generated platform registry and state back to the repository.

### `actions: read`

Allows the workflow to access GitHub Actions information required by the platform build process.

The workflow therefore has enough permission to both **read required CI workflow information** and **write the resulting GitOps state**.

---

# Environment Variables

The workflow exposes its inputs and execution metadata as environment variables:

```text
ENV
MANIFEST
REGISTRY
RUN_ID
WORKFLOW_ID
```

They are populated from:

```yaml
ENV: ${{ inputs.env }}
MANIFEST: ${{ inputs.manifest }}
REGISTRY: ${{ inputs.registry }}
RUN_ID: "${{ github.run_id }}"
WORKFLOW_ID: "${{ github.workflow }}"
```

This keeps the platform scripts independent from GitHub Actions expression syntax.

The Python scripts consume normal environment variables instead of needing to know how the workflow was triggered.

---

# Pipeline

The workflow contains a single job:

```text
platform_build
```

The job executes the platform build sequentially:

```text
Checkout
   │
   ▼
Build App Registry
   │
   ▼
Build Service Registry
   │
   ▼
Validate Registry
   │
   ▼
Create Latest State
   │
   ▼
Commit Registry
```

This ordering is intentional.

The registry must be completely generated and validated before anything is committed.

---

# 1. Checkout

The workflow first checks out the repository:

```yaml
- name: Checkout KubApp
  uses: actions/checkout@v4
```

All subsequent scripts operate against the checked-out repository.

---

# 2. Build Application Registry

The first platform build step runs:

```text
python scripts/platform/build_app_registry.py
```

This builds the registry representation of the applications produced by CI.

The application registry is based on the CI-generated application state rather than rebuilding the applications themselves.

Conceptually:

```text
CI Application Output
        │
        ▼
final_ci_data.json
        │
        ▼
build_app_registry.py
        │
        ▼
Application Registry
```

This keeps application build logic separate from platform registry generation.

---

# 3. Build Platform Service Registry

The next step runs:

```text
python scripts/platform/build_service_registry.py
```

This generates registry information for platform-managed services.

These are services that are part of the KubApp platform rather than application workloads built by CI.

Examples can include platform components such as:

* Argo CD
* Prometheus
* Grafana
* Alertmanager

The exact services represented by the registry are defined by the platform registry implementation.

The distinction is:

```text
Application Registry
        │
        └── Applications built by CI

Service Registry
        │
        └── Platform/backend services
```

Both become part of the generated platform registry.

---

# 4. Registry Validation

After both registries have been generated, the workflow runs:

```text
python scripts/platform/validate_registry.py
```

Validation occurs **before the GitOps changes are committed**.

The purpose is to prevent an invalid generated registry from becoming repository state.

The flow is therefore:

```text
Generate
   │
   ▼
Validate
   │
   ├── Failure → Stop
   │
   └── Success
          │
          ▼
        Commit
```

A validation failure prevents the workflow from reaching the commit stage.

---

# 5. Save Platform State

The workflow then runs:

```text
python scripts/platform/create_latest_state.py
```

This generates the latest platform state required by downstream workflows.

The state can contain information about the platform registry generation and its originating workflow execution.

The workflow exposes:

```text
ENV
RUN_ID
WORKFLOW_ID
```

so the state-generation script can associate the generated platform state with its environment and GitHub Actions execution.

Conceptually:

```text
Platform Registry
      │
      ▼
Latest Platform State
      │
      ├── Environment
      ├── Workflow information
      └── Build metadata
```

---

# 6. Commit Platform Registry

Once registry generation, validation, and state creation have succeeded, the workflow commits the resulting GitOps changes.

It invokes the shared commit utility:

```text
bash scripts/extra/commit.sh "$DIR" "$MSG"
```

with:

```text
DIR="gitops"
```

and:

```text
[PLATFORM-BUILD] Update platform registry from CI
```

The important point is that the workflow commits the **`gitops/` directory as a unit**.

The commit therefore contains the registry and state changes produced by the platform build.

---

# Repository State

The platform build transforms the repository approximately like this:

```text
Before Platform Build

gitops/
├── registry/
└── state/
        │
        │
        ▼
   Platform Build
        │
        ├── build_app_registry.py
        ├── build_service_registry.py
        ├── validate_registry.py
        └── create_latest_state.py
        │
        ▼

After Platform Build

gitops/
├── registry/
│   ├── ...
│   └── ...
└── state/
    └── ...
```

The exact generated files are controlled by the platform scripts rather than by the workflow itself.

---

# Failure Boundaries

Each stage must succeed before the next stage begins.

```text
Checkout
   │
   ▼
App Registry
   │
   X ── failure → workflow stops
   │
   ▼
Service Registry
   │
   X ── failure → workflow stops
   │
   ▼
Validation
   │
   X ── failure → workflow stops
   │
   ▼
Latest State
   │
   X ── failure → workflow stops
   │
   ▼
Git Commit
```

This prevents the workflow from committing partially generated or invalid platform state.

---

# Relationship With CI

The CI workflow and Platform Registry Build have different responsibilities.

## CI

CI handles application-level work:

```text
Discover application
      │
      ▼
Detect runtime
      │
      ▼
Install dependencies
      │
      ▼
Lint
      │
      ▼
Security analysis
      │
      ▼
Unit tests
      │
      ▼
Docker build
      │
      ▼
Push image
      │
      ▼
Container health check
      │
      ▼
final_ci_data.json
```

## Platform Registry Build

The platform build consumes that result:

```text
final_ci_data.json
        │
        ▼
Application Registry
        │
        ▼
Platform Service Registry
        │
        ▼
Validation
        │
        ▼
Latest Platform State
        │
        ▼
GitOps Commit
```

This separation prevents the platform registry workflow from duplicating application build logic.

---

# Relationship With GitOps

The platform registry is the bridge between application CI and GitOps.

```text
Application Source
       │
       ▼
      CI
       │
       ▼
Application Build State
       │
       ▼
Platform Registry Build
       │
       ▼
gitops/registry/
       │
       ▼
Git Commit
       │
       ▼
GitOps / Argo CD
       │
       ▼
Kubernetes
```

The Platform Registry Build therefore produces **repository state for deployment**, rather than directly deploying workloads to Kubernetes.

---

# Why This Workflow Is Separate From CI

Keeping these responsibilities separate provides a clean boundary:

| Responsibility                       | Workflow             |
| ------------------------------------ | -------------------- |
| Application discovery                | CI                   |
| Runtime detection                    | CI                   |
| Dependency installation              | CI                   |
| Linting                              | CI                   |
| Security analysis                    | CI                   |
| Unit testing                         | CI                   |
| Docker image build                   | CI                   |
| Image push                           | CI                   |
| Application container health check   | CI                   |
| Application registry generation      | Platform Build       |
| Platform service registry generation | Platform Build       |
| Registry validation                  | Platform Build       |
| Platform state generation            | Platform Build       |
| GitOps registry commit               | Platform Build       |
| Kubernetes deployment                | Downstream GitOps    |
| Runtime verification                 | Runtime Verification |
| Rollback                             | Rollback workflow    |

This gives each workflow a clear responsibility instead of making one workflow responsible for the entire delivery system.

---

# Downstream Flow

The current pipeline relationship is:

```text
                    CI
                     │
                     ▼
          Application Build State
                     │
                     ▼
             build.yml
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
    App Registry          Service Registry
          │                     │
          └──────────┬──────────┘
                     ▼
              Registry Validation
                     │
                     ▼
              Latest Platform State
                     │
                     ▼
               Git Commit
                     │
                     ▼
             GitOps Workflows
                     │
                     ▼
                 Argo CD
                     │
                     ▼
                Kubernetes
                     │
                     ▼
             Runtime Verification
```


