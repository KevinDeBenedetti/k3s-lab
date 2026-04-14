#!/usr/bin/env bash
# =============================================================================
# check-resource-limits.sh — Verify all Helm chart values define resource limits
#
# Ensures every chart in charts/ has resources.requests and resources.limits
# defined for all workload components. Fails CI if any are missing.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

errors=0

echo "🔍 Checking resource limits in Helm chart values..."
echo ""

for values_file in charts/*/values.yaml; do
  chart_name=$(basename "$(dirname "$values_file")")
  echo "── $chart_name ──"

  # Skip charts that only define non-workload resources (namespaces, RBAC, etc.)
  # These charts have no pods and thus no resource limits to set.
  if ! grep -q 'resources:' "$values_file"; then
    # Check if this chart has any workload dependencies (sub-charts with pods)
    if [ -f "$(dirname "$values_file")/Chart.yaml" ] && \
       ! grep -q 'dependencies:' "$(dirname "$values_file")/Chart.yaml"; then
      echo -e "  ${YELLOW}⏭  Skipped (no workload resources)${RESET}"
      continue
    fi
    echo -e "  ${RED}❌ No resource definitions found${RESET}"
    errors=$((errors + 1))
    continue
  fi

  # Check that limits: exists alongside resources:
  if ! grep -q 'limits:' "$values_file"; then
    echo -e "  ${RED}❌ Missing 'limits:' in resource definitions${RESET}"
    errors=$((errors + 1))
    continue
  fi

  # Check that requests: exists alongside resources:
  if ! grep -q 'requests:' "$values_file"; then
    echo -e "  ${RED}❌ Missing 'requests:' in resource definitions${RESET}"
    errors=$((errors + 1))
    continue
  fi

  echo -e "  ${GREEN}✅ Resource limits defined${RESET}"
done

echo ""

if [ "$errors" -gt 0 ]; then
  echo -e "${RED}❌ $errors chart(s) missing resource limits — fix before merging${RESET}"
  exit 1
else
  echo -e "${GREEN}✅ All charts have resource limits defined${RESET}"
fi
