# Human administrator, granted through OIDC (role `default`, bound to
# ADMIN_EMAIL). Only written to a role when OIDC is configured.
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list", "delete"]
}
path "sys/health" {
  capabilities = ["read", "sudo"]
}
path "sys/seal-status" {
  capabilities = ["read"]
}
path "sys/policies/*" {
  capabilities = ["read", "list"]
}
path "auth/*" {
  capabilities = ["read", "list"]
}
