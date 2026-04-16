# Monitoring & Observability

The observability stack provides metrics, dashboards, and centralized logging for the entire cluster.

## Stack components

| Component | Role | Helm chart |
|---|---|---|
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) | Prometheus + Grafana + Alertmanager + exporters | `prometheus-community/kube-prometheus-stack` |
| [Loki](https://grafana.com/oss/loki/) | Centralized log storage | `grafana/loki` |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Log collector (DaemonSet) | `grafana/promtail` |

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   monitoring namespace                    │
│                                                          │
│  ┌──────────────┐    ┌───────────┐    ┌──────────────┐  │
│  │  Prometheus  │◄───│ Exporters │    │    Loki      │  │
│  │  (metrics)   │    │ (node,    │    │  (log store) │  │
│  └──────┬───────┘    │  cadvisor)│    └──────▲───────┘  │
│         │            └───────────┘           │          │
│  ┌──────▼───────┐                    ┌───────┴──────┐   │
│  │   Grafana    │◄───────────────────│   Promtail   │   │
│  │  (dashboards)│                    │  (DaemonSet) │   │
│  └──────────────┘                    └──────────────┘   │
│                                                          │
└──────────────────────────────────────────────────────────┘
         ▲ HTTPS via Traefik IngressRoute + cert-manager
```

---

## Prerequisites

Before deploying monitoring:

1. Base stack deployed (`make deploy`)
2. Grafana admin secret created:

```bash
make deploy-grafana-secret
```

This creates a `grafana-admin-secret` in the `monitoring` namespace with:
- `username: admin`
- `password: <GRAFANA_PASSWORD from .env>`

---

## Deploy

```bash
make deploy-monitoring
```

This deploys the monitoring stack via the `platform-monitoring` Helm chart (managed by ArgoCD).
The chart installs:

---

## kube-prometheus-stack

The `kube-prometheus-stack` Helm chart installs:

- **Prometheus** — metrics collection and storage
- **Grafana** — visualization dashboards
- **Alertmanager** — alert routing and silencing
- **kube-state-metrics** — Kubernetes object metrics
- **node-exporter** — host-level metrics (CPU, memory, disk)
- **Prometheus Operator** — manages `ServiceMonitor` and `PrometheusRule` CRDs

### Grafana access

```
URL:      https://<GRAFANA_DOMAIN>
Username: admin
Password: <GRAFANA_PASSWORD>
```

### Prometheus access (port-forward)

```bash
kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090
# Open: http://localhost:9090
```

### Alertmanager access (port-forward)

```bash
kubectl port-forward svc/alertmanager-operated -n monitoring 9093:9093
# Open: http://localhost:9093
```

---

## Grafana OAuth2 / SSO

Grafana supports OAuth2 login without any provider-specific configuration in k3s-lab.
All provider settings are injected at runtime via a Kubernetes Secret.

### How it works

The `kube-prometheus-values.yaml` mounts `grafana-oauth-secret` as an **optional** secret:

- **Secret absent** → Grafana starts normally with admin/password login
- **Secret present** → Grafana reads all `GF_AUTH_GENERIC_OAUTH_*` env vars from it

This means you can configure any OIDC-compatible provider (Infomaniak, Auth0, Keycloak,
Entra ID, etc.) simply by creating the secret with the right values.

### Enable OAuth2

1. Create the `grafana-oauth-secret` with your provider's settings (see [configuration.md](../configuration.md#oauth2--sso-for-grafana)):

   ```bash
   kubectl create secret generic grafana-oauth-secret \
     --from-literal=GF_AUTH_GENERIC_OAUTH_ENABLED="true" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_NAME="<Provider Name>" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID="<client-id>" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="<client-secret>" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_AUTH_URL="<authorize-url>" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_TOKEN_URL="<token-url>" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_API_URL="<userinfo-url>" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_SCOPES="openid email profile" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_USE_PKCE="true" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN="true" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN="true" \
     --from-literal=GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP="true" \
     --from-literal=GF_AUTH_DISABLE_LOGIN_FORM="true" \
     --namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
   ```

2. Restart Grafana:

   ```bash
   kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
   ```

### Disable OAuth2

Delete the secret and restart Grafana to revert to admin/password login:

```bash
kubectl delete secret grafana-oauth-secret -n monitoring
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

---

## Loki

[Loki](https://grafana.com/oss/loki/) stores logs indexed by labels (no full-text indexing). It is queried from Grafana using [LogQL](https://grafana.com/docs/loki/latest/query/).

Configuration (`charts/platform-monitoring/values.yaml` under the `loki:` key): deployed in single-binary mode with filesystem storage — suitable for single-node homelab use.

### Query logs in Grafana

1. Go to **Explore** → select **Loki** datasource
2. Use a LogQL query:

```logql
{namespace="apps"}
{namespace="ingress", job="traefik"} |= "error"
{app="my-app"} | json | level="error"
```

### Loki service endpoint (in-cluster)

```
http://loki.monitoring.svc.cluster.local:3100
```

---

## Promtail

[Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) is deployed as a `DaemonSet` — one pod per node. It:

1. Reads container logs from `/var/log/pods/`
2. Attaches Kubernetes labels (namespace, pod, container, app)
3. Pushes log streams to Loki

Configuration (`charts/platform-monitoring/values.yaml` under the `promtail:` key): uses the default pipeline stages to extract structured labels from Kubernetes metadata.

---

## Grafana dashboards

The following dashboards are available after deploy:

| Dashboard | Source | What it shows |
|---|---|---|
| Kubernetes cluster overview | kube-prometheus built-in | Node CPU/memory, pod counts |
| Node exporter | kube-prometheus built-in | Host CPU, memory, disk, network |
| Traefik | ServiceMonitor auto-discovery | Request rates, latencies, errors |
| Logs — Errors | `grafana-logs-dashboard.yaml` | Error-focused log explorer |

### Import additional dashboards

Grafana has a large community dashboard library. Import by ID from **Dashboards → Import**:

| ID | Name |
|---|---|
| `315` | Kubernetes cluster monitoring |
| `1860` | Node exporter full |
| `13713` | Loki log summary |
| `17501` | Traefik |

---

## Traefik metrics integration

Traefik exposes Prometheus metrics on port `9100`. The `serviceMonitor` in `traefik-values.yaml` creates a `ServiceMonitor` resource that tells Prometheus Operator to scrape Traefik automatically:

```yaml
metrics:
  prometheus:
    serviceMonitor:
      enabled: true
      namespace: ingress
      jobLabel: traefik
      interval: 30s
```

---

## Upgrade

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version <NEW_VERSION> \
  --namespace monitoring \
  --values charts/platform-monitoring/values.yaml \
  --reuse-values
```

Update the version in `charts/platform-monitoring/Chart.yaml` and let ArgoCD sync.

---

## References

- [kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki documentation](https://grafana.com/docs/loki/latest/)
- [Promtail documentation](https://grafana.com/docs/loki/latest/send-data/promtail/)
- [LogQL query language](https://grafana.com/docs/loki/latest/query/)
- [Grafana documentation](https://grafana.com/docs/grafana/latest/)
