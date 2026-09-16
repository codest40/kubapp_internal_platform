resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  values = [
    yamlencode({
      clusterName = local.cluster_name

      serviceAccount = {
        create = false
        name   = kubernetes_service_account_v1.lb_controller.metadata[0].name
      }

      region      = var.region
      vpcId       = local.vpc_id
      installCRDs = true
      podLabels   = local.k8s_labels
    })
  ]

  timeout         = 600
  wait            = true
  cleanup_on_fail = true

  depends_on = [
    null_resource.wait_for_active_eks,
    kubernetes_service_account_v1.lb_controller
  ]
}

resource "helm_release" "external_dns" {
  name      = "external-dns"
  namespace = "kube-system"

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "policy"
    value = "upsert-only"
  }

  set {
    name  = "sources[0]"
    value = "ingress"
  }

  set {
    name  = "txtOwnerId"
    value = local.name_prefix
  }

  set {
    name  = "txtPrefix"
    value = "extdns-"
  }

  set {
    name  = "domainFilters[0]"
    value = local.main_domain
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.external_dns.metadata[0].name
  }

  set {
    name  = "podLabels.plane"
    value = "k8s"
  }

  set {
    name  = "podLabels.project"
    value = var.project
  }

  set {
    name  = "podLabels.env"
    value = local.env
  }

  depends_on = [
    kubernetes_service_account_v1.external_dns,
    helm_release.lb_controller
  ]
}

resource "helm_release" "argocd" {
  name      = "argocd"
  namespace = kubernetes_namespace_v1.this["argocd"].metadata[0].name

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.0"

  create_namespace = true

  values = [
    yamlencode({
      global = {
        podLabels = local.k8s_labels
      }

      server = {
        service = {
          type = "ClusterIP"
        }
      }

      configs = {
        cm = {
          "accounts.ci-user" = "apiKey"
          "accounts.kubapp"  = "login,apiKey"
        }

        rbac = {
          "policy.csv" = <<-EOT
               # For CI role
            p, role:ci, applications, get, */*, allow
            p, role:ci, applications, sync, */*, allow
            p, role:ci, applications, action/*, */*, allow
            p, role:ci, applications, *, */*, allow
            g, ci-user, role:ci

            # Admin UI role
            p, role:admin-ui, applications, *, */*, allow
            p, role:admin-ui, projects, *, *, allow
            p, role:admin-ui, clusters, *, *, allow
            g, kubapp, role:admin-ui
          EOT
        }

        params = {
          "server.url"      = "https://argocd.${local.main_domain}"
          "server.insecure" = "true"
        }
      }
    })
  ]

  timeout         = 2000
  wait            = true
  cleanup_on_fail = true

  depends_on = [
    kubernetes_namespace_v1.this["argocd"],
    helm_release.lb_controller,
    helm_release.fluentbit
  ]
}

resource "helm_release" "fluentbit" {
  name       = "fluent-bit"
  namespace  = "kube-system"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = "0.47.0"

  timeout          = 1200
  wait             = true
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({

      updateStrategy = {
        type = "RollingUpdate"
      }

      serviceAccount = {
        create = false
        name   = "fluent-bit"
      }

      # ------------------------------------------------------------
      # Schedule on all Linux nodes, including tainted app nodes but
      # exclude fargte
      # ------------------------------------------------------------
      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }

      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "eks.amazonaws.com/compute-type"
                    operator = "NotIn"
                    values   = ["fargate"]
                  }
                ]
              }
            ]
          }
        }
      }

      tolerations = [
        {
          operator = "Exists"
        }
      ]

      daemonSetVolumes = [
        {
          name = "varlog"
          hostPath = {
            path = "/var/log"
          }
        },
        {
          name = "varlibdockercontainers"
          hostPath = {
            path = "/var/lib/docker/containers"
          }
        }
      ]

      daemonSetVolumeMounts = [
        {
          name      = "varlog"
          mountPath = "/var/log"
          readOnly  = true
        },
        {
          name      = "varlibdockercontainers"
          mountPath = "/var/lib/docker/containers"
          readOnly  = true
        }
      ]

      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }

        limits = {
          memory = "256Mi"
        }
      }

      podLabels = local.logs_labels

      config = {
        service = <<-EOF
          [SERVICE]
              Flush                     1
              Daemon                    Off
              Log_Level                 info
              Parsers_File              parsers.conf
              HTTP_Server               On
              HTTP_Listen               0.0.0.0
              HTTP_Port                 2020
              Health_Check              On
              storage.path              /var/fluent-bit/state
              storage.sync              normal
              storage.checksum          off
              storage.backlog.mem_limit 50M
        EOF

        inputs = <<-EOF
          [INPUT]
              Name                tail
              Path                /var/log/containers/*.log
              Parser              cri
              Tag                 kube.*
              Refresh_Interval    5
              Rotate_Wait         30
              Mem_Buf_Limit       50MB
              Skip_Long_Lines     On
              DB                  /var/fluent-bit/state/flb_kube.db
              DB.Sync             Normal
              storage.type        filesystem
              Read_from_Head      Off
        EOF

        filters = <<-EOF
          [FILTER]
              Name                kubernetes
              Match               kube.*
              Merge_Log           On
              Keep_Log            Off
              K8S-Logging.Parser  On
              K8S-Logging.Exclude Off

          [FILTER]
              Name                parser
              Match               kube.*
              Key_Name            message
              Parser              json
              Reserve_Data        On
              Preserve_Key        Off

          [FILTER]
              Name                modify
              Match               kube.*
              Copy                kubernetes.namespace_name namespace
              Copy                kubernetes.pod_name       pod
              Copy                kubernetes.container_name container
              Copy                kubernetes.host           node
              Copy                kubernetes.labels.app     app

          [FILTER]
              Name                modify
              Match               kube.*
              Add                 cluster ${local.cluster_name}
              Add                 environment ${local.env}
        EOF

        outputs = <<-EOF
          [OUTPUT]
              Name                cloudwatch_logs
              Match               kube.*
              region              ${var.region}
              log_group_name      ${local.app_logs}
              log_stream_prefix   kubernetes-
              auto_create_group   true
              retry_limit         false
              workers             2
              log_retention_days  30
        EOF
      }
    })
  ]

  depends_on = [
    aws_eks_addon.efs_csi,
    null_resource.wait_for_lb_webhook,
    kubernetes_service_account_v1.fluentbit
  ]
}

resource "helm_release" "kube_prometheus_stack" {
  name      = "kube-prometheus-stack"
  namespace = kubernetes_namespace_v1.this["monitoring"].metadata[0].name

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.0.0"

  timeout         = 1800
  wait            = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      global = {
        podLabels = local.monitoring_labels
      }

      prometheus-node-exporter = {
        affinity = {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [
                {
                  matchExpressions = [
                    {
                      key      = "eks.amazonaws.com/compute-type"
                      operator = "NotIn"
                      values   = ["fargate"]
                    }
                  ]
                }
              ]
            }
          }
        }
      }

      grafana = {
        initChownData = {
          enabled = false
        }

        admin = {
          existingSecret = "grafana-admin"
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }

        "grafana.ini" = {
          "auth.anonymous" = {
            enabled = false
          }

          "security" = {
            disable_initial_admin_creation = false
          }
        }

        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchLabels = local.monitoring_labels
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              }
            ]
          }
        }

        service = {
          type = "ClusterIP"
        }

        persistence = {
          enabled          = true
          storageClassName = kubernetes_storage_class.efs.metadata[0].name
          accessModes      = ["ReadWriteMany"]
          size             = "10Gi"
        }

        podLabels = local.monitoring_labels
      }

      prometheus = {
        prometheusSpec = {
          retention     = "7d"
          retentionSize = "15GB"

          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100
                  podAffinityTerm = {
                    labelSelector = {
                      matchLabels = local.monitoring_labels
                    }
                    topologyKey = "kubernetes.io/hostname"
                  }
                }
              ]
            }
          }

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = kubernetes_storage_class.ebs_gp3.metadata[0].name
                accessModes      = ["ReadWriteOnce"]

                resources = {
                  requests = {
                    storage = "20Gi"
                  }
                }
              }
            }
          }

          podMetadata = {
            labels = local.monitoring_labels
          }
        }
      }

      alertmanager = {
        enabled = true

        alertmanagerSpec = {
          retention = "120h"

          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100
                  podAffinityTerm = {
                    labelSelector = {
                      matchLabels = local.monitoring_labels
                    }
                    topologyKey = "kubernetes.io/hostname"
                  }
                }
              ]
            }
          }

          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = kubernetes_storage_class.efs.metadata[0].name
                accessModes      = ["ReadWriteOnce"]

                resources = {
                  requests = {
                    storage = "5Gi"
                  }
                }
              }
            }
          }

          podMetadata = {
            labels = local.monitoring_labels
          }
        }

        config = {
          global = {
            resolve_timeout    = "5m"
            smtp_smarthost     = "smtp.gmail.com:587"
            smtp_from          = local.alert_email
            smtp_auth_username = local.alert_email
            smtp_auth_password = local.alert_email_password
          }

          route = {
            receiver        = "default"
            group_by        = ["alertname"]
            group_wait      = "30s"
            group_interval  = "5m"
            repeat_interval = "1h"
          }

          receivers = [
            {
              name = "default"
              email_configs = [
                {
                  to            = local.alert_email
                  send_resolved = true
                }
              ]
            },
            {
              name = "null"
            }
          ]

          inhibit_rules = []
        }
      }

      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }
    })
  ]

  depends_on = [
    aws_eks_addon.efs_csi,
    helm_release.fluentbit,
    helm_release.argocd,
    kubernetes_namespace_v1.this["monitoring"],
    null_resource.apply_secrets
  ]
}
