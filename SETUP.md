# KubApp Setup

KubApp requires a small amount of user-provided configuration before the
project can initialize its AWS and GitHub infrastructure.

The setup process is:

```text
Clone
  │
  ▼
setup.env
  │
  ▼
Manual GitHub App
  │
  ▼
setup.sh
  │
  ▼
activate.sh
  │
  ▼
Push to GitHub
  │
  ▼
GitHub Actions / CI/CD
```

## 1. Clone the Repository

Clone the repository and enter the project root:

```bash
git clone <repository>
cd kubapp
```

The setup script must be run from a valid Git repository because it uses Git
to determine the project root.

## 2. Create `setup.env`

Create `setup.env` at the **project root**.

Use the project configuration template if one is provided:

```bash
cp setup.env.example setup.env
```

Edit the configuration:

```bash
nano setup.env
```

Provide the required AWS, GitHub, repository, and other project configuration
values expected by `setup_functions.sh`.

`setup.env` is the main user-provided configuration file for the initial
KubApp setup.

Do not commit `setup.env` if it contains credentials, tokens, secrets, or
other sensitive configuration.

## 3. Create the GitHub App Manually

The GitHub App is created and installed manually.

Configure the App for the GitHub account or organization and repository used
by KubApp, including the permissions required by the project.

After the App has been created and installed, provide the required App
configuration in `setup.env`.

The setup script does not create the GitHub App itself. It uses the
configuration supplied for the already-created App.

## 4. Authenticate Required Tools

KubApp setup requires:

```text
AWS CLI
Terraform
GitHub CLI
```

Verify that they are installed:

```bash
aws --version
terraform version
gh --version
```

Authenticate the AWS CLI with an identity that has sufficient permissions for
the KubApp bootstrap.

Verify AWS authentication:

```bash
aws sts get-caller-identity
```

Authenticate the GitHub CLI:

```bash
gh auth login
```

Verify GitHub authentication:

```bash
gh auth status
```

## 5. Run Initial Setup

From the project root:

```bash
./setup.sh
```

The setup script:

1. Verifies the required command-line tools.
2. Loads `setup.env`.
3. Verifies the current AWS identity.
4. Verifies GitHub authentication.
5. Discovers the GitHub repository.
6. Runs the AWS bootstrap under `iac/boot`.
7. Retrieves the GitHub Actions IAM role and AWS region from Terraform.
8. Configures GitHub variables.
9. Configures GitHub secrets.
10. Configures the manually created GitHub App.
11. Installs and configures Infracost.
12. Supplies Terraform backend variables.
13. Reports the resulting repository, AWS region, and GitHub Actions role.

### Setup Flow

```text
                    ┌─────────────────────────────┐
                    │       Clone Repository       │
                    └──────────────┬──────────────┘
                                   │
                                   ▼
                    ┌─────────────────────────────┐
                    │        Create setup.env      │
                    │                             │
                    │ AWS / GitHub / project      │
                    │ configuration values        │
                    └──────────────┬──────────────┘
                                   │
                                   ▼
                    ┌─────────────────────────────┐
                    │   Manually Create GitHub    │
                    │            App              │
                    │                             │
                    │ Create + install App        │
                    │ for the repository          │
                    └──────────────┬──────────────┘
                                   │
                                   ▼
                    ┌─────────────────────────────┐
                    │         ./setup.sh          │
                    └──────────────┬──────────────┘
                                   │
             ┌─────────────────────┼─────────────────────┐
             ▼                     ▼                     ▼
      Check prerequisites    Validate AWS/GitHub    Bootstrap AWS
      aws / terraform / gh   authentication         Terraform backend
                                                         │
                                                         ▼
                                              GitHub variables/secrets
                                                         │
                                                         ▼
                                                 GitHub App setup
                                                         │
                                                         ▼
                                                 Infracost setup
                                                         │
                                                         ▼
                                           Terraform backend variables
                                                         │
                                                         ▼
                    ┌─────────────────────────────┐
                    │      Initial Setup Done     │
                    └─────────────────────────────┘
```

## 6. Activate the Repository

After `setup.sh` completes, run:

```bash
bash scripts/activate.sh
```

`activate.sh` performs the repository activation and pre-push preparation
required before sending the project to GitHub.

After activation completes successfully, push the repository to GitHub.

The exact push command depends on the repository's configured Git remote.

For example:

```bash
git push origin main
```

The intended sequence is therefore:

```text
./setup.sh
      │
      ▼
bash scripts/activate.sh
      │
      ▼
git push
      │
      ▼
GitHub
```

## 7. Start the CI/CD Pipeline

Once the repository has been pushed to GitHub, the GitHub Actions workflows
provide the CI/CD control plane.

The main pipeline entry point is:

```text
.github/workflows/activate_pipeline.yml
```

The pipeline can be started manually from GitHub Actions.

Its available modes are:

```text
full
build
rollback
cleanup
```

The full pipeline follows the major application lifecycle:

```text
CI
 │
 ▼
Platform Build
 │
 ▼
Application / GitOps Provisioning
 │
 ▼
Argo CD Setup
 │
 ▼
GitOps Validation
 │
 ▼
Runtime Verification
```

Rollback and cleanup are separate operational paths.

## 8. Successful Setup

A successful `setup.sh` execution ends with:

```text
========== KUBAPP SETUP COMPLETE ==========
```

The script also reports:

```text
Repository: <repository>
AWS Region: <region>
AWS Role:   <github-actions-role>
```

This confirms that the initial AWS bootstrap, GitHub configuration, and
Terraform backend setup completed successfully.

## Setup Configuration

The setup process is intentionally split between user configuration,
manual administration, and automation:

| Configuration                             | Responsibility                                   |
| ----------------------------------------- | ------------------------------------------------ |
| `setup.env`                               | User-provided project configuration              |
| GitHub App                                | Manually created and installed by the user       |
| `setup.sh`                                | Automated initial project setup                  |
| `iac/boot`                                | AWS/Terraform bootstrap                          |
| GitHub configuration                      | Variables, secrets, and GitHub App configuration |
| `scripts/supply_tf_vars.sh`               | Terraform backend variable setup                 |
| `scripts/activate.sh`                     | Repository activation and pre-push preparation   |
| `.github/workflows/activate_pipeline.yml` | CI/CD pipeline orchestration                     |

## Complete Initialization Flow
```text
┌──────────────────────┐
│   Clone Repository   │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│      setup.env       │
│   User Configuration │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Create GitHub App   │
│   Manually + Install │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│      ./setup.sh      │
│  AWS + GitHub Setup  │
│  Terraform Bootstrap │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ scripts/activate.sh  │
│ Repository Activation│
│   + Pre-push Checks  │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│       git push       │
│       → GitHub       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────────────┐
│ GitHub Actions               │
│ activate_pipeline.yml        │
└──────────────┬───────────────┘
               │
       ┌───────┼──────────┐
       ▼       ▼          ▼
      CI     Build     Operations
       │       │       Rollback /
       │       │        Cleanup
       └───────┘
           │
           ▼
     GitOps / Argo CD
           │
           ▼
       Kubernetes
           │
           ▼
    Runtime Verification
```
