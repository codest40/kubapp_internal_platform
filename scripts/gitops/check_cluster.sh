#!/usr/bin/env bash
set -e

echo "Checking ConfigMap..."

CM=$(kubectl get configmap cluster-readiness -n kube-system -o json 2>/dev/null || echo "")

if [ -z "$CM" ]; then
  echo "❌ ConfigMap missing"
  exit 1
fi

STATUS=$(echo "$CM" | jq -r .data.status)
CLUSTER=$(echo "$CM" | jq -r .data.cluster)

echo "Status: $STATUS | Cluster: $CLUSTER"

echo "Checking ArgoCD readiness..."

kubectl rollout status deployment argocd-server -n argocd --timeout=180s
kubectl rollout status deployment argocd-repo-server -n argocd --timeout=180s
kubectl rollout status statefulset argocd-application-controller -n argocd --timeout=180s

echo "✅ System is actually ready"
