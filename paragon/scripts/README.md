# Scripts

The `scripts/` directory contains operational scripts used to manage,
validate, deploy, troubleshoot, and clean up the Kubapp environment.

These scripts automate repetitive operational tasks so they can be
executed consistently instead of relying on manual commands.

## Script Documentation

Each script has a corresponding document under `scripts/docs/`.
Ci scripts are under `scripts/ci/README`

The documentation focuses on two things:

- **What the script does**
- **What the script expects to already exist**

This keeps the documentation concise while providing enough context to
understand when and why each script should be used.

## Script Categories

| Category | Purpose |
|---|---|
| Activation | Run validation and GitOps preparation before changes are committed |
| CI |  Continous Integration Scripts|
| GitOps | Bootstrap and inspect GitOps resources |
| AWS Cleanup | Remove AWS resources and investigate leftovers |
| Kubernetes Cleanup | Clean cluster resources and namespaces |
| Secrets | Create or update Kubernetes secrets from encrypted files |
| Git Operations | Commit and push generated or selected changes |

- Clean Up Scripts are mainly for testing and cost control

## Important
```
    Some scripts are intended to be executed by GitHub Actions workflows
    rather than manually.
```

