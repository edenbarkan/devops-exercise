# The Helm provider is configured from the cluster resource in the same state.
# HashiCorp advises against this pattern because provider config is resolved at
# plan time; it is acceptable for a disposable local cluster. In production,
# split cluster and add-ons into separate states/stacks.
provider "helm" {
  kubernetes = {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}
