# Bootstrap GitOps

## What It Does

The `bootstrap_gitops.sh` script bootstraps Kubapp's GitOps configuration
into an existing Kubernetes cluster.

It:

- Previews the ArgoCD ApplicationSet manifest.
- Applies the ArgoCD ApplicationSet.
- Applies the ArgoCD ingress configuration.
- Checks ArgoCD pods after deployment.
- Checks created ArgoCD Applications and ApplicationSets.
- Checks the application resources in the `dev` namespace.

The script is intended to establish the GitOps resources that allow
ArgoCD to manage the Kubapp applications.

## What It Expects to Already Exist

The script expects:

- A working Kubernetes cluster.
- `kubectl` configured to access that cluster.
- ArgoCD already installed in the `argocd` namespace.
- The Kubapp GitOps manifests to exist at:
  - `gitops/argocd/appset.yaml`
  - `gitops/argocd/ingress.yaml`
- The required ArgoCD CRDs, including `Application` and `ApplicationSet`,
  to already exist.
- A `dev` namespace if the application state is expected to be displayed
  during the final checks.

The script **does not install ArgoCD itself**. It bootstraps the Kubapp
GitOps resources into an existing ArgoCD installation.

