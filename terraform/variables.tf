variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
  default     = "gitops-lab"
}

variable "node_image" {
  description = "kindest/node image, pinned by digest. Must match the kind version bundled in the provider (v0.31.0)."
  type        = string
  default     = "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f"
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 5
    error_message = "worker_count must be between 1 and 5."
  }
}

variable "traefik_chart_version" {
  description = "Traefik Helm chart version."
  type        = string
  default     = "42.1.2"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "10.10.5"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version (bootstraps the root Application)."
  type        = string
  default     = "2.0.7"
}

variable "git_repo_url" {
  description = "Public HTTPS URL of this Git repository; Argo CD watches it."
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/[^/]+/[^/]+\\.git$", var.git_repo_url))
    error_message = "git_repo_url must look like https://github.com/<owner>/<repo>.git"
  }
}

variable "git_revision" {
  description = "Branch Argo CD tracks."
  type        = string
  default     = "main"
}

variable "argocd_host" {
  description = "Hostname for the Argo CD UI Ingress."
  type        = string
  default     = "argocd.127.0.0.1.nip.io"
}
