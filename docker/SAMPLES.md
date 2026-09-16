# Application Samples

Examples of the files commonly found in a KUBAPP application.

## Application Structure

```text
weather_app/
├── Dockerfile
├── ci.yml
├── kubapp.yml
├── secrets.yml
└── app/
    ├── requirements.txt
    ├── entrypoint.sh
    └── application.py
```

## `ci.yml`

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
    - bandit
    - -r
    - .

  security_env: []

  test:
    - python
    - -m
    - pytest

  build:
    - python
    - -m
    - build

extra_data:
  healthcheck:
    app_port: 8080
    host_port: 8080
    endpoints:
      - /health
    expected_status: 200
```

## `kubapp.yml`

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
    DATABASE_URL: <database-url>
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

## `secrets.yml` after running scripts/activate.sh

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

## Application-Specific Files

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
```

### Java

```text
app/
├── pom.xml
└── src/
    └── main/
```

### Go

```text
app/
├── go.mod
├── go.sum
└── main.go
```

These files are application-specific and are not required by KUBAPP's
discovery contract.
