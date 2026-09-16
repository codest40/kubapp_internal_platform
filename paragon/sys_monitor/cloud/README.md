# Cloud

The `cloud/` directory contains the cloud-provider infrastructure and deployment components used by SysMonitor.

The purpose of this layer is to provide the infrastructure required to run SysMonitor outside the local development environment.

## Cloud Providers

Currently, SysMonitor supports:

| Provider | Directory | Purpose                                                                        |
| -------- | --------- | ------------------------------------------------------------------------------ |
| AWS      | `aws/`    | EC2 infrastructure, networking, IAM, DNS, deployment, and cloud initialization |

The structure is designed so that additional cloud providers can be added independently without mixing their infrastructure with another provider.

## Structure

```text
cloud/
└── aws/
    └── README.md
```

## Responsibilities

The cloud layer is responsible for things such as:

* Provisioning cloud infrastructure.
* Configuring networking.
* Configuring cloud access and IAM.
* Preparing compute resources.
* Bootstrapping instances.
* Deploying SysMonitor to cloud infrastructure.
* Configuring cloud DNS where required.
* Managing cloud-specific Terraform state and configuration.

Provider-specific implementation details are documented inside the corresponding provider directory.

For the current AWS implementation, see [`aws/README.md`](aws/README.md).
