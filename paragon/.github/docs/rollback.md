# Stable Deployment and Rollback

This section manages stable deployment records and provides the mechanism for restoring GitOps state to a previously promoted stable commit.

The rollback system is based on the **Git commit as the deployment unit**.

```text
Create Stable Deployment
          │
          ▼
   stable tag + state
          │
          ▼
Get Latest Stable Deployment
          │
          ▼
       Rollback
          │
          ├── target
          │
          └── full
```

## Workflows

```text
.github/workflows/
├── create_stable_deploy.yml
├── get_stable_deploy.yml
└── rollback.yml
```

---

# 1. Promote a Commit as Stable

### `create_stable_deploy.yml`

This workflow manually promotes an existing commit as the stable deployment for an environment.

### Inputs

```text
commit
env
```

`commit` must be a complete 40-character Git SHA.

`env` must be:

```text
dev
prod
```

### Process

The workflow:

1. Checks out the repository with full history and tags.
2. Validates that the supplied commit is a full SHA.
3. Fetches and verifies that the commit exists.
4. Validates the selected environment.
5. Displays the selected commit.
6. Creates a stable Git tag.
7. Pushes the tag.
8. Creates a stable deployment state file.
9. Commits that state file to the repository.

### Stable Tag

The tag format is:

```text
stable-<env>-<timestamp>-<short-sha>
```

Example:

```text
stable-dev-20260916-120530-a1b2c3d
```

The tag points directly to the promoted commit.

### Stable State

A record is created under:

```text
gitops/state/
```

with the format:

```text
stable-deploy-<env>-<timestamp>.json
```

The record contains:

```json
{
  "env": "dev",
  "commit": "<commit-sha>",
  "stable_tag": "<stable-tag>",
  "timestamp": "<timestamp>"
}
```

This creates a historical record of which commit was promoted as stable.

---

# 2. Retrieve the Latest Stable Deployment

### `get_stable_deploy.yml`

This workflow finds the latest stable deployment record for an environment.

### Input

```text
env
```

### Process

It searches:

```text
gitops/state/
```

for:

```text
stable-deploy-<env>-*.json
```

The latest matching file is selected.

The workflow then verifies:

* the file exists
* the recorded environment matches the requested environment
* a stable commit exists
* a stable tag exists

### Outputs

The workflow exposes:

```text
stable_commit
stable_tag
```

These outputs are consumed by the rollback workflow.

---

# 3. Rollback

### `rollback.yml`

The rollback workflow restores the platform to a previously promoted stable deployment.

### Inputs

For reusable workflow execution:

```text
env
commit
tag
```

For manual execution:

```text
env
tag
mode
```

Manual rollback modes are:

```text
target
full
```

---

## Stable Deployment Verification

Before changing anything, rollback verifies:

```text
Stable commit exists
        │
        ▼
Stable tag exists
        │
        ▼
Tag points to supplied commit
```

If the tag does not point to the supplied commit, rollback stops.

This prevents a mismatched commit/tag pair from being used for rollback.

---

# Target Rollback

`target` is the normal rollback operation.

It restores the complete `gitops/` directory from the stable commit:

```bash
git restore --source="$COMMIT" -- gitops
```

The restored state is then committed to `main`:

```text
Stable commit
      │
      ▼
Restore gitops/
      │
      ▼
Commit rollback
      │
      ▼
Push to main
```

Only the GitOps state is restored. The existing `main` history is preserved.

If the current GitOps state already matches the stable commit, no new rollback commit is created.

---

# Full Rollback

`full` rollback resets `main` itself to the stable commit:

```text
main
 │
 ▼
reset --hard <stable-commit>
 │
 ▼
force-with-lease
 │
 ▼
main points to stable commit
```

This rewrites the `main` branch history.

The workflow explicitly warns:

```text
WARNING: This rewrites main history
```

The push uses:

```bash
git push origin main --force-with-lease
```

---

# Rollback Flow

The normal automated rollback path is:

```text
activate_pipeline.yml
        │
        ▼
get_stable_deploy.yml
        │
        ├── stable_commit
        └── stable_tag
                │
                ▼
        rollback.yml
                │
                ▼
        verify commit + tag
                │
                ▼
          target rollback
                │
                ▼
        restore gitops/
                │
                ▼
          commit + push
```

---

# Stable Deployment Lifecycle

```text
Existing Git Commit
        │
        ▼
Promote as Stable
        │
        ├── create stable tag
        │
        └── create stable state record
                │
                ▼
        gitops/state/
                │
                ▼
       Retrieve latest stable
                │
                ▼
             Rollback
                │
          ┌─────┴─────┐
          ▼           ▼
       target        full
          │           │
          ▼           ▼
    restore GitOps   reset main
```

## Responsibility

| Workflow                   | Responsibility                                    |
| -------------------------- | ------------------------------------------------- |
| `create_stable_deploy.yml` | Promote a known commit as stable                  |
| `get_stable_deploy.yml`    | Find and return the latest stable deployment      |
| `rollback.yml`             | Verify and restore the selected stable deployment |

The stable deployment is therefore identified by **both a commit and a tag**, while the rollback target is the complete GitOps state represented by that stable commit.
