resource "null_resource" "wait_for_active_eks" {
  triggers = {
    cluster = local.cluster_name
  }

  provisioner "local-exec" {
    command = "aws eks wait cluster-active --name ${local.cluster_name}"
  }
}

resource "null_resource" "wait_for_efs_csi" {
  depends_on = [aws_eks_addon.efs_csi]

  provisioner "local-exec" {
    command = <<EOT
echo "Waiting for EFS CSI controller..."

kubectl rollout status deployment efs-csi-controller -n kube-system --timeout=5m

echo "Waiting for EFS CSI node daemonset..."

kubectl rollout status daemonset efs-csi-node -n kube-system --timeout=5m

echo "EFS CSI fully ready"
EOT
  }
}


resource "kubernetes_config_map_v1" "cluster_readiness" {
  metadata {
    name      = "cluster-readiness"
    namespace = "kube-system"
  }

  data = {
    status    = "initializing"
    cluster   = local.cluster_name
    timestamp = timestamp()
    version   = "1.31"
  }
}

resource "null_resource" "mark_cluster_ready" {
  depends_on = [
    helm_release.argocd,
    helm_release.kube_prometheus_stack,
    kubernetes_config_map_v1.cluster_readiness
  ]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
set -e

echo "Updating kubeconfig..."
aws eks update-kubeconfig --name ${local.cluster_name} --region ${var.region}

echo "Marking cluster as ready..."

kubectl patch configmap cluster-readiness -n kube-system \
  --type merge \
  -p "{\"data\":{\"status\":\"ready\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}"

echo "Cluster marked as READY"
EOT
  }
}

resource "null_resource" "wait_for_lb_webhook" {
  depends_on = [helm_release.lb_controller]

  provisioner "local-exec" {
    command = <<EOT
echo "Waiting for AWS LB webhook..."

kubectl wait --for=condition=available deployment \
  aws-load-balancer-controller \
  -n kube-system \
  --timeout=10m

kubectl get endpoints -n kube-system aws-load-balancer-webhook-service

echo "LB webhook ready"
EOT
  }
}

