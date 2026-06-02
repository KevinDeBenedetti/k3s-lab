#!/bin/bash
# =============================================================================
# tests/vault-seeder-validation.sh — Quick validation for Étape 4.2
#
# Validates:
#   - Helm chart structure
#   - Configmap scripts
#   - Job specifications
#
# Usage:
#   bash tests/vault-seeder-validation.sh
# =============================================================================

TESTS_RUN=0
TESTS_PASSED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

test_pass() {
  ((TESTS_PASSED++))
  echo -e "${GREEN}✓${NC} $1"
}

test_fail() {
  echo -e "${RED}✗${NC} $1"
}

check_file() {
  local file="$1" name="$2"
  ((TESTS_RUN++))
  if [ -f "$file" ]; then
    test_pass "$name exists"
    return 0
  else
    test_fail "$name missing: $file"
    return 1
  fi
}

check_grep() {
  local file="$1" pattern="$2" name="$3"
  ((TESTS_RUN++))
  if grep -q "$pattern" "$file" 2>/dev/null; then
    test_pass "$name"
    return 0
  else
    test_fail "$name not found in $file"
    return 1
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Étape 4.2: vault-seeder Chart Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📋 Chart Files"
check_file "charts/platform-vault-seeder/Chart.yaml" "Chart.yaml"
check_file "charts/platform-vault-seeder/values.yaml" "values.yaml"
check_file "charts/platform-vault-seeder/README.md" "README.md"

echo ""
echo "📋 Template Files"
check_file "charts/platform-vault-seeder/templates/job-core.yaml" "job-core.yaml"
check_file "charts/platform-vault-seeder/templates/configmap-core.yaml" "configmap-core.yaml"
check_file "charts/platform-vault-seeder/templates/job-apps.yaml" "job-apps.yaml"
check_file "charts/platform-vault-seeder/templates/configmap-apps.yaml" "configmap-apps.yaml"
check_file "charts/platform-vault-seeder/templates/serviceaccount.yaml" "serviceaccount.yaml"

echo ""
echo "🏗️  Chart Metadata"
check_grep "charts/platform-vault-seeder/Chart.yaml" "name: platform-vault-seeder" "Chart name"
check_grep "charts/platform-vault-seeder/Chart.yaml" "version: 0.1.0" "Chart version"

echo ""
echo "⚙️  Job 1: vault-seeder-core"
check_grep "charts/platform-vault-seeder/templates/job-core.yaml" "kind: Job" "Job 1 is Job kind"
check_grep "charts/platform-vault-seeder/templates/configmap-core.yaml" "vault_exec()" "Job 1 has vault_exec"
check_grep "charts/platform-vault-seeder/templates/configmap-core.yaml" "policy write eso-read" "Job 1 creates ESO policy"
check_grep "charts/platform-vault-seeder/templates/configmap-core.yaml" "auth/kubernetes/role/eso" "Job 1 creates ESO role"

echo ""
echo "⚙️  Job 2: vault-seeder-apps"
check_grep "charts/platform-vault-seeder/templates/job-apps.yaml" "kind: Job" "Job 2 is Job kind"
check_grep "charts/platform-vault-seeder/templates/job-apps.yaml" "wait-for-core-job" "Job 2 waits for Job 1"
check_grep "charts/platform-vault-seeder/templates/configmap-apps.yaml" "secret/argocd/oidc" "Job 2 seeds argocd"
check_grep "charts/platform-vault-seeder/templates/configmap-apps.yaml" "secret/grafana/admin" "Job 2 seeds grafana"

echo ""
echo "🔒 Security"
check_grep "charts/platform-vault-seeder/templates/job-core.yaml" "readOnlyRootFilesystem: true" "Job 1 read-only fs"
check_grep "charts/platform-vault-seeder/templates/job-core.yaml" "runAsNonRoot: true" "Job 1 non-root"
check_grep "charts/platform-vault-seeder/templates/job-apps.yaml" "readOnlyRootFilesystem: true" "Job 2 read-only fs"
check_grep "charts/platform-vault-seeder/templates/job-apps.yaml" "runAsNonRoot: true" "Job 2 non-root"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $TESTS_PASSED/$TESTS_RUN passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $TESTS_PASSED -eq $TESTS_RUN ]; then
  echo -e "${GREEN}✅ All validations passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some validations failed${NC}"
  exit 1
fi
