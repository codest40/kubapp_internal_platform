# KUBAPP Security

KUBAPP treats security as an end-to-end property of the application delivery and infrastructure lifecycle, applying a shift-left approach to identify and address security risks as early as possible in the development and delivery process.

Security controls are applied progressively across source control, CI/CD, AWS,
Terraform, secrets, container images, Kubernetes, GitOps, and production 
operations, so security is continuously enforced from code and infrastructure changes through to runtime.

The project follows:

* least privilege
* explicit authorization
* encrypted secrets
* short-lived CI credentials
* controlled deployment permissions
* immutable build artifacts
* environment separation
* auditable infrastructure and deployment changes

This document describes the security controls currently applied by KUBAPP.
It is not a formal compliance certification.

---

## Identity & Access

### GitHub

KUBAPP uses GitHub authentication and a dedicated GitHub App for controlled
repository operations.

GitHub App permissions are restricted to the operations required by the
platform.

Repository and environment permissions are treated as separate security
boundaries.

### AWS

GitHub Actions uses **OIDC → STS → IAM Role** rather than long-lived AWS
access keys.

```text
GitHub Actions
      │
      ▼
GitHub OIDC
      │
      ▼
AWS STS
      │
      ▼
Restricted IAM Role
      │
      ▼
AWS Resources
```

OIDC trust policies restrict which GitHub repository and deployment context
may assume the role.

AWS permissions follow least privilege and are scoped to the resources
required by each workflow.

### Kubernetes

Kubernetes workloads use dedicated service accounts and controlled RBAC.

IAM, Kubernetes RBAC, and workload identities are treated as separate
authorization boundaries.

---

## Secrets

KUBAPP does not store plaintext application secrets in Git.

Application secrets use **SOPS + AGE** encryption.

```text
secrets.yml
     │
     ▼
SOPS + AGE
     │
     ▼
Encrypted Git state
     │
     ▼
Authorized workflow
     │
     ▼
Controlled decryption
     │
     ▼
Runtime secret
```

AGE private keys remain outside the repository.

Private keys are never:

* committed to Git
* embedded in images
* written into manifests
* exposed in workflow output
* included in build artifacts

`.sops.yaml` defines the encryption recipients used by the repository.

Decryption is restricted to authorized environments and workflows that require
the secret.

---

## CI/CD Security

GitHub Actions workflows explicitly declare required permissions.

Typical permissions are limited to the operation being performed, with
additional privileges such as:

```text
id-token: write
contents: write
pull-requests: write
security-events: write
```

only where required.

Reusable workflows receive controlled inputs and inherited secrets only where
necessary.

Production workflows are separated from development execution through
environment selection and deployment controls.

Destructive operations are not part of the normal application build path.

---

## Source & Supply Chain

Application admission requires the KUBAPP application contract, including:

```text
*_app/
├── Dockerfile
└── ci.yml
```

CI validates application-specific commands before the application enters the
deployment pipeline.

Security controls include:

* dependency checks
* application security checks
* infrastructure scanning
* Kubernetes manifest validation
* container image scanning
* controlled image generation

Build artifacts remain traceable to their source commit.

---

## Container Security

KUBAPP treats application images as deployment artifacts rather than trusted
application inputs.

Applications are expected to:

* use controlled base images
* avoid embedded credentials
* minimize runtime privileges
* use appropriate security contexts
* expose only required ports
* use runtime health checks

Where supported, workloads use non-root execution and read-only filesystems.

Secrets are injected at runtime rather than incorporated into container
images.

---

## Terraform Security

Terraform state is treated as sensitive infrastructure data.

Remote state uses encrypted S3 storage with locking.

The DNS Terraform stack has its own dedicated state backend and is isolated
from the main KUBAPP infrastructure state.

Terraform execution identities are restricted to the infrastructure they
manage.

Infrastructure changes are executed through controlled workflows and remain
reviewable through Git.

---

## GitOps Security

GitOps state is treated as deployment state.

Only controlled workflows should modify generated deployment configuration.

The deployment path is:

```text
Source
  │
  ▼
CI
  │
  ▼
Container Image
  │
  ▼
GitOps State
  │
  ▼
Argo CD
  │
  ▼
Kubernetes
```

Application source access does not automatically imply unrestricted
infrastructure or production deployment access.

---

## Kubernetes Security

KUBAPP applies security controls at workload and cluster boundaries.

Controls include:

* Kubernetes RBAC
* dedicated service accounts
* workload security contexts
* non-root execution where supported
* restricted privilege escalation
* controlled Linux capabilities
* read-only filesystems where supported
* runtime secret injection
* health probes
* network restrictions where configured

Kubernetes access is separated from AWS infrastructure access.

---

## Network Security

Network exposure follows the intended application traffic path.

```text
Internet
   │
   ▼
AWS Load Balancer
   │
   ▼
Kubernetes Service
   │
   ▼
Application Pod
```

Internal workloads are not exposed externally unless explicitly required.

Network-level restrictions are applied through AWS networking and Kubernetes
network controls where required by the workload.

---

## Deployment & Production Security

Production changes are treated as privileged operations.

KUBAPP separates:

* application build
* GitOps generation
* deployment
* runtime verification
* rollback
* cleanup

Rollback uses recorded stable deployment commits and tags.

Before rollback, the supplied stable tag is verified against its recorded
commit.

Destructive operations such as infrastructure destruction, state deletion,
application removal, and full Git history rollback require explicit execution
and safety checks.

---

## Observability & Auditability

Security-relevant operations remain attributable through GitHub, AWS,
Terraform, Git, and Kubernetes records.

Relevant events include:

* IAM role assumptions
* infrastructure changes
* GitOps changes
* deployments
* rollbacks
* operational actions
* security scanning results

Sensitive values are excluded from logs and workflow output.

---

## Security Boundaries

KUBAPP deliberately separates security boundaries across:

```text
GitHub
   │
   ├── Repository / App permissions
   │
   ▼
GitHub Actions
   │
   ├── OIDC
   ├── Workflow permissions
   └── Environment controls
   │
   ▼
AWS
   │
   ├── IAM
   ├── Terraform
   └── Networking
   │
   ▼
Kubernetes
   │
   ├── RBAC
   ├── Service Accounts
   ├── Security Contexts
   └── Network Controls
   │
   ▼
Application Runtime
```

No single identity is intended to provide unrestricted access across the
entire platform.

---

## Security Checklist

### Identity & Access

* [ ] GitHub App permissions are restricted
* [ ] GitHub Actions permissions are reviewed
* [ ] AWS OIDC trust policy is restricted
* [ ] IAM policies follow least privilege
* [ ] Kubernetes RBAC is restricted

### Secrets

* [ ] No plaintext secrets committed
* [ ] SOPS/AGE configured
* [ ] AGE private key remains outside Git
* [ ] Decryption occurs only in authorized contexts
* [ ] Secrets are not embedded in images
* [ ] Decrypted secrets are not exposed in logs

### CI/CD

* [ ] Application contains required `Dockerfile` and `ci.yml`
* [ ] Dependencies are checked
* [ ] Security scans are enabled
* [ ] Container images are scanned
* [ ] Production changes are controlled
* [ ] Build artifacts are traceable to source commits

### Infrastructure

* [ ] Terraform state is encrypted
* [ ] Terraform state access is restricted
* [ ] AWS credentials are not stored in Git
* [ ] Infrastructure changes are reviewable
* [ ] Destructive operations are explicitly controlled

### Kubernetes

* [ ] Workloads use appropriate security contexts
* [ ] Workloads avoid unnecessary privileges
* [ ] Service accounts and RBAC are restricted
* [ ] Runtime secrets are protected
* [ ] Network exposure is intentional
* [ ] Runtime health checks are configured

