resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600
  atomic           = true

  values = [yamlencode({
    global = { domain = var.argocd_host }

    # No SSO locally; the built-in admin user is enough.
    dex = { enabled = false }

    configs = {
      # TLS terminates at (or is skipped by) the ingress; the UI is plain HTTP locally.
      params = { "server.insecure" = true }
      # A localhost cluster can't receive GitHub webhooks, so poll faster.
      cm = {
        "timeout.reconciliation"        = "30s"
        "timeout.reconciliation.jitter" = "5s"
      }
    }

    server = {
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hostname         = var.argocd_host
      }
    }
  })]

  depends_on = [helm_release.traefik]
}

# Root "app of apps". Installed via the argocd-apps chart instead of
# kubernetes_manifest, which needs the Application CRD at PLAN time and so
# fails on a fresh cluster.
resource "helm_release" "argocd_root_app" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = "argocd"
  wait       = true
  timeout    = 300
  atomic     = true

  values = [yamlencode({
    applications = {
      root = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.git_repo_url
          targetRevision = var.git_revision
          path           = "argocd"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
