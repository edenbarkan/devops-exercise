# Traefik replaces ingress-nginx (retired March 2026). It still serves standard
# networking.k8s.io/v1 Ingress resources.
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  namespace        = "traefik"
  create_namespace = true
  wait             = true
  timeout          = 300
  atomic           = true

  values = [yamlencode({
    # Pin to the control-plane node, which owns the host port mappings.
    nodeSelector = { "ingress-ready" = "true" }
    tolerations = [{
      key      = "node-role.kubernetes.io/control-plane"
      operator = "Exists"
      effect   = "NoSchedule"
    }]

    # hostPort binds the node's 80/443 to Traefik's unprivileged 8000/8443.
    ports = {
      web       = { hostPort = 80 }
      websecure = { hostPort = 443 }
    }

    # No cloud LB on kind; traffic arrives via hostPort.
    # (chart >= 42 moved this from service.type to service.spec.type)
    service = { spec = { type = "ClusterIP" } }

    # hostPort pods cannot surge on the same node (port conflict), so replace
    # in place. Ingress-controller downtime on upgrade is acceptable locally.
    updateStrategy = {
      type          = "RollingUpdate"
      rollingUpdate = { maxUnavailable = 1, maxSurge = 0 }
    }

    ingressClass = { enabled = true, isDefaultClass = true, name = "traefik" }

    # By default Traefik copies Ingress status from its own Service. A ClusterIP
    # Service never gets an address, so Ingress status stays empty and Argo CD
    # reports the app as Progressing forever. Publish the loopback address that
    # the hostPort mapping actually serves instead.
    # https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-ingress/
    providers = {
      kubernetesIngress = {
        publishedService = { enabled = false }
        ingressEndpoint  = { ip = "127.0.0.1" }
      }
    }
  })]
}
