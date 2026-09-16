# CI System

The CI system is the application build and validation layer of KUBAPP.

It discovers applications from the `docker/` directory, detects their runtime from their manifests, loads application-specific CI configuration, runs the required quality gates, builds and pushes Docker images, validates the resulting containers, and produces deployment data for the downstream platform and GitOps stages.

The CI system currently supports:

* Python
* Node.js
* Java

---

## CI Flow

```text
Application Source
        │
        ▼
   docker/<app>_app/
        │
        ▼
 detect_runtime.py
        │
        ├── Discover application
        ├── Detect runtime
        └── Load component ci.yml
        │
        ▼
 dependency_abstractor.py
        │
        ├── Install dependencies
        ├── Lint
        ├── Security analysis
        ├── Unit tests
        ├── Build Docker image
        ├── Validate image
        ├── Authenticate to Docker Hub
        ├── Push image
        └── Start + health-check container
        │
        ▼
 gitops/state/final_ci_data.json
        │
        ▼
 Platform / GitOps stages
```

The important design principle is that **the CI system does not need to know the internal commands of every application**.

The application provides its CI commands through its `ci.yml`, while the platform provides the execution and validation framework.

---

# Directory Structure

```text
scripts/ci/
├── app_builder.py
├── command_policy.py
├── command_policy.json
├── container.py
├── dependency_abstractor.py
├── detect_runtime.py
├── java_handler.py
├── node_handler.py
├── python_handler.py
├── reuse.py
└── variables.py
```

Application CI configuration lives with the application component:

```text
docker/
└── example_app/
    └── api/
        ├── requirements.txt
        ├── Dockerfile
        ├── ci.yml
        └── ...
```

This keeps application-specific CI configuration close to the application itself.

---

# 1. Application Discovery

`detect_runtime.py` is responsible for discovering valid applications.

An application directory must:

* exist under `docker/`
* be a directory
* end with `_app`

Example:

```text
docker/
├── payment_app/
├── user_app/
└── inventory_app/
```

The `_app` suffix provides the first boundary for determining what should be treated as an application.

---

# 2. Runtime Detection

Runtime detection is manifest-based.

The current mappings are:

| Manifest           | Runtime |
| ------------------ | ------- |
| `requirements.txt` | Python  |
| `pyproject.toml`   | Python  |
| `pom.xml`          | Java    |
| `build.gradle`     | Java    |
| `build.gradle.kts` | Java    |
| `package.json`     | Node.js |
| `go.mod`           | Golang  |

The mapping is defined in:

```text
scripts/ci/variables.py
```

Runtime handlers currently exist for:

```text
python
node
java
```

Golang is recognized by the discovery layer but does not currently have a runtime handler.

Therefore, detecting a Golang manifest does not automatically mean Golang CI execution is supported.

---

# 3. Component CI Configuration

Each application component can provide a `ci.yml`.

Example:

```yaml
runtime: python

ci_commands:
  lint:
    - python
    - -m
    - ruff
    - check
    - .

  security:
    - python
    - -m
    - pip_audit

  test:
    - python
    - -m
    - pytest

extra_data:
  healthcheck:
    app_port: 8080
    host_port: 8080
    endpoints:
      - /health
    expected_status: 200
```

The CI system reads this configuration through:

```text
detect_runtime.py
```

The configuration is validated before being passed to the runtime handler.

The configured runtime must match the runtime detected from the application's manifest.

For example:

```yaml
runtime: python
```

cannot be used by an application whose manifest identifies it as Java.

This prevents an application from declaring one runtime while actually being processed as another.

---

# 4. Dependency Abstractor

`dependency_abstractor.py` is the main CI orchestration layer.

It coordinates the complete application build process.

For each valid application component it:

1. Detects the runtime.
2. Loads CI configuration.
3. Selects the runtime handler.
4. Installs dependencies.
5. Runs linting.
6. Runs security analysis.
7. Runs unit tests.
8. Builds the Docker image.
9. Tags the image.
10. Validates the image.
11. Authenticates to Docker Hub.
12. Pushes the image.
13. Starts the pushed image.
14. Performs an application health check.
15. Stops and removes the test container.
16. Stores the resulting application data.

This makes CI a complete **application delivery gate**.

---

# 5. Runtime Handlers

Each supported runtime has its own handler.

```text
PythonHandler
NodeHandler
JavaHandler
```

The handlers expose a common lifecycle:

```text
install_dependencies()
        │
        ▼
lint()
        │
        ▼
security_analysis()
        │
        ▼
unit_tests()
        │
        ▼
build_from_dockerfile()
```

This allows the orchestration layer to remain runtime-independent.

The dependency abstractor does not need separate logic such as:

```text
if python ...
if node ...
if java ...
```

Instead it selects the appropriate handler:

```python
handler_class = get_runtime_handler(runtime)
```

and executes the common CI lifecycle.

---

# 6. Python CI

Python applications support:

### Dependency installation

`requirements.txt`:

```text
python -m pip install -r requirements.txt
```

`pyproject.toml`:

```text
python -m pip install .
```

### CI gates

Python uses application-defined commands for:

* linting
* security analysis
* unit tests

The commands are obtained from `ci.yml`.

---

# 7. Node.js CI

Node.js applications use `package.json` for runtime detection.

If `package-lock.json` exists, CI uses:

```text
npm ci
```

Otherwise:

```text
npm install
```

This allows lockfile-based builds to remain deterministic when a lockfile is available.

Node.js CI also supports application-defined:

* linting
* security analysis
* unit tests

through `ci.yml`.

---

# 8. Java CI

Java applications are detected from:

```text
pom.xml
build.gradle
build.gradle.kts
```

Maven applications install dependencies using:

```text
mvn dependency:resolve
```

Gradle applications use:

```text
./gradlew dependencies
```

Java CI commands are supplied through `ci.yml`.

The Java handler also supports security environment configuration for tools such as OWASP Dependency-Check.

For example:

```yaml
ci_commands:
  security_env:
    - NVD_API_KEY
```

When `security_env` is configured, the required environment variable must exist before the security gate can run.

---

# 9. Command Safety

Application-provided CI commands are not executed blindly.

Before a configured command is executed, it passes through:

```text
command_policy.py
```

The policy validates:

* command structure
* executable
* blocked executables
* shell operators
* runtime-specific arguments
* blocked file extensions

The command must be represented as a list rather than an arbitrary shell string.

Example:

```python
[
    "python",
    "-m",
    "pytest"
]
```

rather than:

```text
python -m pytest
```

This allows CI to execute commands through `subprocess` without invoking a shell.

The safety policy is stored in:

```text
scripts/ci/command_policy.json
```

The runtime handlers call:

```python
ensure_command_is_safe(command, runtime)
```

before executing application-provided CI commands.

---

# 10. Docker Image Build

After the application quality gates pass, the runtime handler builds the Docker image from the application's Dockerfile.

The image name uses the application name and the current Git commit:

```text
<app-name>:<commit-id>
```

The commit identifier provides traceability between:

```text
Git commit
      │
      ▼
Docker image
      │
      ▼
Deployment
```

The image is then tagged for Docker Hub using a timestamp:

```text
<docker-user>/<image>-<timestamp>
```

This gives pushed images a unique timestamp-based identity.

---

# 11. Docker Image Validation

Before pushing, the generated image is validated using Docker:

```text
docker image inspect
```

The CI system verifies that the expected image exists locally.

If validation fails, the application build fails.

---

# 12. Docker Hub Authentication

The CI system requires Docker Hub credentials when an image needs to be pushed.

The expected environment variables are:

```text
DOCKER_USER
DOCKER_PASS
```

Authentication is performed using:

```text
docker login --username <user> --password-stdin
```

The password is provided through standard input rather than being placed directly in the command arguments.

---

# 13. Push

After authentication, the image is pushed to Docker Hub.

A failed push causes the application build to fail.

The resulting image reference is retained as part of the application's CI output.

---

# 14. Runtime Container Validation

A successful Docker build and push does not automatically mean that the application works.

CI therefore starts the pushed image locally.

Example:

```text
docker run -d \
  --name <container> \
  -p <host-port>:<container-port> \
  <image>
```

The application is then tested through its configured HTTP health endpoint.

Example:

```yaml
extra_data:
  healthcheck:
    app_port: 8080
    host_port: 8080
    endpoints:
      - /health
    expected_status: 200
```

CI repeatedly checks the endpoint.

The health check:

* uses HTTP
* validates the expected status code
* retries failed checks
* waits between attempts
* captures container logs when validation ultimately fails

This provides a stronger gate than simply checking whether Docker successfully created the container.

---

# 15. Container Cleanup

The test container is cleaned up after the health check.

The lifecycle is:

```text
Start
  │
  ▼
Health Check
  │
  ├── Success ──────┐
  │                 │
  └── Failure ──────┤
                    ▼
               Stop Container
                    │
                    ▼
               Remove Container
```

Cleanup is performed using a `finally` block so that the container is stopped and removed even when the health check fails.

---

# 16. Parallel Application Builds

Applications are processed concurrently using:

```text
ThreadPoolExecutor
```

The current maximum concurrency is:

```text
MAX_WORKERS = 4
```

Therefore up to four application builds can run simultaneously.

This allows a platform containing multiple independent applications to reduce total CI execution time without creating unlimited local resource consumption.

---

# 17. CI State

After application processing, successful application information is stored in:

```text
gitops/state/final_ci_data.json
```

The state contains:

```json
{
  "env": "dev",
  "apps": {},
  "timestamp": "..."
}
```

Each application entry contains information such as:

```text
image
path
runtime
extra CI data
platform file
secret file
```

This state is intended to be consumed by downstream platform/GitOps stages.

The important separation is:

```text
CI
 │
 └── Produces application delivery data
              │
              ▼
       Platform Build
              │
              ▼
          GitOps
```

CI does not directly perform the complete Kubernetes deployment process.

---

# 18. Failure Behavior

CI treats application failures independently while processing applications concurrently.

If an application fails:

```text
❌ <application>: failed
```

the overall CI result becomes unsuccessful.

After all submitted applications finish, CI reports whether:

```text
All applications completed successfully
```

or:

```text
One or more applications failed
```

The workflow exits with a non-zero status when one or more application builds fail.
This prevents a partially successful CI run from being reported as completely successful.

---

# 19. CI Responsibilities

The CI layer is responsible for:

```text
Application discovery
Runtime detection
CI configuration loading
Dependency installation
Linting
Security analysis
Unit testing
Docker image building
Image validation
Image publishing
Container startup
Application health verification
CI state generation
```

---

# 20. Design Principle

The CI system separates **application knowledge** from **platform execution**.

The application tells KUBAPP:

```text
What runtime am I?
What commands should CI execute?
What environment data does CI need?
How should my container be health-checked?
```

KUBAPP provides:

```text
Discovery
Execution
Command safety
Docker lifecycle
Concurrency
Validation
State generation
```

This allows new applications to be integrated without modifying the central CI orchestrator.
The intended model is:

```text
              Application
                   │
             ci.yml + source
                   │
                   ▼
        ┌─────────────────────┐
        │    KUBAPP CI        │
        │                     │
        │ Discover            │
        │ Detect              │
        │ Validate            │
        │ Build               │
        │ Push                │
        │ Health-check        │
        └──────────┬──────────┘
                   │
                   ▼
          final_ci_data.json
                   │
                   ▼
          Platform / GitOps
```

