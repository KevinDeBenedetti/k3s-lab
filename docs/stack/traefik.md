# Traefik — Ingress Controller

[Traefik](https://traefik.io) is the ingress controller for this cluster. It handles all inbound HTTP/HTTPS traffic, TLS termination, and routing to backend services.

k3s ships with Traefik by default, but this repo **disables the built-in Traefik** (`--disable=traefik`) and installs it via Helm for full configuration control.

---

## What Traefik does here

| Responsibility | Detail |
|---|---|
| Ingress controller | Routes traffic to services via `IngressRoute` CRDs |
| TLS termination | Handles HTTPS using certificates from cert-manager |
| Dashboard | Secured admin UI at `DASHBOARD_DOMAIN` |
| Metrics | Exposes Prometheus metrics on port `9100` |
| Access logs | JSON-formatted access logs |

---

## Helm install

```bash
helm upgrade --install traefik traefik/traefik \
  --version "${TRAEFIK_CHART_VERSION}" \
  --namespace ingress \
  --create-namespace \
  --values kubernetes/ingress/traefik-values.yaml \
  --set service.externalIPs="{${MASTER_IP}}"
```

> The `--set service.externalIPs` flag pins the LoadBalancer service to the master node's public IP. This is skipped automatically for local testing (`127.*` addresses).

---

## Values explained (`kubernetes/ingress/traefik-values.yaml`)

### EntryPoints

| EntryPoint | Port | Exposed | Purpose |
|---|---|---|---|
| `web` | 8000 | 80 | HTTP traffic |
| `websecure` | 8443 | 443 | HTTPS + TLS |
| `metrics` | 9100 | No | Prometheus scrape |

> **No global HTTP→HTTPS redirect.** A global redirect on the `web` entrypoint would intercept cert-manager's HTTP-01 ACME challenge before the solver can respond, breaking TLS issuance. Use a per-route `redirectScheme` middleware instead.

### TLS hardening

TLS 1.0 and 1.1 are disabled. Only strong cipher suites are allowed:

```yaml
tlsOptions:
  default:
    minVersion: VersionTLS12
    cipherSuites:
      - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
      - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
      - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      - TLS_AES_128_GCM_SHA256
      - TLS_AES_256_GCM_SHA384
      - TLS_CHACHA20_POLY1305_SHA256
    sniStrict: true
```

### Security context

Traefik runs as a non-root user (`runAsUser: 65532`) with a read-only filesystem and dropped capabilities (except `NET_BIND_SERVICE` for low ports).

### Prometheus metrics

The `serviceMonitor` is enabled so the kube-prometheus-stack Prometheus Operator auto-discovers and scrapes Traefik metrics.

---

## Dashboard

The Traefik dashboard is exposed via a secured `IngressRoute` at `DASHBOARD_DOMAIN`.

### Create the BasicAuth secret (run once)

```bash
make deploy-dashboard-secret
```

This runs:
```bash
kubectl create secret generic traefik-dashboard-auth \
  --from-literal=users="$(htpasswd -nb admin <DASHBOARD_PASSWORD>)" \
  -n ingress
```

> Username is always `admin`. Password is set via `DASHBOARD_PASSWORD` in `.env`.

### IngressRoute manifest

The dashboard manifest (`kubernetes/ingress/traefik-dashboard.yaml`) creates:

1. **`dashboard-basicauth` Middleware** — enforces HTTP Basic Authentication
2. **`dashboard-redirect-scheme` Middleware** — HTTP → HTTPS redirect
3. **`traefik-dashboard` IngressRoute** — routes `DASHBOARD_DOMAIN/dashboard` and `/api` to `api@internal`
4. **`traefik-dashboard-tls` Certificate** — cert-manager issues a Let's Encrypt certificate

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: ingress
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`${DASHBOARD_DOMAIN}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
      kind: Rule
      middlewares:
        - name: dashboard-basicauth
          namespace: ingress
      services:
        - name: api@internal
          kind: TraefikService
  tls:
    secretName: traefik-dashboard-tls
```

---

## Deploying your own services

To expose a service via Traefik, create an `IngressRoute`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  namespace: apps
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`app.example.com`)
      kind: Rule
      services:
        - name: my-app-svc
          port: 80
  tls:
    secretName: my-app-tls
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-tls
  namespace: apps
spec:
  secretName: my-app-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - app.example.com
```

See `kubernetes/apps/` for a complete example.

---

## References

- [Traefik Kubernetes documentation](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
- [IngressRoute reference](https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/)
- [Traefik Helm chart](https://github.com/traefik/traefik-helm-chart)
- [BasicAuth middleware](https://doc.traefik.io/traefik/middlewares/http/basicauth/)
