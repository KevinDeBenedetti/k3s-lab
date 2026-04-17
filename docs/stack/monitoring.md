# Monitoring & Observability

The observability stack provides dashboards and centralized logging for the entire cluster.

## Stack components

| Component | Role | Helm chart |
|---|---|---|
| [Grafana](https://grafana.com/grafana/) | Visualization dashboards | `grafana/grafana` |
| [Loki](https://grafana.com/oss/loki/) | Centralized log storage | `grafana/loki` |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) | Log collector (DaemonSet) | `grafana/promtail` |

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   monitoring namespace                    │
│                                                          │
│  ┌──────────────┐                    ┌──────────────┐   │
│  │   Grafana    │◄───────────────────│     Loki     │   │
│  │  (dashboards)│                    │  (log store) │   │
│  └──────────────┘                    └──────▲───────┘   │
│                                             │           │
│                                      ┌──────┴──────┐   │
│                                      │   Promtail  │   │
│                                      │  (DaemonSet)│   │
│                                      └─────────────┘   │
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

### Grafana access

```
URL:      https://<GRAFANA_DOMAIN>
Username: admin
Password: <GRAFANA_PASSWORD>
```

---

## Grafana OAuth2 / SSO

Grafana supports OAuth2 login without any provider-specific configuration in k3s-lab.
All provider settings are injected at runtime via a Kubernetes Secret.

### How it works

The monitoring values mount `grafana-oauth-secret` as an **optional** secret:

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
   kubectl rollout restart deployment/monitoring-grafana -n monitoring
   ```

### Disable OAuth2

Delete the secret and restart Grafana to revert to admin/password login:

```bash
kubectl delete secret grafana-oauth-secret -n monitoring
kubectl rollout restart deployment/monitoring-grafana -n monitoring
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

| Dashboard | Source | What it shows |
|---|---|---|
| Logs — Errors | `grafana-logs-dashboard.yaml` | Error-focused log explorer (Loki) |

### Import additional dashboards

Grafana has a large community dashboard library. Import by ID from **Dashboards → Import**:

| ID | Name |
|---|---|
| `13713` | Loki log summary |

---

## Upgrade

Update the chart version in `charts/platform-monitoring/Chart.yaml` and let ArgoCD sync.

---

## References

- [Grafana documentation](https://grafana.com/docs/grafana/latest/)
- [Loki documentation](https://grafana.com/docs/loki/latest/)
- [Promtail documentation](https://grafana.com/docs/loki/latest/send-data/promtail/)
- [LogQL query language](https://grafana.com/docs/loki/latest/query/)
