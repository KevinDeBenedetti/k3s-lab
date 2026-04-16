#!/bin/bash
set -euo pipefail

# =============================================================================
# deploy-monitoring.sh — Deploy the observability stack (Phase 1)
# Run FROM YOUR LOCAL MACHINE with kubectl + helm already configured.
# Prerequisites: base stack deployed (make deploy)
#
# What this deploys:
#   - kube-prometheus-stack (Prometheus + Grafana + Alertmanager + exporters)
#   - Loki (centralized logs storage)
#   - Promtail (Kubernetes logs collector)
#   - Grafana logs dashboard (error-focused)
#   - Grafana IngressRoute + TLS certificate
# =============================================================================

# shellcheck source=lib/script-init.sh
_src="${BASH_SOURCE[0]:-}"
if [[ -n "${_src}" && "${_src}" != /dev/fd/* && -f "${_src}" ]]; then
  source "$(cd "$(dirname "${_src}")" && pwd)/../lib/script-init.sh"
else
  # shellcheck source=/dev/null
  source <(curl -fsSL "${K3S_LAB_RAW:-https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main}/lib/script-init.sh")
fi
unset _src
_lib require-vars.sh
_lib helm-repo.sh

# --- Context (overridable via env for alternate clusters) ---
KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-k3s-infra}"

# --- Pinned versions (overridable via .env) ---
KUBE_PROMETHEUS_VERSION="${KUBE_PROMETHEUS_VERSION:-82.10.3}"
LOKI_VERSION="${LOKI_VERSION:-6.35.1}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-6.17.1}"

# --- Validate ---
require_vars GRAFANA_DOMAIN

log_info "Deploying observability stack on cluster: $(kubectl config current-context)"

# --- Pre-flight: cluster must be reachable ---
if ! kubectl --context "${KUBECONFIG_CONTEXT}" cluster-info --request-timeout=5s >/dev/null 2>&1; then
  log_error "Cannot reach cluster '${KUBECONFIG_CONTEXT}' API server (timeout)."
  echo "   k3s may have crashed. On your VPS run: sudo systemctl restart k3s"
  exit 1
fi

# --- Pre-flight: grafana-admin-secret must exist ---
if ! kubectl --context "${KUBECONFIG_CONTEXT}" get secret grafana-admin-secret -n monitoring &>/dev/null 2>&1; then
  log_warn "grafana-admin-secret not found in monitoring namespace."
  echo "   Run first:  make deploy-grafana-secret GRAFANA_PASSWORD=<your-password>"
  exit 1
fi

# --- 1. Helm repo ---
log_step "[1/5] Helm repos..."
helm_add_repo prometheus-community https://prometheus-community.github.io/helm-charts
helm_add_repo grafana https://grafana.github.io/helm-charts

# --- 2. kube-prometheus-stack ---
log_step "[2/5] kube-prometheus-stack ${KUBE_PROMETHEUS_VERSION}..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${KUBE_PROMETHEUS_VERSION}" \
  --namespace monitoring \
  --create-namespace \
  --values "$(_k8s_file monitoring/kube-prometheus-values.yaml)" \
  --set "grafana.grafana\.ini.server.root_url=https://${GRAFANA_DOMAIN}" \
  --wait \
  --timeout 600s

log_info "Waiting for Grafana to be ready..."
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=120s

log_info "Waiting for Prometheus to be ready..."
kubectl rollout status statefulset/prometheus-kube-prometheus-stack-prometheus -n monitoring --timeout=120s

# Enable Traefik ServiceMonitor now that kube-prometheus-stack CRDs exist
log_step "Enabling Traefik ServiceMonitor..."
kubectl apply -f "$(_k8s monitoring/traefik-servicemonitor.yaml)"

# --- 3. Loki ---
log_step "[3/5] Loki ${LOKI_VERSION}..."
helm upgrade --install loki grafana/loki \
  --version "${LOKI_VERSION}" \
  --namespace monitoring \
  --create-namespace \
  --values "$(_k8s_file monitoring/loki-values.yaml)" \
  --wait \
  --timeout 600s

# --- 4. Promtail ---
log_step "[4/5] Promtail ${PROMTAIL_VERSION}..."
helm upgrade --install promtail grafana/promtail \
  --version "${PROMTAIL_VERSION}" \
  --namespace monitoring \
  --create-namespace \
  --values "$(_k8s_file monitoring/promtail-values.yaml)" \
  --wait \
  --timeout 600s

# --- 5. Grafana IngressRoute + TLS + Logs Dashboard ---
log_step "[5/5] Grafana IngressRoute + TLS Certificate + Logs Dashboard..."
GRAFANA_DOMAIN="${GRAFANA_DOMAIN}" envsubst < "$(_k8s_file monitoring/grafana-ingress.yaml)" | kubectl apply -f -
kubectl apply -f "$(_k8s monitoring/grafana-logs-dashboard.yaml)"

echo ""
log_ok "Observability stack deployed!"
echo ""
echo "   Grafana:       https://${GRAFANA_DOMAIN}  (cert issues in ~30s)"
echo "   Prometheus:    kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090"
echo "   Loki (svc):    http://loki.monitoring.svc.cluster.local:3100"
echo "   Explore logs:  Grafana -> Explore -> Loki"
echo ""
echo "   Certificate status:"
kubectl get certificate -n monitoring
echo ""
kubectl get pods -n monitoring
