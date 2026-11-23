# cert-manager — Automatic TLS

[cert-manager](https://cert-manager.io) automates TLS certificate issuance and renewal from [Let's Encrypt](https://letsencrypt.org). Certificates are stored as Kubernetes Secrets and automatically rotated before expiry.

---

## How it works

```
Browser → Traefik (:443) → Service
                              ↑
                         cert-manager
                              ↑
                        Let's Encrypt ACME
                              ↑
                    HTTP-01 challenge via Traefik (:80)
```

1. You create a `Certificate` resource referencing a `ClusterIssuer`
2. cert-manager creates an ACME order with Let's Encrypt
3. Let's Encrypt sends an HTTP-01 challenge to `http://<domain>/.well-known/acme-challenge/<token>`
4. cert-manager deploys a temporary solver pod; Traefik routes the challenge to it
5. Let's Encrypt validates the domain → issues the certificate
6. cert-manager stores the certificate in a Kubernetes Secret
7. Traefik reads the Secret and serves HTTPS

> Certificates are automatically renewed ~30 days before expiry.

---

## Helm install

cert-manager is installed from the `platform-cert-manager` wrapper chart, which
pins the upstream `cert-manager` chart (and so its version) in its
[`Chart.yaml`](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/charts/platform-cert-manager/Chart.yaml):

```bash
helm upgrade --install cert-manager oci://ghcr.io/kevindebenedetti/charts/platform-cert-manager \
  --version <k3s-lab release, e.g. 0.25.0> \
  --namespace cert-manager \
  --create-namespace
```

The wrapper sets `crds.enabled: true`, so the CRDs (`Certificate`,
`ClusterIssuer`, …) are part of the release and upgraded with it. With ArgoCD,
point an Application at the same chart and version instead.

---

## ClusterIssuers

Two `ClusterIssuer` resources are defined in your consuming repo's `platform/` directory (or managed via ArgoCD):

### Staging (for testing)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      # DNS-01 via Cloudflare — for ${DOMAIN} and all its subdomains
      # Works even when apex domain points to Vercel or another provider
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
        selector:
          dnsZones:
            - "${DOMAIN}"
      # HTTP-01 fallback — for any domain not covered by the dns01 selector
      - http01:
          ingress:
            ingressClassName: traefik
```

### Production

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${EMAIL}
    privateKeySecretRef:
      name: letsencrypt-production-account-key
    solvers:
      # DNS-01 via Cloudflare — for ${DOMAIN} and all its subdomains
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
        selector:
          dnsZones:
            - "${DOMAIN}"
      # HTTP-01 fallback — for any domain not covered by the dns01 selector
      - http01:
          ingress:
            ingressClassName: traefik
```

> Replace `${EMAIL}` and `${DOMAIN}` with your own values in your config repo:
> nothing in k3s-lab substitutes them.

---

## Staging vs Production

|                 | Staging          | Production                                          |
| --------------- | ---------------- | --------------------------------------------------- |
| Rate limits     | None             | [Strict](https://letsencrypt.org/docs/rate-limits/) |
| Browser-trusted | ❌                | ✅                                                   |
| Use case        | Testing pipeline | Real workloads                                      |

**Always test with staging first.** Production is rate-limited to 5 duplicate certificates per week per domain.

---

## Using a certificate in an IngressRoute

```yaml
# 1. Request the certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-tls
  namespace: apps
spec:
  secretName: my-app-tls          # Secret where the cert is stored
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - app.example.com

---
# 2. Reference it in the IngressRoute
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
    secretName: my-app-tls        # Must match Certificate.spec.secretName
```

---

## Check certificate status

```bash
# List all certificates
kubectl get certificate -A

# Describe a certificate (shows ACME order status)
kubectl describe certificate my-app-tls -n apps

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager --tail=50
```

Expected output when ready:
```
NAME         READY   SECRET       AGE
my-app-tls   True    my-app-tls   5m
```

---

## HTTP-01 and the HTTP→HTTPS redirect

`platform-traefik` **does** redirect every request on the `web` entrypoint
(port 80) to `websecure` (443), globally
([`values.yaml`](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/charts/platform-traefik/values.yaml),
`ports.web.http.redirections`).

Let's Encrypt sends HTTP-01 challenges to port 80, so with this chart a
challenge request is redirected to HTTPS before it reaches cert-manager's
solver. Whether it then succeeds depends on Traefik also serving the solver's
route on `websecure`, which this repository does not test. If HTTP-01 orders
stay `pending`, either:

- use DNS-01 (next section), which never goes through Traefik, or
- turn the global redirect off in your values and redirect per route instead,
  with a `redirectScheme` middleware:

  ```yaml
  # platform-traefik values in your config repo
  traefik:
    ports:
      web:
        http:
          redirections: null
  ```

---

## DNS-01 (recommended for a homelab)

The examples use Cloudflare; cert-manager supports
[many other DNS providers](https://cert-manager.io/docs/configuration/acme/dns01/#supported-dns01-providers).

Use DNS-01 when:
- The apex domain (`example.com`) DNS points elsewhere (e.g. Vercel) — HTTP-01 would reach the wrong server
- You need **wildcard certificates** (`*.example.com`) — Let's Encrypt only issues these via DNS-01
- The cluster is not publicly reachable on port 80 — the usual homelab case

```
cert-manager → Cloudflare API → creates TXT _acme-challenge.example.com
Let's Encrypt → DNS lookup → validates TXT → issues certificate
```

### Setup

1. Create a Cloudflare API Token with:
   - Permission: `Zone - DNS - Edit`
   - Permission: `Zone - Zone - Read`
   - Zone Resources: `Include - All Zones`

2. Put the token in the `cert-manager` namespace as `cloudflare-api-token-secret`
   (key `api-token`) — either directly, or from Vault through an
   `ExternalSecret` kept in your config repo:

```bash
kubectl -n cert-manager create secret generic cloudflare-api-token-secret \
  --from-literal=api-token="$CLOUDFLARE_API_TOKEN"
```

3. The `ClusterIssuer` manifests already include a DNS-01 solver for `${DOMAIN}`:

```yaml
solvers:
  - dns01:
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-api-token-secret
          key: api-token
    selector:
      dnsZones:
        - "${DOMAIN}"
  - http01:
      ingress:
        ingressClassName: traefik  # fallback for other domains
```

> Replace `${DOMAIN}` with your own domain in your config repo: nothing in
> k3s-lab substitutes it.

### Wildcard certificate example

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-tls
  namespace: apps
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
    - "example.com"
```

---

## References

- [cert-manager documentation](https://cert-manager.io/docs/)
- [ACME HTTP-01 challenge](https://cert-manager.io/docs/configuration/acme/http01/)
- [ACME DNS-01 challenge](https://cert-manager.io/docs/configuration/acme/dns01/)
- [cert-manager Cloudflare DNS-01](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
- [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/)
- [cert-manager Helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
