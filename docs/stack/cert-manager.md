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

```bash
helm upgrade --install cert-manager jetstack/cert-manager \
  --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

> `crds.enabled=true` installs the CRDs (`Certificate`, `ClusterIssuer`, etc.) as part of the Helm release so they are versioned and upgradeable.

---

## ClusterIssuers

Two `ClusterIssuer` resources are created (`kubernetes/cert-manager/clusterissuer.yaml`):

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
      - http01:
          ingress:
            ingressClassName: traefik
```

> The `ClusterIssuer` manifests use `${EMAIL}` — they are applied via `envsubst` so your `.env` variable is substituted at deploy time.

---

## Staging vs Production

| | Staging | Production |
|---|---|---|
| Rate limits | None | [Strict](https://letsencrypt.org/docs/rate-limits/) |
| Browser-trusted | ❌ | ✅ |
| Use case | Testing pipeline | Real workloads |

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

## HTTP-01 challenge gotcha

> ⚠️ **Do not configure a global HTTP→HTTPS redirect on Traefik's `web` entrypoint.**

Let's Encrypt sends the HTTP-01 challenge to port `80`. If Traefik redirects all HTTP traffic to HTTPS before the challenge solver can respond, the validation fails and the certificate is never issued.

This is why `traefik-values.yaml` has no `redirectTo` on the `web` entrypoint. Use `redirectScheme` middleware on individual routes instead.

---

## References

- [cert-manager documentation](https://cert-manager.io/docs/)
- [ACME HTTP-01 challenge](https://cert-manager.io/docs/configuration/acme/http01/)
- [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/)
- [cert-manager Helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
