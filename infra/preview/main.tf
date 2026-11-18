terraform {
  backend "local" {}

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig)
  config_context = var.kube_context
}

locals {
  app_labels = { app = "myapp" }
}

resource "kubernetes_namespace_v1" "preview" {
  metadata {
    name = "pr-${var.pr_number}"
    labels = {
      purpose = "preview"
      pr      = var.pr_number
      owner   = var.owner
      expires = var.expires
    }
  }
}

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = "myapp"
    namespace = kubernetes_namespace_v1.preview.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.app_labels
    }

    template {
      metadata {
        labels = local.app_labels
      }

      spec {
        automount_service_account_token = false
        enable_service_links            = false

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          run_as_group    = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "myapp"
          image = var.image

          port {
            container_port = 3000
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          resources {
            requests = { cpu = "100m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name      = "myapp"
    namespace = kubernetes_namespace_v1.preview.metadata[0].name
  }

  spec {
    selector = local.app_labels
    type     = "ClusterIP"

    port {
      port        = 80
      target_port = 3000
    }
  }
}
