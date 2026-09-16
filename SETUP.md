# KubApp Setup

KubApp requires a small amount of user-provided configuration before the
project can initialize its AWS and GitHub infrastructure.

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

This file contains the configuration required by the setup process.

```bash
cp setup.env.example setup.env
```

Edit the values:

```bash
nano setup.env
```

Provide the required AWS, GitHub, repository, and other project configuration
values expected by `setup_functions.sh`.

Do not commit `setup.env` if it contains credentials, tokens, secrets, or
other sensitive configuration.

## 3. Create the GitHub App Manually

The GitHub App should be created and configured manually before running the
setup script.

Configure the App for the GitHub account/organization and repository used by
KubApp, including the required permissions and installation.

After the App has been created and installed, provide the required App
configuration in `setup.env`.

This keeps GitHub App creation as an explicit administrative step rather than
having the setup script attempt to create the App itself.

## 4. Authenticate Required Tools

KubApp setup requires:

```text
AWS CLI
Terraform
GitHub CLI
```

Verify them:

```bash
aws --version
terraform version
gh --version
```

Authenticate the AWS CLI with an identity that has sufficient permissions
for the KubApp bootstrap.

Verify AWS authentication:

```bash
aws sts get-caller-identity
```

Authenticate GitHub CLI:

```bash
gh auth login
```

Verify:

```bash
gh auth status
```

## 5. Run Setup

From the project root:

```bash
./setup.sh
```

The setup script performs the following initialization:

```text
setup.env
    │
    ├── AWS configuration
    ├── GitHub configuration
    └── KubApp configuration
             │
             ▼
        AWS Bootstrap
             │
             ▼
     Terraform Backend
             │
             ▼
      GitHub Configuration
             │
       ┌─────┴─────┐
       ▼           ▼
    Variables    Secrets
             │
             ▼
       GitHub App
             │
             ▼
       Infracost
             │
             ▼
   Terraform Backend Variables
```

The script:

1. Verifies the required command-line tools.
2. Loads `setup.env`.
3. Verifies the current AWS identity.
4. Verifies GitHub authentication and discovers the repository.
5. Runs the AWS bootstrap under `iac/boot`.
6. Retrieves the GitHub Actions IAM role and AWS region from Terraform.
7. Configures GitHub variables and secrets.
8. Configures the manually created GitHub App.
9. Installs and configures Infracost.
10. Supplies Terraform backend variables.
11. Reports the resulting repository, AWS region, and GitHub Actions role.

## 6. Successful Setup

A successful setup ends with:

```text
========== KUBAPP SETUP COMPLETE ==========
```

The script also reports:

```text
Repository: <repository>
AWS Region: <region>
AWS Role:   <github-actions-role>
```

At this point the repository has its initial AWS bootstrap, GitHub
configuration, and Terraform backend configuration required for the remaining
KubApp infrastructure workflows.

## Setup Configuration

The setup process is intentionally split into two parts:

| Configuration               | Responsibility                             |
| --------------------------- | ------------------------------------------ |
| `setup.env`                 | User-provided project configuration        |
| GitHub App                  | Manually created and installed by the user |
| `setup.sh`                  | Automated project initialization           |
| `iac/boot`                  | AWS/Terraform bootstrap                    |
| GitHub configuration        | Variables, secrets, and App configuration  |
| `scripts/supply_tf_vars.sh` | Terraform backend configuration            |

`setup.env` is therefore the main configuration entry point for a new KubApp
installation, while GitHub App creation remains an explicit manual
administrative step.
