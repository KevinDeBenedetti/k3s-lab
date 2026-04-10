# external-dns — Automatic DNS Management

[external-dns](https://github.com/kubernetes-sigs/external-dns) watches your cluster and automatically creates, updates, and (optionally) deletes DNS records in Cloudflare whenever you deploy an app.

---

## How it works

```
You push IngressRoute to git
         ↓
    ArgoCD syncs → kubectl applies IngressRoute
         ↓
    external-dns sees annotation: external-dns.alpha.kubernetes.io/hostname: myapp.kevindb.dev
         ↓
    Cloudflare API: creates A record  myapp.kevindb.dev → <Traefik LoadBalancer IP>
         ↓
    cert-manager DNS-01: Cloudflare API → creates TXT _acme-challenge.myapp.kevindb.dev
         ↓
    Let's Encrypt validates → issues TLS cert → stored in Kubernetes Secret
         ↓
    Traefik serves HTTPS at myapp.kevindb.dev ✅
```

No manual DNS management. No waiting for DNS propagation before pushing.

---

## Setup

### Prerequisites

1. Cloudflare API token seeded into Vault:
   ```bash
   make vault-seed-cloudflare        # seeds secret/cert-manager/cloudflare
   make vault-apply-externalsecrets  # syncs cloudflare-api-token-secret to external-dns namespace
   ```

2. Deploy external-dns:
   ```bash
   make deploy-external-dns
   ```

That's it. external-dns is now watching the cluster.

---

## Adding DNS to an app

Add one annotation to your `IngressRoute`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: apps
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.kevindb.dev   # ← this line
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.kevindb.dev`)
      kind: Rule
      services:
        - name: myapp
          port: 80
  tls:
    secretName: myapp-tls
```

Within ~1 minute, external-dns creates the A record in Cloudflare:

```
A  myapp.kevindb.dev → 37.27.215.168
```

### TXT ownership records

external-dns also creates a `TXT` record to track ownership:

```
TXT  _external-dns.myapp.kevindb.dev → "heritage=external-dns,owner=k3s-infra,resource=..."
```

This prevents external-dns from modifying records it didn't create.

---

## Policy: upsert-only (safe default)

The cluster is configured with `policy: upsert-only` — records are **never automatically deleted**.

This means:
- ✅ New IngressRoute → DNS record created
- ✅ IP changes → DNS record updated
- ✅ IngressRoute deleted → **DNS record is kept** (you delete manually if needed)

To delete a DNS record, remove it from the Cloudflare dashboard.

> To switch to `sync` policy (auto-delete), update `external-dns-values.yaml` and re-run `make deploy-external-dns`.

---

## Verify

```bash
# Check external-dns pod is running
make external-dns-status

# Tail live logs to see record creation events
make external-dns-logs

# Verify record in Cloudflare
dig myapp.kevindb.dev +short
```

Expected log output:
```json
{"level":"info","msg":"Desired change: CREATE myapp.kevindb.dev A [37.27.215.168]"}
{"level":"info","msg":"1 record(s) in zone kevindb.dev were successfully updated"}
```

---

## Sources watched

external-dns reads hostnames from three sources:

| Source | How it discovers hostnames |
|---|---|
| `traefik-proxy` | Reads `Host()` rules from `IngressRoute` CRDs + `external-dns.alpha.kubernetes.io/hostname` annotation |
| `ingress` | Reads standard Kubernetes `Ingress` resources |
| `service` | Reads `LoadBalancer` services with hostname annotation |

---

## Relationship with cert-manager

Both external-dns and cert-manager use the same Cloudflare API token from Vault:

| Component | Vault path | K8s Secret | Namespace | Purpose |
|---|---|---|---|---|
| cert-manager | `secret/cert-manager/cloudflare` | `cloudflare-api-token-secret` | `cert-manager` | DNS-01 ACME challenge |
| external-dns | `secret/cert-manager/cloudflare` | `cloudflare-api-token-secret` | `external-dns` | Create/update A records |

Both are synced by ESO via `make vault-apply-externalsecrets`.

---

## References

- [external-dns GitHub](https://github.com/kubernetes-sigs/external-dns)
- [external-dns Cloudflare provider](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/cloudflare.md)
- [external-dns Traefik tutorial](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/traefik-proxy.md)
- [Helm chart](https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns)
