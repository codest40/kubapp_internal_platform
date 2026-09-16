# KubApp Remove Service

`remove_svc.yml` is the controlled service-removal workflow for KubApp.

It removes one or more services from the environment-specific shared
ingress registry. It does **not** immediately delete the corresponding
application configuration.

Application deletion is handled separately by the reconciliation process.

## Purpose

The workflow provides a safe separation between **routing removal** and
**application deletion**.

It:

1. Accepts the target environment and service names.
2. Normalizes the service list.
3. Removes the services from the shared ingress registry.
4. Validates the resulting configuration.
5. Commits the GitOps change.
6. Allows `remove_app.yml` to later reconcile orphaned applications.

The main flow is:

    Manual Trigger
          |
          v
    Select Environment
          |
          v
    Provide Services
          |
          v
    Normalize Service List
          |
          v
    Remove Ingress Entries
          |
          v
    Validate Configuration
          |
          v
    Git Commit
          |
          v
    remove_app.yml
          |
          v
    Orphan Reconciliation

## Workflow

The workflow is:

    .github/workflows/remove_svc.yml

It is manually triggered through `workflow_dispatch`.

## Inputs

| Input | Required | Description | Example |
|---|---|---|---|
| `services` | Yes | Services to remove | `chatbot,nodejsapp` |
| `env` | Yes | Target environment | `dev` |

Services may be supplied as comma-separated or space-separated values:

    chatbot nodejsapp

or:

    chatbot,nodejsapp

## Permissions

The workflow requires repository write access because it creates the
resulting GitOps commit.

    permissions:
      contents: write

## Concurrency

GitOps mutation workflows use a shared concurrency group:

    concurrency:
      group: using-commit
      cancel-in-progress: false

This prevents multiple workflows from modifying and committing GitOps
state at the same time.

# Processing

## Checkout

The repository is checked out with full history:

    actions/checkout@v4

    fetch-depth: 0

Full history allows the workflow to perform the required Git operations
when creating the removal commit.

## Required Tools

The workflow uses:

| Tool | Purpose |
|---|---|
| `jq` | JSON processing where required by supporting scripts |
| `yq` | YAML inspection and validation |

The important validation performed by this workflow is the validation of
the environment-specific ingress configuration.

## Input Normalization

The supplied service list may contain commas, spaces, or duplicates.

The workflow converts the input into a unique list of service names.

For example:

    chatbot,nodejsapp chatbot

becomes:

    chatbot
    nodejsapp

This ensures that each service is processed once.

If normalization produces an empty list, the workflow fails rather than
performing an ambiguous operation.

# Ingress Removal

Each normalized service is passed to the shared ingress-management script:

    bash scripts/register_new_svc.sh remove "$SERVICE" "$ENV"

The workflow therefore does not contain a second implementation of ingress
mutation logic. The service registration script remains the central place
for adding and removing ingress entries.

The target configuration is:

    gitops/ingress/<env>/values.yaml

For example:

    gitops/ingress/dev/values.yaml

If `chatbot` is removed, the registry changes conceptually from:

    services:
      - chatbot
      - nodejsapp
      - payments

to:

    services:
      - nodejsapp
      - payments

# Validation

After the services are removed, the workflow validates the resulting
configuration before committing it.

## Ingress YAML Validation

The environment-specific values file is parsed with `yq`:

    yq e '.' "gitops/ingress/${ENV}/values.yaml" > /dev/null

This catches malformed YAML before the change reaches Git.

## GitOps Validation

The complete GitOps structure is then validated with:

    bash scripts/validate_gitops.sh

The validation boundary is therefore:

    Ingress YAML
         |
         v
    GitOps Validation
         |
         v
    Commit

If either validation fails, the workflow stops without committing the
change.

# Commit

After successful validation, the workflow records the removal as a Git
change using:

    bash scripts/commit.sh \
      "gitops/ingress" \
      "[REMOVE-SVC]: removed services from ingress (${ENV})"

The resulting commit becomes part of the GitOps history.

Example:

    [REMOVE-SVC]: removed services from ingress (dev)

# Relationship With Application Reconciliation

Removing a service from ingress does **not** immediately remove its
application directory.

For example, after removing `chatbot`:

    gitops/ingress/dev/values.yaml

no longer references the service, but:

    gitops/envs/dev/chatbot/

may still exist.

This is intentional.

The two operations have separate responsibilities:

    remove_svc.yml
          |
          v
    Remove ingress registration
          |
          v
    Git Commit
          |
          v
    remove_app.yml
          |
          v
    Detect orphan
          |
          v
    Remove permitted application configuration

This separation provides an opportunity to validate the routing change
before application configuration is considered for deletion.

# Example

Suppose the environment contains:

    gitops/
    ├── ingress/
    │   └── dev/
    │       └── values.yaml
    │
    └── envs/
        └── dev/
            ├── chatbot/
            ├── nodejsapp/
            └── payments/

and the ingress registry contains:

    chatbot
    nodejsapp
    payments

An operator requests:

    services = chatbot
    env = dev

The workflow:

1. Normalizes `chatbot`.
2. Removes `chatbot` from the development ingress registry.
3. Validates the ingress YAML.
4. Validates the GitOps structure.
5. Commits the change.

The application directory may temporarily remain:

    gitops/envs/dev/chatbot/

`remove_app.yml` can subsequently detect that `chatbot` is no longer
registered in ingress and classify the directory as an orphan.

# Safety Model

KubApp intentionally separates:

**Routing removal**

    Remove service from ingress

from:

**Application deletion**

    Remove orphaned application configuration

This prevents a request to stop exposing a service from automatically
deleting its deployment configuration.

Application deletion is therefore subject to the separate reconciliation
workflow and its environment-specific safety controls.

# Responsibilities

| Component | Responsibility |
|---|---|
| `remove_svc.yml` | Removes services from shared ingress |
| `register_new_svc.sh` | Performs the ingress registry mutation |
| `gitops/ingress/<env>/values.yaml` | Stores environment-specific routing configuration |
| `validate_gitops.sh` | Validates the resulting GitOps structure |
| `remove_app.yml` | Reconciles application directories that become orphaned |
| Argo CD | Eventually reconciles the committed GitOps state with Kubernetes |

# Design Principle

The workflow follows a simple lifecycle principle:

    Remove routing
         |
         v
    Validate
         |
         v
    Commit
         |
         v
    Reconcile application state separately

Ingress removal and application deletion are deliberately independent
operations so that destructive cleanup is not implicitly coupled to a
routing change.
