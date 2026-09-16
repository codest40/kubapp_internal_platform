# Activate Pipeline Workflow

## Purpose

`activate_pipeline.yml` is the manual entry point for activating the platform pipeline.

It controls which pipeline stages run based on the selected:

* environment
* execution mode

The workflow does not implement the individual stages itself. It calls the corresponding reusable workflows in sequence.

---

## Workflow File

```text
.github/workflows/activate_pipeline.yml
```

## Inputs

### Environment

```text
env
```

Available values:

```text
dev
prod
```

Default:

```text
dev
```

### Mode

```text
mode
```

Available values:

```text
full
build
rollback
cleanup
```

Default:

```text
full
```

---

# Pipeline Modes

## `full`

Runs the complete deployment flow:

```text
CI
 ↓
Platform Build
 ↓
Add New App
 ↓
Setup Argo CD
 ↓
Validate GitOps
 ↓
Verify Runtime
```

The mode runs:

```text
ci.yml
build.yml
add_new_app.yml
setup_argocd.yml
validate_gitops.yml
verify_runtime.yml
```

Each stage waits for its required previous stage to complete successfully.

---

## `build`

Runs the build and GitOps preparation flow without runtime verification:

```text
CI
 ↓
Platform Build
 ↓
Add New App
 ↓
Validate GitOps
```

The mode runs:

```text
ci.yml
build.yml
add_new_app.yml
validate_gitops.yml
```

---

## `rollback`

Retrieves the latest stable deployment and rolls the GitOps state back to it:

```text
Get Latest Stable Deployment
          ↓
        Rollback
```

The mode runs:

```text
get_stable_deploy.yml
rollback.yml
```

The stable commit and stable tag returned by `get_stable_deploy.yml` are passed to the rollback workflow.

---

## `cleanup`

Runs only the Argo CD cleanup workflow:

```text
Clean Argo CD
```

The mode runs:

```text
clean_argocd.yml
```

---

# Execution Flow

```text
                    activate_pipeline
                           │
                ┌──────────┼──────────┐
                │          │          │
              full       build     rollback
                │          │          │
                │          │          ▼
                │          │    get stable deploy
                │          │          │
                │          │          ▼
                │          │       rollback
                │          │
                ▼          ▼
               CI         CI
                │          │
                ▼          ▼
              Build      Build
                │          │
                ▼          ▼
            Add App     Add App
                │          │
                ├───┐      ▼
                │   │   Validate
                ▼   │     GitOps
            Setup   │
            ArgoCD  │
                │   │
                ▼   │
            Validate│
            GitOps  │
                │   │
                ▼   │
          Verify Runtime
```

`cleanup` is independent of the other modes:

```text
cleanup
   │
   ▼
clean_argocd.yml
```

---

# Concurrency

Pipeline executions are grouped by environment:

```text
activate-pipeline-${{ inputs.env }}
```

`cancel-in-progress` is disabled.

Therefore, an active pipeline execution for an environment is not automatically cancelled by a newer execution for that same environment.

---

# Permissions

The workflow requests:

```text
contents: write
actions: read
id-token: write
pull-requests: write
security-events: write
```

These permissions are available to the reusable workflows called by the pipeline, subject to GitHub Actions permission rules.

---

# Responsibility

`activate_pipeline.yml` is the **orchestrator**.

It is responsible for:

* selecting the environment
* selecting the pipeline mode
* ordering reusable workflows
* passing required inputs
* passing inherited secrets where required
* enforcing stage dependencies

The individual workflows remain responsible for their own operations.

```text
activate_pipeline.yml
        │
        ├── ci.yml
        ├── build.yml
        ├── add_new_app.yml
        ├── setup_argocd.yml
        ├── validate_gitops.yml
        ├── verify_runtime.yml
        ├── get_stable_deploy.yml
        ├── rollback.yml
        └── clean_argocd.yml
```
