#!/bin/bash
################################################################################
# Étape 4.5: vault-seeder End-to-End (E2E) Testing Script
# Purpose: Deploy vault-seeder to real cluster and verify all components work
# Prerequisites:
#   - k3s cluster running with Vault initialized
#   - kubectl configured with admin access
#   - ArgoCD deployed (or deployment will be manual)
#   - vault-seeder chart available
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Config
NAMESPACE_SEEDER="vault-seeder"
NAMESPACE_VAULT="vault"
VAULT_POD="vault-0"
SECRET_NAME="vault-seeder-secrets"
JOB_CORE_NAME="vault-seeder-core"
JOB_APPS_NAME="vault-seeder-apps"
TIMEOUT_CORE_JOB=300  # 5 minutes
TIMEOUT_APPS_JOB=300  # 5 minutes

# Results tracking
STEP=0
PASSED=0
FAILED=0

# Helper functions
log_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BLUE}$1${RESET}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

log_step() {
  STEP=$((STEP + 1))
  echo ""
  echo -e "${CYAN}→ Step $STEP: $1${RESET}"
}

log_ok() {
  echo -e "${GREEN}✓${RESET} $1"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo -e "${RED}✗${RESET} $1"
  FAILED=$((FAILED + 1))
}

log_info() {
  echo "  ℹ️  $1"
}

log_warn() {
  echo -e "${YELLOW}⚠️ $1${RESET}"
}

# vault_exec <vault-args...> — run vault CLI in the Vault pod.
# The token travels on stdin (first line), never as a process argument.
vault_exec() {
  printf '%s\n' "${VAULT_TOKEN}" | kubectl exec -i -n "$NAMESPACE_VAULT" "$VAULT_POD" -- \
    sh -c 'IFS= read -r VAULT_TOKEN; export VAULT_TOKEN VAULT_SKIP_VERIFY=true; exec vault "$@"' vault-cli "$@"
}

wait_for_condition() {
  local description="$1"
  local condition_cmd="$2"
  local timeout="${3:-300}"
  local interval="${4:-5}"

  echo -n "  Waiting for $description... "
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if eval "$condition_cmd" > /dev/null 2>&1; then
      echo -e "${GREEN}Done${RESET} (${elapsed}s)"
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
    echo -n "."
  done

  echo -e "${RED}TIMEOUT${RESET}"
  return 1
}

# =============================================================================
# Main E2E Test Flow
# =============================================================================

log_header "Étape 4.5: vault-seeder E2E Testing"

# =============================================================================
# Phase 1: Pre-flight Checks
# =============================================================================

log_header "Phase 1: Pre-flight Checks"

log_step "Check kubectl access"
# NOTE: no --short — the flag was removed in kubectl 1.28
if kubectl version > /dev/null 2>&1; then
  log_ok "kubectl is accessible"
else
  log_fail "kubectl is not accessible"
  exit 1
fi

log_step "Check Vault pod is running"
if kubectl get pod -n "$NAMESPACE_VAULT" "$VAULT_POD" > /dev/null 2>&1; then
  log_ok "Vault pod found"
else
  log_fail "Vault pod not found in $NAMESPACE_VAULT namespace"
  exit 1
fi

log_step "Check Vault is unsealed"
VAULT_STATUS=$(kubectl exec -n "$NAMESPACE_VAULT" "$VAULT_POD" -- vault status -format=json 2>/dev/null | jq -r '.sealed' 2>/dev/null || echo "unknown")
if [[ "$VAULT_STATUS" == "false" ]]; then
  log_ok "Vault is unsealed"
else
  log_fail "Vault is not unsealed (status: $VAULT_STATUS)"
  exit 1
fi

log_step "Check Vault is initialized"
VAULT_INITIALIZED=$(kubectl exec -n "$NAMESPACE_VAULT" "$VAULT_POD" -- vault status -format=json 2>/dev/null | jq -r '.initialized' 2>/dev/null || echo "unknown")
if [[ "$VAULT_INITIALIZED" == "true" ]]; then
  log_ok "Vault is initialized"
else
  log_fail "Vault is not initialized"
  exit 1
fi

log_step "Check cluster version"
CLUSTER_VERSION=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' || echo "unknown")
log_ok "Cluster version: $CLUSTER_VERSION"

# =============================================================================
# Phase 2: Create/Verify Secret
# =============================================================================

log_header "Phase 2: Create/Verify Secret"

log_step "Check if vault-seeder-secrets exists"
if kubectl get secret -n argocd "$SECRET_NAME" > /dev/null 2>&1; then
  log_ok "Secret $SECRET_NAME already exists in argocd namespace"
  log_info "Using existing secret. If you want to update it, delete and recreate."
else
  log_warn "Secret $SECRET_NAME not found in argocd namespace"
  log_info "Create it with:"
  echo "    kubectl apply -f secrets/vault-seeder-secrets.yaml"
  echo ""
  read -r -p "Press Enter to continue (assuming secret will be created)..."
fi

log_step "Verify secret has required keys"
REQUIRED_KEYS=("vault-root-token")
for key in "${REQUIRED_KEYS[@]}"; do
  if kubectl get secret -n argocd "$SECRET_NAME" -o jsonpath="{.data.$key}" > /dev/null 2>&1; then
    log_ok "Secret has key: $key"
  else
    log_fail "Secret missing required key: $key"
    exit 1
  fi
done

# =============================================================================
# Phase 3: Create Namespace
# =============================================================================

log_header "Phase 3: Create Namespace"

log_step "Create $NAMESPACE_SEEDER namespace"
if kubectl get ns "$NAMESPACE_SEEDER" > /dev/null 2>&1; then
  log_ok "Namespace $NAMESPACE_SEEDER already exists"
else
  kubectl create ns "$NAMESPACE_SEEDER"
  log_ok "Namespace $NAMESPACE_SEEDER created"
fi

# =============================================================================
# Phase 4: Deploy Chart
# =============================================================================

log_header "Phase 4: Deploy vault-seeder Chart"

log_step "Deploy chart via Helm"
if helm install vault-seeder ./charts/platform-vault-seeder \
  --namespace "$NAMESPACE_SEEDER" \
  --set secrets.vaultRootToken="$(kubectl get secret -n argocd $SECRET_NAME -o jsonpath='{.data.vault-root-token}' | base64 -d)" \
  --set secrets.oidcClientId="$(kubectl get secret -n argocd $SECRET_NAME -o jsonpath='{.data.oidc-client-id}' 2>/dev/null | base64 -d || echo '')" \
  --set secrets.oidcClientSecret="$(kubectl get secret -n argocd $SECRET_NAME -o jsonpath='{.data.oidc-client-secret}' 2>/dev/null | base64 -d || echo '')" \
  --set secrets.grafanaPassword="$(kubectl get secret -n argocd $SECRET_NAME -o jsonpath='{.data.grafana-password}' 2>/dev/null | base64 -d || echo '')" \
  --set secrets.ghcrPat="$(kubectl get secret -n argocd $SECRET_NAME -o jsonpath='{.data.ghcr-pat}' 2>/dev/null | base64 -d || echo '')" \
  --set secrets.rrAuthSecret="$(kubectl get secret -n argocd $SECRET_NAME -o jsonpath='{.data.rr-auth-secret}' 2>/dev/null | base64 -d || echo '')" \
  2>/dev/null; then
  log_ok "Chart deployed successfully"
else
  log_warn "Helm install may have warnings (check above), but proceeding..."
fi

log_step "Verify resources were created"
RESOURCE_COUNT=$(kubectl get all -n "$NAMESPACE_SEEDER" --no-headers 2>/dev/null | wc -l)
if [ "$RESOURCE_COUNT" -gt 0 ]; then
  log_ok "Resources created: $RESOURCE_COUNT"
else
  log_fail "No resources found in $NAMESPACE_SEEDER namespace"
  exit 1
fi

# =============================================================================
# Phase 5: Monitor Job 1 (vault-configure)
# =============================================================================

log_header "Phase 5: Monitor Job 1 ($JOB_CORE_NAME)"

log_step "Wait for Job 1 to start"
# NOTE: under `set -e` a bare wait_for_condition failure would abort the
# script, so each call must be part of an if — `$?` checks were dead code.
if ! wait_for_condition "Job $JOB_CORE_NAME exists" \
  "kubectl get job -n $NAMESPACE_SEEDER $JOB_CORE_NAME" \
  30 \
  2; then
  log_fail "Job 1 did not start within 30 seconds"
  kubectl get pods -n "$NAMESPACE_SEEDER"
  exit 1
fi

log_step "Monitor Job 1 pod"
POD_NAME=$(kubectl get pod -n "$NAMESPACE_SEEDER" -l app="$JOB_CORE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "unknown")
log_info "Pod: $POD_NAME"

log_step "Wait for Job 1 pod to start"
if wait_for_condition "Job 1 pod is running" \
  "kubectl get pod -n $NAMESPACE_SEEDER $POD_NAME -o jsonpath='{.status.phase}' | grep -q Running" \
  60 \
  3; then
  log_ok "Job 1 pod is running"
else
  log_warn "Job 1 pod not in Running state yet. Checking logs..."
fi

log_step "Stream Job 1 logs"
log_info "Streaming logs from $POD_NAME (press Ctrl+C to continue)..."
timeout 120 kubectl logs -n "$NAMESPACE_SEEDER" -f "$POD_NAME" 2>/dev/null || true
echo ""

log_step "Wait for Job 1 to complete"
if wait_for_condition "Job $JOB_CORE_NAME completes" \
  "kubectl get job -n $NAMESPACE_SEEDER $JOB_CORE_NAME -o jsonpath='{.status.succeeded}' | grep -q 1" \
  "$TIMEOUT_CORE_JOB" \
  5; then
  log_ok "Job 1 completed successfully"
  JOB1_STATUS="SUCCESS"
else
  log_warn "Job 1 did not complete within $TIMEOUT_CORE_JOB seconds"
  JOB1_STATUS="TIMEOUT"

  # Check if it failed
  JOB1_FAILED=$(kubectl get job -n "$NAMESPACE_SEEDER" "$JOB_CORE_NAME" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
  if [ "$JOB1_FAILED" != "0" ] && [ "$JOB1_FAILED" != "" ]; then
    log_fail "Job 1 failed"
    JOB1_STATUS="FAILED"
  fi
fi

log_step "Display Job 1 final status"
kubectl describe job -n "$NAMESPACE_SEEDER" "$JOB_CORE_NAME" | grep -E "^Status:|Pods Status:|Succeeded|Failed"

# =============================================================================
# Phase 6: Monitor Job 2 (vault-seed-apps)
# =============================================================================

log_header "Phase 6: Monitor Job 2 ($JOB_APPS_NAME)"

log_step "Wait for Job 2 to exist"
if ! wait_for_condition "Job $JOB_APPS_NAME exists" \
  "kubectl get job -n $NAMESPACE_SEEDER $JOB_APPS_NAME" \
  60 \
  3; then
  log_fail "Job 2 did not appear within 60 seconds"
  log_info "Job 1 may have failed or timed out"
  exit 1
fi

log_ok "Job 2 exists"

log_step "Monitor Job 2 pod"
POD_NAME_2=$(kubectl get pod -n "$NAMESPACE_SEEDER" -l app="$JOB_APPS_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "unknown")
log_info "Pod: $POD_NAME_2"

log_step "Check Job 2 initContainer (waiting for Job 1)"
if kubectl get pod -n "$NAMESPACE_SEEDER" "$POD_NAME_2" -o jsonpath='{.spec.initContainers[0].name}' 2>/dev/null | grep -q "wait-for-core-job"; then
  log_ok "initContainer found: wait-for-core-job"
  log_info "Pod is likely waiting for Job 1 to complete..."
else
  log_warn "initContainer not found or unexpected"
fi

log_step "Wait for Job 2 main container to start"
if wait_for_condition "Job 2 pod is running" \
  "kubectl get pod -n $NAMESPACE_SEEDER $POD_NAME_2 -o jsonpath='{.status.phase}' | grep -q Running" \
  120 \
  5; then
  log_ok "Job 2 main container is running"
else
  log_warn "Job 2 main container not running yet"
fi

log_step "Stream Job 2 logs"
log_info "Streaming logs from $POD_NAME_2 (press Ctrl+C to continue)..."
timeout 240 kubectl logs -n "$NAMESPACE_SEEDER" -f "$POD_NAME_2" -c seeder 2>/dev/null || true
echo ""

log_step "Wait for Job 2 to complete"
if wait_for_condition "Job $JOB_APPS_NAME completes" \
  "kubectl get job -n $NAMESPACE_SEEDER $JOB_APPS_NAME -o jsonpath='{.status.succeeded}' | grep -q 1" \
  "$TIMEOUT_APPS_JOB" \
  5; then
  log_ok "Job 2 completed successfully"
  JOB2_STATUS="SUCCESS"
else
  log_warn "Job 2 did not complete within $TIMEOUT_APPS_JOB seconds"
  JOB2_STATUS="TIMEOUT"

  # Check if it failed
  JOB2_FAILED=$(kubectl get job -n "$NAMESPACE_SEEDER" "$JOB_APPS_NAME" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
  if [ "$JOB2_FAILED" != "0" ] && [ "$JOB2_FAILED" != "" ]; then
    log_fail "Job 2 failed"
    JOB2_STATUS="FAILED"
  fi
fi

log_step "Display Job 2 final status"
kubectl describe job -n "$NAMESPACE_SEEDER" "$JOB_APPS_NAME" | grep -E "^Status:|Pods Status:|Succeeded|Failed"

# =============================================================================
# Phase 7: Verify Secrets in Vault
# =============================================================================

log_header "Phase 7: Verify Secrets in Vault"

log_step "Get Vault root token"
VAULT_TOKEN=$(kubectl get secret -n argocd "$SECRET_NAME" -o jsonpath='{.data.vault-root-token}' 2>/dev/null | base64 -d)
if [ -z "$VAULT_TOKEN" ]; then
  log_fail "Could not retrieve Vault root token from secret"
  exit 1
fi
log_ok "Vault root token retrieved"

log_step "List all seeded secrets in Vault"
SECRETS_LIST=$(vault_exec kv list secret/ 2>/dev/null || echo "ERROR")

if [[ "$SECRETS_LIST" == "ERROR" ]]; then
  log_fail "Could not list secrets from Vault"
else
  log_ok "Secrets found in Vault:"
  echo "$SECRETS_LIST" | sed 's/^/    /'
fi

# Verify each secret path
SECRETS_TO_CHECK=(
  "secret/argocd/oidc"
  "secret/grafana/admin"
  "secret/grafana/oauth"
  "secret/ghcr/pull"
  "secret/reactive-resume/prod"
)

for secret_path in "${SECRETS_TO_CHECK[@]}"; do
  log_step "Check $secret_path exists in Vault"
  if vault_exec kv get "$secret_path" > /dev/null 2>&1; then
    log_ok "$secret_path exists"
  else
    log_warn "$secret_path does not exist (may not have been seeded if optional)"
  fi
done

# =============================================================================
# Phase 8: Verify Vault Configuration (ESO role, OIDC)
# =============================================================================

log_header "Phase 8: Verify Vault Configuration"

log_step "Check ESO Kubernetes auth role exists"
if vault_exec read auth/kubernetes/role/eso > /dev/null 2>&1; then
  log_ok "ESO Kubernetes auth role found"
else
  log_fail "ESO Kubernetes auth role not found"
fi

log_step "Check eso-read policy exists"
if vault_exec policy read eso-read > /dev/null 2>&1; then
  log_ok "eso-read policy found"
else
  log_fail "eso-read policy not found"
fi

log_step "Check OIDC auth method (if configured)"
OIDC_ENABLED=$(vault_exec auth list -format=json 2>/dev/null | jq 'has("oidc/")' || echo "false")

if [[ "$OIDC_ENABLED" == "true" ]]; then
  log_ok "OIDC auth method is enabled"
else
  log_info "OIDC auth method not enabled (optional, may not have been configured)"
fi

# =============================================================================
# Phase 9: Verify K8s Secrets (via ExternalSecret)
# =============================================================================

log_header "Phase 9: Verify K8s Secrets (via ExternalSecret)"

log_step "Wait for ExternalSecrets to sync"
log_info "Waiting up to 2 minutes for ESO to pull secrets from Vault..."
if wait_for_condition "K8s secrets are synced" \
  "kubectl get secret -n argocd argocd-secret > /dev/null 2>&1 || kubectl get secret -n monitoring grafana-oauth-secret > /dev/null 2>&1" \
  120 \
  10; then
  log_ok "K8s secrets found (ESO sync completed)"
else
  log_warn "Expected K8s secrets not found yet"
  log_info "ExternalSecrets may be still syncing or not configured"
fi

log_step "List secrets in app namespaces"
for ns in argocd monitoring vault-seeder; do
  if kubectl get ns "$ns" > /dev/null 2>&1; then
    SECRET_COUNT=$(kubectl get secret -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [ "$SECRET_COUNT" -gt 0 ]; then
      log_ok "Namespace $ns has $SECRET_COUNT secrets"
    else
      log_info "Namespace $ns has no secrets"
    fi
  fi
done

# =============================================================================
# Phase 10: Summary
# =============================================================================

log_header "Phase 10: Test Summary"

echo ""
echo -e "${CYAN}Execution Summary:${RESET}"
echo "  Job 1 ($JOB_CORE_NAME): $JOB1_STATUS"
echo "  Job 2 ($JOB_APPS_NAME): $JOB2_STATUS"
echo ""
echo -e "${CYAN}Results:${RESET}"
echo "  Total Checks: $((PASSED + FAILED))"
echo -e "  ${GREEN}Passed: $PASSED${RESET}"
if [ "$FAILED" -gt 0 ]; then
  echo -e "  ${RED}Failed: $FAILED${RESET}"
else
  echo -e "  ${GREEN}Failed: $FAILED${RESET}"
fi

echo ""
echo -e "${CYAN}Next Steps:${RESET}"

if [ "$JOB1_STATUS" = "SUCCESS" ] && [ "$JOB2_STATUS" = "SUCCESS" ]; then
  echo "  1. ✅ Verify all secrets in Vault (run: vault kv list secret/)"
  echo "  2. ✅ Force ExternalSecret syncs: kubectl annotate externalsecret --all -A force-sync=\$(date +%s) --overwrite"
  echo "  3. ✅ Verify K8s Secrets were created: kubectl get secret -n argocd argocd-secret"
  echo "  4. ✅ Monitor upcoming app deployments (they will pull secrets from Vault)"
  echo ""
  echo -e "${GREEN}🎉 E2E Test PASSED - vault-seeder is working!${RESET}"
  exit 0
else
  echo "  1. ⚠️  Check Job logs for errors"
  echo "  2. ⚠️  Verify Vault is unsealed and accessible"
  echo "  3. ⚠️  Check secret $SECRET_NAME exists in argocd namespace"
  echo "  4. ⚠️  Review Étape 4 documentation for troubleshooting"
  echo ""
  echo -e "${RED}⚠️  E2E Test encountered issues - see above for details${RESET}"
  exit 1
fi
