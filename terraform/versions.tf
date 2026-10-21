terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11.0" # bundles sigs.k8s.io/kind v0.31.0
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }

  # State is local on purpose: this is a single-user local cluster.
  # Production would use an S3 backend with use_lockfile = true.
}
