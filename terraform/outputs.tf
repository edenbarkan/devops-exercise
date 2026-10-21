output "kubeconfig_path" {
  description = "Path of the kubeconfig written by kind."
  value       = kind_cluster.this.kubeconfig_path
}

output "kube_context" {
  description = "kubectl context for this cluster."
  value       = "kind-${var.cluster_name}"
}

output "argocd_url" {
  description = "Argo CD UI."
  value       = "http://${var.argocd_host}"
}

output "argocd_admin_password_cmd" {
  description = "Command to read the initial Argo CD admin password."
  value       = "kubectl --context kind-${var.cluster_name} -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
