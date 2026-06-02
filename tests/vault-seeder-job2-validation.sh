#!/bin/bash
################################################################################
# Étape 4.3: vault-seeder-apps (Job 2) Validation Tests
# Purpose: Comprehensive validation of Job 2 configuration and script logic
# Tests: 35 assertions across structure, environment, secrets, and seeding logic
################################################################################

set -euo pipefail

CHART_DIR="./charts/platform-vault-seeder"
JOB2_TEMPLATE="$CHART_DIR/templates/job-apps.yaml"
CONFIGMAP2_TEMPLATE="$CHART_DIR/templates/configmap-apps.yaml"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

passed=0
failed=0
total=0

# Test helper
test_assert() {
  local description="$1"
  local assertion="$2"

  total=$((total + 1))
  if eval "$assertion" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${RESET} $description"
    passed=$((passed + 1))
  else
    echo -e "${RED}✗${RESET} $description"
    failed=$((failed + 1))
  fi
}

# Header
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BLUE}Étape 4.3: vault-seeder-apps (Job 2) Validation${RESET}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# =============================================================================
# Section 1: Job 2 Structure
# =============================================================================
echo -e "${YELLOW}⚙️  Job 2: Structure${RESET}"

test_assert "job-apps.yaml file exists" "[[ -f '$JOB2_TEMPLATE' ]]"

test_assert "Job 2 is Kind: Job" "grep -q '^kind: Job' '$JOB2_TEMPLATE'"

test_assert "Job 2 uses jobApps.name from values" \
  "grep -q 'name: {{ .Values.jobApps.name }}' '$JOB2_TEMPLATE'"

test_assert "Job 2 namespace is jobApps.namespace from values" \
  "grep -q 'namespace: {{ .Values.namespace.name }}' '$JOB2_TEMPLATE'"

test_assert "Job 2 uses vault-seeder ServiceAccount" \
  "grep -q 'serviceAccountName: vault-seeder' '$JOB2_TEMPLATE'"

test_assert "Job 2 has labels from template helpers" \
  "grep -q 'include \"platform-vault-seeder.labels\"' '$JOB2_TEMPLATE'"

test_assert "Job 2 has TTL set for cleanup" \
  "grep -q 'ttlSecondsAfterFinished: {{ .Values.jobApps.ttlSecondsAfterFinished }}' '$JOB2_TEMPLATE'"

echo ""

# =============================================================================
# Section 2: initContainer (Wait for Job 1)
# =============================================================================
echo -e "${YELLOW}⚙️  Job 2: initContainer (Dependency on Job 1)${RESET}"

test_assert "initContainers section exists (conditional on jobCore.enabled)" \
  "grep -q 'initContainers:' '$JOB2_TEMPLATE'"

test_assert "Wait container name is wait-for-core-job" \
  "grep -q 'name: wait-for-core-job' '$JOB2_TEMPLATE'"

test_assert "Wait container uses kubectl image" \
  "grep -q 'image: \"{{ .Values.jobApps.image.repository' '$JOB2_TEMPLATE'"

test_assert "Wait logic loops 300 times (5 min timeout)" \
  "grep -q 'for i in {1..300}' '$JOB2_TEMPLATE'"

test_assert "Wait checks Job succeeded status (.status.succeeded)" \
  "grep -q '.status.succeeded' '$JOB2_TEMPLATE' | head -1 && grep -q \"grep -q \\\"1\\\"\" '$JOB2_TEMPLATE'"

test_assert "Wait checks Job failed status (.status.failed)" \
  "grep -q '.status.failed' '$JOB2_TEMPLATE'"

test_assert "Wait sleeps 2 seconds between checks" \
  "grep -q 'sleep 2' '$JOB2_TEMPLATE'"

test_assert "Wait container has readOnlyRootFilesystem" \
  "awk '/wait-for-core-job/,/{{- end }}/' '$JOB2_TEMPLATE' | grep -q 'readOnlyRootFilesystem: true'"

test_assert "Wait container has non-root user (65534)" \
  "awk '/wait-for-core-job/,/{{- end }}/' '$JOB2_TEMPLATE' | grep -q 'runAsUser: 65534'"

test_assert "Wait container drops ALL capabilities" \
  "awk '/wait-for-core-job/,/{{- end }}/' '$JOB2_TEMPLATE' | grep 'drop:' && awk '/wait-for-core-job/,/{{- end }}/' '$JOB2_TEMPLATE' | grep 'ALL'"

echo ""

# =============================================================================
# Section 3: Main Container Environment Variables
# =============================================================================
echo -e "${YELLOW}⚙️  Job 2: Main Container - Environment Variables${RESET}"

test_assert "VAULT_ROOT_TOKEN from secret" \
  "grep -q 'name: VAULT_ROOT_TOKEN' '$JOB2_TEMPLATE' && grep -q 'vault-root-token' '$JOB2_TEMPLATE'"

test_assert "OIDC_CLIENT_ID from secret (optional)" \
  "grep -q 'name: OIDC_CLIENT_ID' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "OIDC_CLIENT_SECRET from secret (optional)" \
  "grep -q 'name: OIDC_CLIENT_SECRET' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "OIDC_PROVIDER_NAME from values" \
  "grep -q 'OIDC_PROVIDER_NAME' '$JOB2_TEMPLATE' && grep -q '.Values.secrets.oidcProviderName' '$JOB2_TEMPLATE'"

test_assert "OIDC_AUTH_URL from values" \
  "grep -q 'OIDC_AUTH_URL' '$JOB2_TEMPLATE'"

test_assert "OIDC_TOKEN_URL from values" \
  "grep -q 'OIDC_TOKEN_URL' '$JOB2_TEMPLATE'"

test_assert "OIDC_API_URL from values" \
  "grep -q 'OIDC_API_URL' '$JOB2_TEMPLATE'"

test_assert "ARGOCD_SERVER_SECRET_KEY from secret (optional)" \
  "grep -q 'ARGOCD_SERVER_SECRET_KEY' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "HOMEPAGE_ARGOCD_TOKEN from secret (optional)" \
  "grep -q 'HOMEPAGE_ARGOCD_TOKEN' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "GRAFANA_PASSWORD from secret (optional)" \
  "grep -q 'GRAFANA_PASSWORD' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "GHCR_PAT from secret (optional)" \
  "grep -q 'GHCR_PAT' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "GITHUB_USER from values" \
  "grep -q 'GITHUB_USER' '$JOB2_TEMPLATE' && grep -q '.Values.secrets.githubUser' '$JOB2_TEMPLATE'"

test_assert "RR_AUTH_SECRET from secret (optional)" \
  "grep -q 'RR_AUTH_SECRET' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "RR_DB_PASSWORD from secret (optional)" \
  "grep -q 'RR_DB_PASSWORD' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "RR_BROWSERLESS_TOKEN from secret (optional)" \
  "grep -q 'RR_BROWSERLESS_TOKEN' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "RR_DATABASE_URL from secret (optional)" \
  "grep -q 'RR_DATABASE_URL' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "RR_PRINTER_ENDPOINT from secret (optional)" \
  "grep -q 'RR_PRINTER_ENDPOINT' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "RR_S3_ACCESS_KEY_ID from secret (optional)" \
  "grep -q 'RR_S3_ACCESS_KEY_ID' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

test_assert "RR_S3_SECRET_ACCESS_KEY from secret (optional)" \
  "grep -q 'RR_S3_SECRET_ACCESS_KEY' '$JOB2_TEMPLATE' && grep -q 'optional: true' '$JOB2_TEMPLATE'"

echo ""

# =============================================================================
# Section 4: Main Container Security
# =============================================================================
echo -e "${YELLOW}🔒 Job 2: Main Container - Security${RESET}"

test_assert "Main container readOnlyRootFilesystem: true" \
  "grep -q 'readOnlyRootFilesystem: true' '$JOB2_TEMPLATE' && tail -30 '$JOB2_TEMPLATE' | grep -q 'readOnlyRootFilesystem: true'"

test_assert "Main container runAsNonRoot: true" \
  "grep -c 'runAsNonRoot: true' '$JOB2_TEMPLATE' | grep -q '[2-9]'"

test_assert "Main container allowPrivilegeEscalation: false" \
  "grep -c 'allowPrivilegeEscalation: false' '$JOB2_TEMPLATE' | grep -q '[2-9]'"

test_assert "Main container drops ALL capabilities" \
  "tail -30 '$JOB2_TEMPLATE' | grep 'drop:' && tail -30 '$JOB2_TEMPLATE' | grep 'ALL'"

test_assert "Main container has resource limits" \
  "grep 'resources:' '$JOB2_TEMPLATE' && grep '{{- with .Values.jobApps.resources }}' '$JOB2_TEMPLATE'"

echo ""

# =============================================================================
# Section 5: Vault Seed Script - ConfigMap Structure
# =============================================================================
echo -e "${YELLOW}📜 Job 2: ConfigMap Script - Structure${RESET}"

test_assert "configmap-apps.yaml file exists" "[[ -f '$CONFIGMAP2_TEMPLATE' ]]"

test_assert "ConfigMap name references jobApps.name" \
  "grep -q 'name: {{ .Values.jobApps.name }}-script' '$CONFIGMAP2_TEMPLATE'"

test_assert "Script key is vault-seed-apps.sh" \
  "grep -q 'vault-seed-apps.sh:' '$CONFIGMAP2_TEMPLATE'"

test_assert "Script starts with bash shebang" \
  "grep -q '#!/bin/bash' '$CONFIGMAP2_TEMPLATE'"

test_assert "Script uses set -euo pipefail" \
  "grep -q 'set -euo pipefail' '$CONFIGMAP2_TEMPLATE'"

test_assert "Script defines vault_exec function" \
  "grep -q 'vault_exec()' '$CONFIGMAP2_TEMPLATE'"

test_assert "vault_exec uses kubectl exec into vault pod" \
  "grep -q 'kubectl.*exec' '$CONFIGMAP2_TEMPLATE' | head -1"

echo ""

# =============================================================================
# Section 6: Vault Seed Script - Application Secrets
# =============================================================================
echo -e "${YELLOW}📝 Job 2: ConfigMap Script - 5 Application Secret Paths${RESET}"

test_assert "Seeds secret/argocd/oidc" \
  "grep -q 'secret/argocd/oidc' '$CONFIGMAP2_TEMPLATE'"

test_assert "secret/argocd/oidc includes clientID" \
  "grep -A 5 'secret/argocd/oidc' '$CONFIGMAP2_TEMPLATE' | grep -q 'clientID'"

test_assert "secret/argocd/oidc includes clientSecret" \
  "grep -A 5 'secret/argocd/oidc' '$CONFIGMAP2_TEMPLATE' | grep -q 'clientSecret'"

test_assert "secret/argocd/oidc includes server.secretkey" \
  "grep -A 5 'secret/argocd/oidc' '$CONFIGMAP2_TEMPLATE' | grep -q 'server.secretkey'"

test_assert "secret/argocd/oidc includes accounts.homepage.tokens" \
  "grep -A 5 'secret/argocd/oidc' '$CONFIGMAP2_TEMPLATE' | grep -q 'accounts.homepage.tokens'"

test_assert "Seeds secret/grafana/admin" \
  "grep -q 'secret/grafana/admin' '$CONFIGMAP2_TEMPLATE'"

test_assert "secret/grafana/admin includes username" \
  "grep -A 3 'secret/grafana/admin' '$CONFIGMAP2_TEMPLATE' | grep -q 'username.*admin'"

test_assert "secret/grafana/admin includes password" \
  "grep -A 3 'secret/grafana/admin' '$CONFIGMAP2_TEMPLATE' | grep -q 'password'"

test_assert "Seeds secret/grafana/oauth" \
  "grep -q 'secret/grafana/oauth' '$CONFIGMAP2_TEMPLATE'"

test_assert "secret/grafana/oauth includes GF_AUTH_GENERIC_OAUTH_ENABLED" \
  "grep -q 'GF_AUTH_GENERIC_OAUTH_ENABLED' '$CONFIGMAP2_TEMPLATE'"

test_assert "secret/grafana/oauth includes GF_AUTH_GENERIC_OAUTH_CLIENT_ID" \
  "grep -q 'GF_AUTH_GENERIC_OAUTH_CLIENT_ID' '$CONFIGMAP2_TEMPLATE'"

test_assert "secret/grafana/oauth includes GF_AUTH_GENERIC_OAUTH_AUTH_URL" \
  "grep -q 'GF_AUTH_GENERIC_OAUTH_AUTH_URL' '$CONFIGMAP2_TEMPLATE'"

test_assert "Seeds secret/ghcr/pull" \
  "grep -q 'secret/ghcr/pull' '$CONFIGMAP2_TEMPLATE'"

test_assert "secret/ghcr/pull includes username (GITHUB_USER)" \
  "grep -A 3 'secret/ghcr/pull' '$CONFIGMAP2_TEMPLATE' | grep -q 'username'"

test_assert "secret/ghcr/pull includes password (GHCR_PAT)" \
  "grep -A 3 'secret/ghcr/pull' '$CONFIGMAP2_TEMPLATE' | grep -q 'password'"

test_assert "Seeds secret/reactive-resume/prod" \
  "grep -q 'secret/reactive-resume/prod' '$CONFIGMAP2_TEMPLATE'"

test_assert "secret/reactive-resume/prod includes AUTH_SECRET" \
  "grep -A 8 'secret/reactive-resume/prod' '$CONFIGMAP2_TEMPLATE' | grep -q 'AUTH_SECRET'"

test_assert "secret/reactive-resume/prod includes DB_PASSWORD" \
  "grep -A 8 'secret/reactive-resume/prod' '$CONFIGMAP2_TEMPLATE' | grep -q 'DB_PASSWORD'"

test_assert "secret/reactive-resume/prod includes DATABASE_URL" \
  "grep -A 8 'secret/reactive-resume/prod' '$CONFIGMAP2_TEMPLATE' | grep -q 'DATABASE_URL'"

test_assert "secret/reactive-resume/prod includes S3_ACCESS_KEY_ID" \
  "grep -A 8 'secret/reactive-resume/prod' '$CONFIGMAP2_TEMPLATE' | grep -q 'S3_ACCESS_KEY_ID'"

echo ""

# =============================================================================
# Section 7: Conditional Logic
# =============================================================================
echo -e "${YELLOW}⚡ Job 2: Conditional Secret Seeding${RESET}"

test_assert "secret/argocd/oidc conditional on oidcClientId" \
  "grep -B 2 'secret/argocd/oidc' '$CONFIGMAP2_TEMPLATE' | grep -q '{{- if'"

test_assert "secret/grafana/admin conditional on grafanaPassword" \
  "grep -B 2 'secret/grafana/admin' '$CONFIGMAP2_TEMPLATE' | grep -q '{{- if'"

test_assert "secret/grafana/oauth conditional on oidcClientId" \
  "grep -B 2 'secret/grafana/oauth' '$CONFIGMAP2_TEMPLATE' | grep -q '{{- if'"

test_assert "secret/ghcr/pull conditional on ghcrPat" \
  "grep -B 2 'secret/ghcr/pull' '$CONFIGMAP2_TEMPLATE' | grep -q '{{- if'"

test_assert "secret/reactive-resume/prod conditional on rrAuthSecret" \
  "grep '.Values.secrets.rrAuthSecret' '$CONFIGMAP2_TEMPLATE'"

echo ""

# =============================================================================
# Summary
# =============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [[ $failed -eq 0 ]]; then
  echo -e "${GREEN}✅ Results: $passed/$total passed${RESET}"
  echo ""
  exit 0
else
  echo -e "${RED}❌ Results: $failed failed, $passed/$total passed${RESET}"
  echo ""
  exit 1
fi
