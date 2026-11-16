# shellcheck shell=bash
# lib/vault.sh — Vault bootstrap: everything between a running Vault pod and a
# Vault that External Secrets can read from.
#
# Source it after lib/log.sh (lib/script-init.sh does that):
#   _lib vault.sh
#
# What a caller needs to know:
#
#   vault_require_tools        fail early when kubectl or jq is missing
#   vault_wait_ready           wait for the Vault pod to be Ready
#   vault_check_reachable      fail when Vault does not answer `status`
#   vault_is_initialized       exit 0 when Vault is initialised
#   vault_is_sealed            exit 0 when Vault is sealed
#   vault_initialize           one-time `operator init`; prints the keys and the
#                              root token, sets VAULT_TOKEN and VAULT_UNSEAL_KEY_n
#   vault_unseal               feed VAULT_UNSEAL_KEY_1, _2, … until unsealed
#   vault_use_root_token       set VAULT_TOKEN from VAULT_ROOT_TOKEN (or prompt)
#   vault_configure            idempotent: KV engine, Kubernetes auth, policies,
#                              External Secrets role, OIDC
#   vault_exec <vault args>    run `vault` in the pod with VAULT_TOKEN
#
# Configuration (environment, all optional unless noted):
#   KUBECONFIG_CONTEXT    kubectl context                 default: k3s-lab
#   VAULT_NAMESPACE       namespace of the Vault pod      default: vault
#   VAULT_POD             Vault pod name                  default: vault-0
#   ESO_NAMESPACE         External Secrets namespace      default: external-secrets
#   ESO_SA                External Secrets ServiceAccount default: external-secrets
#   VAULT_POLICY_DIR      directory of *.hcl policies     default: <repo>/vault/policies
#   VAULT_KEY_SHARES      unseal keys created at init     default: 3
#   VAULT_KEY_THRESHOLD   keys needed to unseal           default: 2
#   VAULT_ROOT_TOKEN      root token (prompted when unset and a terminal exists)
#   VAULT_UNSEAL_KEY_<n>  unseal keys (prompted likewise)
#   OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OIDC_ISSUER_URL, VAULT_DOMAIN,
#   ADMIN_EMAIL           all five = OIDC is configured; none = skipped;
#                         only some = error
#
# The seam: every cluster call goes through ${KUBECTL} (default `kubectl`).
# tests/bats/vault.bats puts a fake there; nothing else in this file knows
# whether the Vault on the other side is real.
#
# Secrets (root token, unseal keys) travel on STDIN, never as process
# arguments: argv is visible in local `ps`, in the kubectl exec API request and
# inside the pod — stdin is none of those.
# ──────────────────────────────────────────────────────────────────────────────

KUBECTL="${KUBECTL:-kubectl}"
KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-lab}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_SA="${ESO_SA:-external-secrets}"
VAULT_KEY_SHARES="${VAULT_KEY_SHARES:-3}"
VAULT_KEY_THRESHOLD="${VAULT_KEY_THRESHOLD:-2}"
VAULT_POLICY_DIR="${VAULT_POLICY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vault/policies}"

# Policies the roles below point at. Configure refuses to run without them.
_VAULT_ESO_POLICY="eso-read"
_VAULT_ADMIN_POLICY="vault-admin"

# The five values OIDC needs. ADMIN_EMAIL is part of the set on purpose:
# without it the role would have no bound_claims and ANY account at the
# provider would get vault-admin.
_VAULT_OIDC_VARS=(OIDC_CLIENT_ID OIDC_CLIENT_SECRET OIDC_ISSUER_URL VAULT_DOMAIN ADMIN_EMAIL)

# The `vault` CLI runs INSIDE the Vault pod and talks to Vault on localhost, so
# the TLS check it skips is on a connection that never leaves the pod. Set here
# only; verifying it would mean shipping the CA into the pod's CLI environment,
# which is the chart's business.
_VAULT_CLI_ENV='export VAULT_SKIP_VERIFY=true'

# ── Cluster access (the seam) ────────────────────────────────────────────────

_vault_kubectl() {
  "${KUBECTL}" --context "${KUBECONFIG_CONTEXT}" "$@"
}

# _vault_pod_sh <script> <argv0> [args…] — run a shell snippet in the Vault pod,
# stdin attached.
_vault_pod_sh() {
  _vault_kubectl exec -i -n "${VAULT_NAMESPACE}" "${VAULT_POD}" -- sh -c "$@"
}

# vault_exec <vault args…> — for commands that do not read stdin themselves.
vault_exec() {
  printf '%s\n' "${VAULT_TOKEN:-}" \
    | _vault_pod_sh "IFS= read -r VAULT_TOKEN; export VAULT_TOKEN; ${_VAULT_CLI_ENV}; exec vault \"\$@\"" vault-cli "$@"
}

# vault_exec_stdin <vault args…> — same, and the caller's stdin follows the
# token line (policy write reads its HCL from there).
vault_exec_stdin() {
  { printf '%s\n' "${VAULT_TOKEN:-}"; cat; } \
    | _vault_pod_sh "IFS= read -r VAULT_TOKEN; export VAULT_TOKEN; ${_VAULT_CLI_ENV}; exec vault \"\$@\"" vault-cli "$@"
}

# _vault_unseal_key <key> — the key on stdin; argv only inside the container.
_vault_unseal_key() {
  printf '%s\n' "$1" \
    | _vault_pod_sh "IFS= read -r k; ${_VAULT_CLI_ENV}; exec vault operator unseal \"\$k\"" vault-unseal
}

# ── Preconditions and state ──────────────────────────────────────────────────

vault_require_tools() {
  local tool missing=0
  for tool in "${KUBECTL}" jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_error "${tool} is required but not installed"
      missing=1
    fi
  done
  return "$missing"
}

vault_wait_ready() {
  log_info "Waiting for Vault pod to be Ready..."
  _vault_kubectl wait "pod/${VAULT_POD}" -n "${VAULT_NAMESPACE}" \
    --for=condition=Ready --timeout=120s
}

# _vault_status_json — `vault status` exits 0 (unsealed), 1 (error) or 2
# (sealed); all but the error case print JSON. Empty output = unreachable.
_vault_status_json() {
  VAULT_TOKEN="" vault_exec status -format=json 2>/dev/null || true
}

# vault_check_reachable — fail loudly when Vault does not answer. The two
# predicates below cannot tell "unreachable" from "false", so callers check
# this first.
vault_check_reachable() {
  if [[ -z "$(_vault_status_json)" ]]; then
    log_error "Cannot reach Vault — is pod ${VAULT_POD} running in namespace ${VAULT_NAMESPACE}?"
    return 1
  fi
}

_vault_status_field() {
  _vault_status_json | jq -r --arg f "$1" '.[$f] // false' 2>/dev/null
}

vault_is_initialized() { [[ "$(_vault_status_field initialized)" == "true" ]]; }
vault_is_sealed() { [[ "$(_vault_status_field sealed)" == "true" ]]; }

# _vault_prompt_secret <label> — read a secret from the terminal, print it.
# Fails when there is no terminal: a missing secret must not become an empty one.
_vault_prompt_secret() {
  local value
  if ! { : </dev/tty; } 2>/dev/null; then
    log_error "$1 is not set and there is no terminal to ask for it"
    return 1
  fi
  read -r -s -p "  $1: " value </dev/tty
  echo "" >/dev/tty
  printf '%s\n' "$value"
}

# ── Initialise ───────────────────────────────────────────────────────────────

# vault_initialize — one-time creation of the unseal keys and the root token.
# Prints them (they are never shown again), then leaves them in VAULT_TOKEN and
# VAULT_UNSEAL_KEY_<n> for the rest of the run.
vault_initialize() {
  local out i key
  log_step "Initializing Vault (${VAULT_KEY_SHARES} key shares, threshold ${VAULT_KEY_THRESHOLD})..."
  out="$(VAULT_TOKEN="" vault_exec operator init \
    -key-shares="${VAULT_KEY_SHARES}" \
    -key-threshold="${VAULT_KEY_THRESHOLD}" \
    -format=json)"

  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  ⚠️  VAULT INIT OUTPUT — SAVE THIS IMMEDIATELY"
  echo "  These keys and token will NEVER be shown again."
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  jq -r '.unseal_keys_b64 | to_entries[] | "Unseal Key \(.key + 1): \(.value)"' <<<"$out"
  echo ""
  echo "Root Token:   $(jq -r '.root_token' <<<"$out")"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""

  i=1
  while IFS= read -r key; do
    printf -v "VAULT_UNSEAL_KEY_${i}" '%s' "$key"
    i=$((i + 1))
  done < <(jq -r '.unseal_keys_b64[]' <<<"$out")
  VAULT_TOKEN="$(jq -r '.root_token' <<<"$out")"
}

# ── Unseal ───────────────────────────────────────────────────────────────────

# vault_unseal — feed VAULT_UNSEAL_KEY_1, _2, … one at a time and stop as soon
# as Vault reports unsealed. A key that is not set is asked for on the terminal.
vault_unseal() {
  local i=1 var key
  vault_check_reachable || return 1
  if ! vault_is_sealed; then
    log_info "Vault is already unsealed"
    return 0
  fi
  log_step "Unsealing Vault..."
  while vault_is_sealed; do
    if [[ "$i" -gt "${VAULT_KEY_SHARES}" ]]; then
      log_error "Vault is still sealed after ${VAULT_KEY_SHARES} key(s) — wrong keys?"
      return 1
    fi
    var="VAULT_UNSEAL_KEY_${i}"
    key="${!var:-}"
    if [[ -z "$key" ]]; then
      key="$(_vault_prompt_secret "Unseal Key ${i}")" || return 1
    fi
    _vault_unseal_key "$key" >/dev/null
    i=$((i + 1))
  done
  log_ok "Vault unsealed"
}

# ── Token ────────────────────────────────────────────────────────────────────

# vault_use_root_token — make VAULT_TOKEN usable for the configure steps:
# keep one already set (fresh init), else VAULT_ROOT_TOKEN, else ask.
vault_use_root_token() {
  if [[ -z "${VAULT_TOKEN:-}" ]]; then
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
      VAULT_TOKEN="${VAULT_ROOT_TOKEN}"
    else
      VAULT_TOKEN="$(_vault_prompt_secret "Vault root token")" || return 1
    fi
  fi
  if [[ -z "${VAULT_TOKEN}" ]]; then
    log_error "No root token provided — cannot continue"
    return 1
  fi
  if ! vault_exec token lookup >/dev/null 2>&1; then
    log_error "Invalid or expired root token — check VAULT_ROOT_TOKEN in .env"
    return 1
  fi
}

# ── Configure ────────────────────────────────────────────────────────────────

# _vault_mount_enabled <secrets|auth> <path/> — is that mount listed?
_vault_mount_enabled() {
  vault_exec "$1" list -format=json 2>/dev/null | jq -e --arg p "$2" 'has($p)' >/dev/null 2>&1
}

# _vault_oidc_missing — print the OIDC variables that are not set, one per line.
_vault_oidc_missing() {
  local var
  for var in "${_VAULT_OIDC_VARS[@]}"; do
    [[ -n "${!var:-}" ]] || printf '%s\n' "$var"
  done
}

# vault_oidc_mode — prints `all`, `none` or `partial`.
vault_oidc_mode() {
  local missing
  missing="$(_vault_oidc_missing | wc -l | tr -d ' ')"
  if [[ "$missing" -eq 0 ]]; then
    echo all
  elif [[ "$missing" -eq "${#_VAULT_OIDC_VARS[@]}" ]]; then
    echo none
  else
    echo partial
  fi
}

# _vault_check_inputs — everything that can be refused BEFORE touching Vault:
# a half-set OIDC configuration and a policy directory missing a policy a role
# points at. Checked first so a refusal never leaves Vault half-configured.
_vault_check_inputs() {
  local mode="$1" policy errors=0
  if [[ "$mode" == "partial" ]]; then
    log_error "OIDC is only partly configured. Missing: $(_vault_oidc_missing | tr '\n' ' ')"
    log_error "Set all of ${_VAULT_OIDC_VARS[*]} — or none of them to skip OIDC."
    errors=1
  fi
  if [[ ! -d "${VAULT_POLICY_DIR}" ]]; then
    log_error "Policy directory not found: ${VAULT_POLICY_DIR}"
    return 1
  fi
  for policy in "${_VAULT_ESO_POLICY}" "${_VAULT_ADMIN_POLICY}"; do
    [[ "$policy" == "${_VAULT_ADMIN_POLICY}" && "$mode" != "all" ]] && continue
    if [[ ! -f "${VAULT_POLICY_DIR}/${policy}.hcl" ]]; then
      log_error "Required policy missing: ${VAULT_POLICY_DIR}/${policy}.hcl"
      errors=1
    fi
  done
  return "$errors"
}

# _vault_apply_policies — every *.hcl in the policy directory becomes a policy
# named after its file.
_vault_apply_policies() {
  local file name
  for file in "${VAULT_POLICY_DIR}"/*.hcl; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file" .hcl)"
    vault_exec_stdin policy write "$name" - <"$file" >/dev/null
    log_info "policy ${name}"
  done
}

_vault_configure_oidc() {
  log_step "Configuring OIDC auth method..."
  if _vault_mount_enabled auth oidc/; then
    log_info "OIDC auth already enabled — updating config"
  else
    vault_exec auth enable oidc
  fi

  # The client secret goes through stdin as JSON, not through argv.
  jq -n \
    --arg url "${OIDC_ISSUER_URL}" \
    --arg id "${OIDC_CLIENT_ID}" \
    --arg secret "${OIDC_CLIENT_SECRET}" \
    '{oidc_discovery_url: $url, oidc_client_id: $id, oidc_client_secret: $secret, default_role: "default"}' \
    | vault_exec_stdin write auth/oidc/config - >/dev/null

  vault_exec write auth/oidc/role/default \
    user_claim="email" \
    allowed_redirect_uris="https://${VAULT_DOMAIN}/ui/vault/auth/oidc/oidc/callback" \
    allowed_redirect_uris="http://localhost:8250/oidc/callback" \
    policies="default,${_VAULT_ADMIN_POLICY}" \
    oidc_scopes="openid,email,profile" \
    bound_claims="{\"email\":\"${ADMIN_EMAIL}\"}" \
    ttl=12h >/dev/null
  log_info "OIDC configured — login at https://${VAULT_DOMAIN}"
}

# vault_configure — the idempotent setup of engines, auth methods, policies and
# roles. Needs an unsealed Vault and VAULT_TOKEN (vault_use_root_token).
vault_configure() {
  local oidc_mode
  oidc_mode="$(vault_oidc_mode)"
  _vault_check_inputs "$oidc_mode" || return 1

  log_step "Enabling KV v2 secrets engine at 'secret/'..."
  if _vault_mount_enabled secrets secret/; then
    log_info "KV v2 already enabled — skipping"
  else
    vault_exec secrets enable -path=secret kv-v2
  fi

  log_step "Configuring Kubernetes auth method..."
  if _vault_mount_enabled auth kubernetes/; then
    log_info "Kubernetes auth already enabled — updating config"
  else
    vault_exec auth enable kubernetes
  fi
  vault_exec write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local:443" >/dev/null

  log_step "Writing policies from ${VAULT_POLICY_DIR}..."
  _vault_apply_policies

  log_step "Creating the External Secrets role..."
  vault_exec write auth/kubernetes/role/eso \
    bound_service_account_names="${ESO_SA}" \
    bound_service_account_namespaces="${ESO_NAMESPACE}" \
    policies="${_VAULT_ESO_POLICY}" \
    ttl=1h >/dev/null

  if [[ "$oidc_mode" == "all" ]]; then
    _vault_configure_oidc
  else
    log_info "Skipping OIDC auth (none of ${_VAULT_OIDC_VARS[*]} is set)"
  fi

  log_ok "Vault configured"
}
