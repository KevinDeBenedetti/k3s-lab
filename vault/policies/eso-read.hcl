# Read-only access for External Secrets Operator (role `eso`, Kubernetes auth).
# Grants every path of the KV v2 mount `secret/`. To narrow it to the paths
# your ExternalSecrets really read, copy this directory into your own
# repository, edit it, and point VAULT_POLICY_DIR at the copy.
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
