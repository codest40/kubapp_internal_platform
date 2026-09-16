# CI Workflow

## Purpose

`ci.yml` runs the application Continuous Integration workflow.

It:

1. Checks out the repository.
2. Identifies the commit being processed.
3. Checks the Python environment.
4. Runs the CI dependency abstractor.
5. Commits generated application and GitOps changes.

---

## Workflow File

```text
.github/workflows/ci.yml
```

## Triggers

### Reusable workflow

```yaml
workflow_call:
```

Required input:

```text
env
```

Required secrets:

```text
DOCKER_USER
DOCKER_PASS
```

### Manual execution

```yaml
workflow_dispatch:
```

Available environments:

```text
dev
prod
```

Default:

```text
dev
```

---

## Permissions

```yaml
permissions:
  contents: write
```

The workflow requires write access because it commits generated changes back to the repository.

---

## Environment

The workflow sets:

```yaml
ENV: ${{ inputs.env || 'dev' }}
```

If no environment is supplied, `dev` is used.

---

## Steps

### 1. Checkout

```yaml
actions/checkout@v4
```

Checks out the repository.

### 2. Show Commit

Prints the GitHub commit SHA being processed.

### 3. Check Python

Runs:

```bash
bash scripts/ci/check_python.sh
```

### 4. Run CI

Runs:

```bash
python scripts/ci/dependency_abstractor.py
```

The following environment variables are provided:

```text
NVD_API_KEY
DOCKER_USER
DOCKER_PASS
ENV
```

### 5. Commit Generated Changes

Runs:

```bash
bash scripts/extra/commit.sh "$DIR1" "$DIR2" "$MSG"
```

with:

```text
DIR1 = docker
DIR2 = gitops
```

and commit message:

```text
[APP-BUILD-PUSH] Updated App Build + Push Registry from CI
```

### 6. Completion

Prints:

```text
Successfully completed CI workflow!
```

---

## Flow

```text
Checkout
   ↓
Show Commit
   ↓
Check Python
   ↓
Run Dependency Abstractor
   ↓
Commit docker/ + gitops/
   ↓
Complete
```
