# KubApp GitOps Reconciliation

GitOps reconciliation keeps the application configuration under
`gitops/envs/<env>/` aligned with the services currently registered in the
environment's ingress configuration.

Its primary purpose is to detect application configurations that are no
longer part of the desired application set and safely remove them when
permitted.

The reconciliation workflow is:

- `remove_app.yml`

---

## Purpose

Reconciliation answers a simple question:

> Does every application configuration in the environment still belong to
> the current desired application set?

KubApp uses the ingress registry as the reference for currently registered
services.

```text
Ingress Registry
      |
      v
Valid Service List
      |
      v
Compare with gitops/envs/<env>/
      |
      +---- Registered ----> Keep
      |
      +---- Missing --------> Orphan
                                  |
                                  v
                              Remove
                                  |
                                  v
                         Validate GitOps
                                  |
                                  v
                              Git Commit
