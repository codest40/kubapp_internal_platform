# Platform Build

The platform build section converts CI application output and platform configuration into a validated **platform registry**.
The registry provides the structured information required by the downstream deployment/GitOps layer.

## Location

```text
scripts/platform/
```

## Build Flow

```text
gitops/state/final_ci_data.json
            │
            ▼
build_app_registry.py
            │
            ├── App registry files
            │
            ▼
build_service_registry.py
            │
            ├── Backend service registry files
            │
            ▼
validate_registry.py
            │
            ▼
Validated platform registry
            │
            ▼
create_latest_state.py
            │
            ▼
gitops/state/current.json
```

---

# 1. `build_app_registry.py`

Builds a registry entry for every application reported by CI.

### Inputs

Environment variables:

```text
ENV
MANIFEST
REGISTRY
```

The CI manifest is read from:

```text
<MANIFEST>/final_ci_data.json
```

For each application, it consumes:

* application image
* application path
* runtime
* CI metadata
* `kubapp.yml`
* secret-file information

### Processing

The script:

1. Validates the CI manifest.
2. Verifies the manifest environment matches `ENV`.
3. Validates required application fields.
4. Loads the application's `kubapp.yml` when present.
5. Applies platform defaults where configuration is absent.
6. Extracts image repository and tag.
7. Builds the application registry object.
8. Validates the generated registry.
9. Writes the registry file.

### Output

Application registry files are written to:

```text
<REGISTRY>/<ENV>/
```

Each application becomes:

```text
<service-name>.json
```

The generated registry has:

```text
type = App
```

and contains deployment information such as:

```text
service
runtime
computeType
context
image
tag
registry
namespace
env
port
containerUid
basePath
healthPath
livePath
volume configuration
environment/secret availability
```

Applications are processed concurrently with a maximum of **4 workers**.

---

# 2. `build_service_registry.py`

Builds registry entries for platform-managed backend services.

The services are currently defined directly in the script:

```text
grafana
prometheus
alertmanager
argocd
```

Each service defines:

```text
type
stack
backendService
port
```

The script adds:

```text
service
env
timestamp
```

### Output

Service registry files are written to:

```text
<REGISTRY>/<ENV>/
```

For example:

```text
grafana.json
prometheus.json
alertmanager.json
argocd.json
```

These entries have:

```text
type = Backend
```

Services are processed concurrently with a maximum of **4 workers**.

---

# 3. `validate_registry.py`

Validates the generated platform registry.

It reads all JSON files from:

```text
<REGISTRY>/<ENV>/
```

Each file is classified by its `type`.

### Application registry

```text
type = App
```

The script validates:

* required fields
* field types
* service name
* environment
* port
* compute type
* image
* tag
* context
* container UID

Valid compute types are:

```text
fargate
ec2
```

### Backend registry

```text
type = Backend
```

The script validates:

* required fields
* service name
* environment
* port
* stack
* backend service

### Common validation

For every registry file:

```text
filename == service name
env == ENV
port > 0
```

The build fails if any registry file is invalid.

Registry files are validated concurrently with a maximum of **4 workers**.

---

# 4. `create_latest_state.py`

Creates the current platform build state.

Required environment variables:

```text
ENV
RUN_ID
WORKFLOW_ID
MANIFEST
```

It creates:

```text
<MANIFEST>/current.json
```

with:

```json
{
  "env": "...",
  "run_id": "...",
  "workflow": "...",
  "timestamp": "..."
}
```

The timestamp is recorded in UTC.

This file represents the latest platform build execution state.

---

# Supporting Module

## `reuse.py`

Provides shared utility functions used by the platform build scripts.

The important function is:

```python
get_root()
```

which determines the repository root using:

```bash
git rev-parse --show-toplevel
```

This allows the build scripts to resolve paths from the repository root rather than depending on the directory from which the script was executed.

---

# Result

The platform build produces two types of registry entries:

```text
App
 │
 ├── Application image
 ├── Runtime
 ├── Deployment configuration
 ├── Health configuration
 ├── Storage configuration
 └── Environment/secret state

Backend
 │
 ├── Platform service
 ├── Stack
 ├── Kubernetes backend service
 └── Port
```

The resulting registry is then validated before the platform state is committed for downstream GitOps processing.
