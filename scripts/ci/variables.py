MANIFESTS = {
    "requirements.txt": "python",
    "pyproject.toml": "python",
    "package.json": "node",
    "tsconfig.json": "node",
}

RUNTIME_IMAGES = {
    "python": "docker.io/library/python:3.12-slim",
    "node": "docker.io/library/node:22-slim",
}

RUNTIME_DEPENDENCY_CONFIG = {
    "python": {
        "dependency_path": "venv",
        "executable_path": "venv/bin",
        "required_path": "venv/bin/python",
    },
    "node": {
        "dependency_path": "node_modules",
        "executable_path": "node_modules/.bin",
        "required_path": "node_modules/.package-lock.json",
    },
}

EXTRA_MANIFESTS = {
    "package-lock.json": "node",
}

CACHE_RUNTIMES = {}
CI_COMMANDS = {}

COMPONENT_ENV_ALLOWLIST = {
    "DOCKER_USER",
    "DOCKER_PASS",
    "ENV",
}

