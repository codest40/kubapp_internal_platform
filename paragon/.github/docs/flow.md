# Execution Flow

```text
                              ┌──────────────────────────────┐
                              │       GitHub Actions         │
                              │        Control Plane         │
                              └──────────────┬───────────────┘
                                             │
                           ┌─────────────────┴─────────────────┐
                           │                                   │
                           ▼                                   ▼
                 ┌───────────────────┐              ┌────────────────────┐
                 │        CI         │              │  Stable / Rollback │
                 │                   │              │      Operations     │
                 │ Build Applications│              │                    │
                 │ Test / Scan       │              │ Promote Stable     │
                 │ Build Images      │              │ Retrieve Stable    │
                 │ Push Images       │              │ Rollback            │
                 └─────────┬─────────┘              └─────────┬──────────┘
                           │                                   │
                           ▼                                   │
                 ┌───────────────────┐                         │
                 │   Platform Build  │                         │
                 │                   │                         │
                 │ App Registry       │                         │
                 │ Service Registry   │                         │
                 │ Registry Validation│                         │
                 │ Platform State     │                         │
                 └─────────┬─────────┘                         │
                           │                                   │
                           ▼                                   │
                 ┌───────────────────┐                         │
                 │     GitOps         │◄────────────────────────┘
                 │                   │
                 │ Registry / State  │
                 │ Kubernetes Specs  │
                 └─────────┬─────────┘
                           │
                           ▼
                 ┌───────────────────┐
                 │   Add New App     │
                 │                   │
                 │ Update GitOps     │
                 │ Deployment State  │
                 └─────────┬─────────┘
                           │
                           ▼
                 ┌───────────────────┐
                 │     Argo CD       │
                 │                   │
                 │ Declarative Sync  │
                 │ Reconciliation    │
                 └─────────┬─────────┘
                           │
                           ▼
                 ┌───────────────────┐
                 │   Kubernetes      │
                 │     AWS EKS       │
                 │                   │
                 │ Applications      │
                 │ Platform Services │
                 └─────────┬─────────┘
                           │
                           ▼
                 ┌───────────────────┐
                 │ Runtime Verify    │
                 │                   │
                 │ Prechecks         │
                 │ GitOps Validation │
                 │ Runtime Checks    │
                 │ Health Checks     │
                 └───────────────────┘


             ─────────────── CONTROL / OPERATIONS ───────────────

                 ┌───────────────────┐
                 │      Cleanup      │
                 │                   │
                 │ Argo CD / Cluster │
                 │ Cleanup Operations│
                 └───────────────────┘


             ─────────────── ROLLBACK PATH ──────────────────────

                 Stable Commit
                       │
                       ▼
                 Stable Tag
                       │
                       ▼
              Retrieve Stable State
                       │
                       ▼
                Rollback GitOps
                       │
                       ▼
                 Argo CD Sync
                       │
                       ▼
                Kubernetes / EKS
```

