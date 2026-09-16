# Docker

The `docker/` directory contains the applications managed by KUBAPP.

## Application Contract

Each application must:

* use a directory name ending in `_app`
* contain a `Dockerfile`
* contain a `ci.yml`

Optional:

* `kubapp.yml` — deployment/runtime configuration
* `secrets.yml` — encrypted secrets, when required

Example:

```text
docker/
└── transaction_app/
    ├── Dockerfile
    ├── ci.yml
    ├── kubapp.yml
    ├── secrets.yml
    └── application manifests + source code
```

`Dockerfile` and `ci.yml` are required for discovery. Applications that do not
meet the contract are not discovered by KUBAPP.

For file examples, see [SAMPLES.md](./SAMPLES.md).

## Application Discovery

KUBAPP discovers applications from the directory structure:

```text
docker/
├── weather_app/
│   ├── Dockerfile
│   └── ci.yml
│
├── incomplete_app/
│   └── Dockerfile
│
└── regular_directory/
    ├── Dockerfile
    └── ci.yml
```

Result:

```text
weather_app
  ✓ *_app
  ✓ Dockerfile
  ✓ ci.yml
  → DISCOVERED

incomplete_app
  ✓ *_app
  ✓ Dockerfile
  ✗ ci.yml
  → OVERLOOKED

regular_directory
  ✗ *_app
  ✓ Dockerfile
  ✓ ci.yml
  → OVERLOOKED
```

The `_app` naming convention, `Dockerfile`, and `ci.yml` form the minimum
application contract.

## Configuration

### `ci.yml`

Defines application-specific CI operations such as:

* linting
* security checks
* tests
* build commands
* healthcheck information

### `kubapp.yml`

Defines optional KUBAPP deployment and runtime configuration such as:

* compute
* ports
* health endpoints
* environment
* storage
* platform features

### `secrets.yml`

Defines encrypted application secrets.

Secrets are encrypted with SOPS after you run **./scripts/activate.sh** before repo is committed and pushed.
Plaintext credentials must not be committed to Git.
Ensure SOPS is set up and the key added in setup.env
See How to set up SOPS [SOPS.md](../SOPS.md)

## Application Files

Files required by the application runtime remain application-specific.
Examples include:

```text
Python:  .py, .txt, .toml
Node:    .js, .ts, .json
Java:    .java, .xml
Go:      .go, .mod, .sum
```

KUBAPP does not impose a specific application runtime or framework.

## Platform Flow

```text
*_app/
   │
   ├── Dockerfile
   ├── ci.yml
   ├── kubapp.yml    (optional)
   └── secrets.yml   (optional)
          │
          ▼
   Application Discovery
          │
          ▼
      KUBAPP CI/CD
          │
          ▼
    Container Image
          │
          ▼
    KUBAPP Platform
          │
          ▼
       Kubernetes
```

The application provides the required contract; KUBAPP handles discovery,
validation, packaging, and deployment through the platform workflow.

