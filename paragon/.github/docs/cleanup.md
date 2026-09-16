# Cleanup and Reconciliation

KubApp uses separate cleanup workflows to remove obsolete Kubernetes resources and reconcile the GitOps repository with the desired application state.

## Workflows

- `clean_argocd.yml` — performs controlled cluster cleanup.
- `remove_app.yml` — removes orphaned application configurations.
- `remove_svc.yml` — removes services from the shared ingress registry.

## Cleanup Architecture

    GitOps State
         |
         +----------------------+
         |                      |
         v                      v
    remove_svc.yml        remove_app.yml
         |                      |
         v                      v
    Remove ingress entry   Find orphan apps
         |                      |
         +----------+-----------+
                    |
                    v
             GitOps Validation
                    |
                    v
                Git Commit


    Kubernetes Cluster
         |
         v
    clean_argocd.yml
         |
         v
    Cluster Cleanup
         |
         v
    State Verification

## Application Cleanup

### `remove_app.yml`

This workflow performs orphan application reconciliation.

An application is considered an orphan when an application directory exists under:

    gitops/envs/<env>/

but the application is no longer registered in:

    gitops/ingress/<env>/values.yaml

The workflow compares the desired ingress services with the existing application directories.

    Ingress Registry
          |
          v
    Valid Applications
          |
          | compare
          v
    gitops/envs/<env>/
          |
          v
    Orphan Detection
          |
          v
    Remove Orphans

### Automatic Reconciliation

`remove_app.yml` can run automatically when relevant GitOps files change.

The reconciliation process:

1. Determines the environment.
2. Reads the ingress registry.
3. Builds the list of valid applications.
4. Scans the environment directory.
5. Identifies applications no longer registered.
6. Removes orphaned application directories.
7. Validates the GitOps structure.
8. Commits the changes.

Production deletion is deliberately blocked in automatic cleanup.

## Manual Application Cleanup

`remove_app.yml` also supports manual service selection.

Manual cleanup:

- Accepts one or more services.
- Verifies that the application directory exists.
- Prevents deletion if the service is still registered in ingress.
- Blocks production deletion.
- Removes only the requested orphan application.

This provides a controlled mechanism for cleaning individual application directories.

## Service Cleanup

### `remove_svc.yml`

This workflow removes services from the shared ingress configuration.

The user provides one or more service names:

    chatbot,nodejsapp

or:

    chatbot nodejsapp

The workflow then:

1. Normalizes the service list.
2. Removes each service from the environment's ingress values.
3. Validates the resulting YAML.
4. Validates the complete GitOps structure.
5. Commits the changes.

Removing a service from ingress can subsequently cause `remove_app.yml` to identify its application directory as an orphan.

Therefore the two workflows work together:

    remove_svc.yml
          |
          v
    Remove service from ingress
          |
          v
    Git Commit
          |
          v
    remove_app.yml
          |
          v
    Detect orphan application
          |
          v
    Remove application directory

## Cluster Cleanup

### `clean_argocd.yml`

This workflow handles controlled cleanup of Kubernetes cluster resources, particularly resources associated with Argo CD and the KubApp deployment environment.

Because cluster cleanup can be destructive, the workflow requires explicit confirmation.

The operator must provide:

    YES

Anything else aborts the workflow.

## Cluster Cleanup Flow

    Manual Trigger
          |
          v
    Safety Confirmation
          |
          +---- NO ----> Abort
          |
         YES
          |
          v
    AWS Authentication
          |
          v
    EKS Kubeconfig
          |
          v
    Cluster Cleanup Script
          |
          v
    Post-Cleanup Verification
          |
          v
    Cluster State

After cleanup, the workflow checks resources such as:

- Namespaces
- Ingress resources
- Argo CD ApplicationSets

The purpose is to verify that the requested cleanup actually occurred.

## Cleanup Safety

KubApp deliberately applies different levels of protection depending on the cleanup operation.

| Operation | Development | Production |
|---|---|---|
| Remove orphan application | Allowed | Blocked |
| Automatic orphan cleanup | Allowed | Deletion blocked |
| Manual orphan deletion | Allowed | Blocked |
| Remove ingress service | Allowed | Explicitly controlled |
| Cluster cleanup | Requires confirmation | Requires confirmation |

The key principle is:

> Cleanup should remove resources that are no longer desired without accidentally deleting resources that are still part of the desired state.

## Relationship With GitOps

Cleanup is part of KubApp's reconciliation model.

    Desired State
          |
          v
    GitOps Repository
          |
          v
    Ingress Registry
          |
          v
    Application State
          |
          +---- missing registration ----> Orphan
                                            |
                                            v
                                         Cleanup

Git remains the source of truth. Cleanup brings the repository back into a consistent state rather than treating the Kubernetes cluster as the authoritative source.
