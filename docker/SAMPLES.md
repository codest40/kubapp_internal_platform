# KUBAPP Application Samples

## 1. Application Structure

```text
docker/
└── weather_app/
    ├── Dockerfile
    ├── ci.yml
    ├── kubapp.yml
    ├── secrets.yml
    ├── ci_secrets.yml
    └── app/
        ├── requirements.txt
        ├── pyproject.toml
        ├── entrypoint.sh
        └── application.py
```

## 2. `ci.yml` — Python Component

```yaml
runtime: python

file_paths:
  manifest_files:
    - app/requirements.txt
    - app/pyproject.toml
  docker_file: Dockerfile
  kubapp_file: kubapp.yml
  secret_file: ci_secrets.yml

use_script: false

ci_commands:
  lint:
    - python
    - -m
    - ruff
    - check
    - .

  test:
    - python
    - -m
    - pytest

extra_ci_commands: {}

security_env: []

extra_ci_config:
  healthcheck:
    app_port: 8080
    host_port: 8080
    endpoints:
      - /health
    expected_status: 200
```

## 3. `ci.yml` — Script-Based CI

```yaml
runtime: python

file_paths:
  manifest_files:
    - app/requirements.txt
    - app/pyproject.toml
  docker_file: Dockerfile
  kubapp_file: kubapp.yml
  secret_file: ci_secrets.yml

use_script: true

ci_scripts:
  - scripts/ci.py
  - scripts/security.py

extra_ci_commands: {}

security_env: []

extra_ci_config:
  healthcheck:
    app_port: 8080
    host_port: 8080
    endpoints:
      - /health
    expected_status: 200
```

## 4. `ci.yml` — Node.js Component

```yaml
runtime: node

file_paths:
  manifest_files:
    - app/package.json
    - app/package-lock.json
  docker_file: Dockerfile
  kubapp_file: kubapp.yml
  secret_file: ci_secrets.yml

use_script: false

ci_commands:
  lint:
    - npm
    - run
    - lint

  test:
    - npm
    - test

extra_ci_commands: {}

security_env: []

extra_ci_config:
  healthcheck:
    app_port: 3000
    host_port: 3000
    endpoints:
      - /health
    expected_status: 200
```

## 5. `kubapp.yml`

```yaml
service:
  name: weather
  compute: fargate

app:
  port: 8080
  appUser: weather_app
  healthPath: /health
  livePath: /live
  basePath: /

deploy:
  env: dev
  containerUid: 10006

runtime:
  env:
    ENVIRONMENT: dev
    FEATURE_FLAG: "true"

storage:
  volumes:
    - name: app-tmp
      emptyDir: {}

  volumeMounts:
    - name: app-tmp
      mountPath: /tmp

features:
  serviceMonitor:
    enabled: true
```

## 6. `secrets.yml` — Encrypted Application Secrets

Example of a SOPS-encrypted file's structure:

```yaml
secrets:
  API_KEY: ENC[...]
  DATABASE_PASSWORD: ENC[...]
  EMAIL_PASSWORD: ENC[...]

sops:
  age:
    - enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
      recipient: age1...
  version: 3.13.1
```

The encrypted values and SOPS metadata above are illustrative placeholders, not usable credentials or a valid encrypted file.

## 7. `ci_secrets.yml` — CI Secrets

```yaml
secrets:
  NVD_API_KEY: ENC[...]
  TEST_DB_USER: ENC[...]
  TEST_DB_PASSWORD: ENC[...]

sops:
  age:
    - enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
      recipient: age1...
  version: 3.13.1
```

The exact schema and loading behavior must match the CI secrets implementation. The values above are placeholders, not a valid encrypted file.

## 8. `platform_secrets.yml` — Platform Secrets

```
secrets:
    OPENWEATHER_API_KEY: ENC[..]
    EMAIL_FROM: ENC[...]
    EMAIL_TO: ENC[AES256_GCM,data:fyEBM1FO4wg6ykcaF/I/MFpO08dZ4ekn,iv:so3fW0x9wxjwjHUj6kW/XBDOEwXLtj5a27QlGtYGEa4=,tag:MQal4Mq709fQZElz75od1w==,type:str]
    EMAIL_PASS: ENC[AES256_GCM,data:xOd3JgcTom2KBcBKFkePww==,iv:wpGjs0CDP0hYSLUyO0kzbhOruP6ekY/J4M8IZmzIvME=,tag:8cEROQm/45pzFr6ZfAftjg==,type:str]
sops:
    age:
        - enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            dWqFZ8d7nJMNS4Xf6ArFLYf9ColfbhfAxO4dIxphGStoHvK+aPpaXw==
            -----END AGE ENCRYPTED FILE-----
          recipient: age19xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    lastmodified: "2026-06-08T12:52:45Z"
    mac: ENC[AES256_GCM,data:vZBmPzrLHMnu62jzlLNpI0JCY+jwQuCERKkuM07EDIJ4IKf314uuikXSkvZdOxhzdcchHR2m6JdOA0+x1QNiAL6gbEI3JT0N6RNsNdhfEDQGE/6PsqdiZZnwGttPj5imU4mA8PwzElbkZIwScbRXCqlhuT85adl4bcOjgDV83VE=,iv:I0NXdpNYfmbyTVo0Z33hCkqWhNBR7qb5rKRXpU4uFwg=,tag:zyqtzF2STEd5sMaRjCsCfQ==,type:str]
    unencrypted_suffix: _unencrypted
    version: 3.13.1

```
## 9. `Dockerfile` — Python

```dockerfile
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY app/requirements.txt ./requirements.txt

RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./

RUN useradd --system --uid 10006 appuser \
    && chown -R appuser:appuser /app

USER 10006

EXPOSE 8080

CMD ["python", "application.py"]
```

## 10. Application-Specific Files

### Python

```text
app/
├── requirements.txt
├── pyproject.toml
├── entrypoint.sh
└── application.py
```

### Node.js

```text
app/
├── package.json
├── package-lock.json
├── tsconfig.json
└── src/
    └── index.ts
```

