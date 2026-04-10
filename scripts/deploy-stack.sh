#!/bin/bash
set -euo pipefail

# =============================================================================
# deploy-stack.sh — Bootstrap the base cluster stack
# Run FROM YOUR LOCAL MACHINE with kubectl already configured.
# Usage: ./scripts/deploy-stack.sh
# =============================================================================

K3S_LAB_RAW="${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}"

# Source run-mode preamble: detects local vs curl-pipe, exposes _lib / _k8s / _k8s_file
_run_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_run_src}" && "${_run_src}" != /dev/fd/* && -f "${_run_src}" ]]; then
  source "$(cd "$(dirname "${_run_src}")" && pwd)/../lib/run-mode.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW}/lib/run-mode.sh")
fi

_lib log.sh
_lib load-env.sh

# Load .env — only sets variables not already in the environment.
# When invoked via Make, all vars are already exported; this is a fallback for
# running the script directly from the k3s-lab repo root.
load_env "${_RUN_REPO:-.}/.env"

# --- Pinned versions (can be overridden via .env) ---
TRAEFIK_CHART_VERSION="${TRAEFIK_CHART_VERSION:-39.0.7}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.17.1}"

# --- Validate required vars ---
[ -n "${DOMAIN:-}" ]           || { log_error "DOMAIN is not set — add it to .env (e.g. DOMAIN=kevindb.dev)"; exit 1; }
[ -n "${EMAIL:-}" ]            || { log_error "EMAIL is not set — add it to .env (e.g. EMAIL=contact@kevindb.dev)"; exit 1; }
[ -n "${SERVER_IP:-}" ]        || { log_error "SERVER_IP is not set — add it to .env"; exit 1; }
[ -n "${DASHBOARD_DOMAIN:-}" ] || { log_error "DASHBOARD_DOMAIN is not set — add it to .env"; exit 1; }

log_info "Deploying base stack on cluster: $(kubectl config current-context)"

# --- 1. Namespaces ---
log_step "[1/4] Namespaces..."
kubectl apply -f "$(_k8s namespaces/namespaces.yaml)"

# --- 2. Traefik (Ingress Controller) ---
log_step "[2/4] Traefik ${TRAEFIK_CHART_VERSION}..."
helm repo add traefik https://helm.traefik.io/traefik --force-update
helm repo update traefik
# hostPort (defined in traefik-values.yaml) binds ports 80/443 directly on the
# host without kube-proxy SNAT, preserving real client IPs for ipAllowList middleware.
# externalIPs is no longer needed and must NOT be set — it would intercept traffic
# before hostPort rules and SNAT the source IP back to 10.42.0.1.

helm upgrade --install traefik traefik/traefik \
  --version "${TRAEFIK_CHART_VERSION}" \
  --namespace ingress \
  --create-namespace \
  --values "$(_k8s_file ingress/traefik-values.yaml)" \
  ${TRAEFIK_EXTRA_ARGS:-} \
  --wait \
  --timeout 120s

log_info "Waiting for Traefik to be ready..."
kubectl rollout status deployment/traefik -n ingress --timeout=120s

# --- 3. cert-manager ---
log_step "[3/4] cert-manager ${CERT_MANAGER_VERSION}..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update jetstack
helm upgrade --install cert-manager jetstack/cert-manager \
  --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait \
  --timeout 120s

log_info "Waiting for cert-manager to be ready..."
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=60s

# Give the webhook a few extra seconds to become reachable before applying CRs
sleep 10

# --- 4. ClusterIssuers ---
log_step "[4/4] ClusterIssuers..."
envsubst < "$(_k8s_file cert-manager/clusterissuer.yaml)" | kubectl apply -f -

# --- 5. Traefik dashboard (optional) ---
# Skip on local Lima testing — the domain/cert requires real internet reachability.
# The ACME HTTP-01 challenge cannot complete when the cluster is not publicly accessible.
if [[ "${SKIP_DASHBOARD:-false}" == "true" ]]; then
  log_info "Traefik dashboard IngressRoute... (skipped — SKIP_DASHBOARD=true)"
else
  log_info "Traefik dashboard IngressRoute..."
  envsubst < "$(_k8s_file ingress/traefik-dashboard.yaml)" | kubectl apply -f -
fi

echo ""
log_ok "Stack deployed successfully!"
echo ""
kubectl get nodes -o wide
echo ""
kubectl get pods -A | grep -v Completed
