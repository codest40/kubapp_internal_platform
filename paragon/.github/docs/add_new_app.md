# KubApp GitOps Provisioning — Add New App

`add_new_app.yml` is the GitOps provisioning workflow responsible for converting application registry metadata into Kubernetes-ready GitOps configuration.

The workflow runs after a successful build or can be triggered manually.

---

## Purpose

The workflow bridges the gap between the **application registry** and the **Kubernetes GitOps configuration**.

    Build Pipeline
          │
          ▼
    gitops/registry/<env>/*.json
          │
          ▼
    add_new_app.yml
          │
          ├── Validate registry/state
          │
          ├── Generate values.yaml
          │
          ├── Generate encrypted secrets
          │
          ├── Register ingress
          │
          └── Validate GitOps
          │
          ▼
    gitops/envs/<env>/
    gitops/ingress/<env>/
          │
          ▼
       Git Commit
          │
          ▼
        Argo CD

---

# Triggers

The workflow supports two execution modes.

## Automatic Trigger

The workflow listens for completion of:

    Build and Push Docker Images

It proceeds only when the build workflow completes successfully.

## Manual Trigger

The workflow can also be started manually with an environment selection.

| Input | Values | Purpose |
|---|---|---|
| `env` | `dev`, `prod` | Environment to provision |

Manual execution is useful for controlled reprovisioning or operational recovery.

---

# Permissions

The workflow requires:

    permissions:
      id-token: write
      contents: read

The GitHub App token generated during the workflow is used for repository operations.

AWS access is provided through GitHub OIDC and the configured AWS IAM role.

---

# Concurrency

The workflow uses:

    concurrency:
      group: using-commit
      cancel-in-progress: false

This prevents multiple workflows from simultaneously modifying the GitOps repository.

The objective is to avoid competing commits against:

    gitops/registry/
    gitops/envs/
    gitops/ingress/
    gitops/state/

The workflow therefore serializes GitOps provisioning operations.

---

# Workflow Stages

## 1. Generate GitHub App Token

The workflow generates a GitHub App installation token using:

    tibdex/github-app-token@v2

The token is used to authenticate repository operations.

---

## 2. Checkout Repository

The workflow checks out:

    paragon40/kubapp

using the generated GitHub App token.

This provides access to:

- GitOps configuration
- Provisioning scripts
- Terraform configuration
- Application registry
- Validation scripts

---

## 3. Configure AWS Credentials

AWS credentials are configured through:

    aws-actions/configure-aws-credentials@v4

The workflow assumes the IAM role supplied through:

    AWS_ROLE_ARN

AWS access is authenticated through GitHub's OIDC mechanism rather than storing long-lived AWS credentials.

The workflow verifies the identity with:

    aws sts get-caller-identity

This confirms that the expected AWS identity is available before provisioning continues.

---

## 4. Prepare Terraform

Terraform is installed using:

    hashicorp/setup-terraform@v3

The workflow later initializes Terraform against the environment-specific backend.

The purpose is to retrieve infrastructure outputs required by application provisioning.

---

## 5. Install Required Tools

The workflow installs or verifies tools required during provisioning:

- `jq`
- `curl`
- `yq`
- `helm`
- `sops`

These tools are used for:

- JSON processing
- YAML processing
- Secret management
- Helm configuration
- GitOps generation

---

# 6. Configure SOPS and AGE

The AGE private key is retrieved from GitHub Actions Secrets and written to:

    ~/.config/sops/age/keys.txt

The file permissions are restricted:

    chmod 600 ~/.config/sops/age/keys.txt

The workflow verifies that the key exists before continuing.

The private key is therefore never committed to the repository.

KubApp uses SOPS with AGE as the standard mechanism for encrypted secrets stored in Git.

Plaintext secret values may exist temporarily in local development or testing environments, but they are not part of the committed GitOps state.

---

# 7. Configure Kubernetes Access

The workflow creates an EKS kubeconfig using:

    aws eks update-kubeconfig

The target cluster is:

    kubapp-dev

The workflow then verifies cluster connectivity using:

    kubectl cluster-info

It also performs an authorization check:

    kubectl auth can-i get pods -A

This ensures that the runner can communicate with the Kubernetes cluster before provisioning continues.

---

# 8. Check Cluster Readiness

The workflow executes:

    scripts/check_cluster.sh

This provides an additional readiness gate before modifying GitOps configuration.

The purpose is to avoid generating deployment configuration when the target cluster is not ready for the downstream deployment process.

---

# State Validation

Before processing applications, the workflow reads:

    gitops/state/current.json

The state file is generated by the build pipeline.

Example structure:

    {
      "env": "dev",
      "run_id": "123456789",
      "workflow": "Build and Push Docker Images",
      "timestamp": "2026-08-16T12:00:00Z"
    }

The workflow validates three important properties.

## Run ID Validation

The workflow compares the state's `run_id` with the current build run.

If they do not match, automatic execution fails.

This prevents an older build's registry from being provisioned accidentally.

Manual execution can bypass this stale-run check.

## Timestamp Validation

The workflow calculates the age of the state file.

If the state is older than the configured maximum age, automatic provisioning fails.

Manual execution can bypass the time check.

## Environment Validation

The workflow extracts the environment from the state file.

The resulting environment becomes the environment used by the provisioning process.

This prevents the workflow from silently selecting an unrelated environment.

---

# Retrieve Terraform Outputs

Terraform is initialized against the selected environment:

    terraform init -reconfigure \
      -backend-config="envs/$ENV/backend.hcl"

The workflow retrieves two infrastructure outputs:

    main_cert_arn
    app_pods_role_arn

These become:

    CERT_ARN
    IRSA_ARN

They are later used when generating application configuration.

The workflow fails if either value cannot be retrieved.

This ensures that required infrastructure dependencies are available before application configuration is generated.

---

# Process Registry

The core provisioning logic scans:

    gitops/registry/$ENV/

Every JSON file represents a service that must be represented in the environment's GitOps configuration.

For every registry entry, the workflow extracts:

- Service name
- Environment
- Service type
- Compute type
- Secret requirements
- Backend service information

The workflow also verifies that the environment recorded in the registry matches the environment being processed.

For example:

    Workflow Environment: dev
    Registry Environment: dev

is valid.

But:

    Workflow Environment: dev
    Registry Environment: prod

causes provisioning to fail.

This prevents cross-environment configuration leakage.

---

# Application Provisioning

Registry entries with:

    type: App

are treated as application workloads.

For each application the workflow determines:

- Service name
- Compute type
- Service port
- Environment
- Runtime variables
- Secret requirements

It then generates the application's deployment values.

---

## Generate Values

The workflow calls:

    scripts/create_values.sh "$file"

The registry JSON acts as the input to the values-generation process.

The generated configuration is placed into the appropriate GitOps environment structure.

The resulting configuration is consumed by the reusable Helm charts during GitOps deployment.

---

## Generate Secrets

If the application contains secrets, the workflow calls:

    scripts/create_secrets.sh "$file"

The workflow determines whether secrets are required from:

    NO_SECRETS

Applications without secrets skip this stage.

Secrets are handled using SOPS and AGE.

The resulting encrypted configuration can therefore be stored safely in Git while the encryption key remains outside the repository.

---

# Ingress Registration

Every application is registered with the shared ingress configuration.

The workflow calls:

    scripts/register_new_svc.sh "$SERVICE" "$ENV"

The registration updates:

    gitops/ingress/<env>/values.yaml

This allows applications to be exposed through the shared ingress architecture without manually editing ingress configuration for every new service.

The application therefore becomes part of the centralized ingress routing model.

---

# Backend Provisioning

Registry entries with:

    type: Backend

represent services that already exist inside the Kubernetes platform.

Examples include:

| Service | Backend Service | Port |
|---|---|---:|
| Grafana | `kube-prometheus-stack-grafana` | 3000 |
| Prometheus | `kube-prometheus-stack-prometheus` | 9090 |
| Alertmanager | `kube-prometheus-stack-alertmanager` | 9093 |
| Argo CD | `argocd-server` | 8080 |

For these services, the workflow reads:

    backendService

and registers the backend with the shared ingress.

Unlike application workloads, these services do not require Docker image provisioning.

---

# GitOps Validation

After all registry entries have been processed, the workflow runs:

    scripts/validate_gitops.sh

This is the final configuration validation before committing changes.

The purpose is to catch:

- Malformed generated files
- Invalid GitOps structure
- Incomplete application configuration
- Inconsistent configuration
- Invalid ingress registration

The workflow therefore follows:

    Generate
       │
       ▼
    Validate
       │
       ├── Failure ──► Stop
       │
       └── Success
              │
              ▼
            Commit

---

# Commit GitOps Changes

Once validation succeeds, the workflow commits the generated configuration using:

    scripts/commit.sh

The committed changes can include:

    gitops/envs/
    gitops/ingress/

The commit becomes part of the GitOps source of truth consumed by the deployment process.

    Registry
       │
       ▼
    Generated GitOps
       │
       ▼
    Validation
       │
       ▼
    Git Commit
       │
       ▼
    Argo CD
       │
       ▼
    Kubernetes

---

# Failure Gates

The workflow intentionally stops when critical provisioning assumptions are violated.

| Check | Failure Condition |
|---|---|
| State file | Missing or empty |
| Run ID | Stale automatic execution |
| Timestamp | State too old |
| Environment | Missing or mismatched |
| Certificate ARN | Terraform output unavailable |
| IRSA ARN | Terraform output unavailable |
| Service | Missing or invalid |
| Registry environment | Does not match workflow environment |
| GitOps validation | Generated configuration invalid |

These gates prevent the workflow from converting incomplete or stale metadata into deployment configuration.

---

# Relationship With Other Workflows

`add_new_app.yml` is not responsible for building the image or deploying the application directly.

Its position in the lifecycle is:

    build.yml
       │
       │ image + registry metadata
       ▼
    add_new_app.yml
       │
       │ GitOps configuration
       ▼
    setup_argocd.yml
       │
       │ Argo CD deployment
       ▼
    verify_runtime.yml
       │
       │ runtime verification
       ▼
    Stable Deployment

---

# End-to-End Provisioning Model

The complete provisioning path is:

    Application Source
           │
           ▼
       build.yml
           │
           ├── Build Docker image
           │
           ├── Push image
           │
           └── Generate registry metadata
           │
           ▼
    gitops/registry/<env>/
           │
           ▼
    add_new_app.yml
           │
           ├── Validate build state
           ├── Validate environment
           ├── Retrieve Terraform outputs
           ├── Generate values
           ├── Generate SOPS secrets
           ├── Register ingress
           └── Validate GitOps
           │
           ▼
    Git Commit
           │
           ▼
    setup_argocd.yml
           │
           ▼
        Argo CD
           │
           ▼
      Helm + Values
           │
           ▼
       Kubernetes
           │
           ▼
    verify_runtime.yml
           │
           ▼
    Verified Deployment

The key responsibility boundary is:

**`build.yml` produces the application artifact and registry metadata.**

**`add_new_app.yml` converts that metadata into GitOps configuration.**

**Argo CD consumes the resulting Git state and reconciles Kubernetes.**
