# Vault + External Secrets Operator

This guide covers deploying [HashiCorp Vault](https://developer.hashicorp.com/vault) as a central secret store and [External Secrets Operator (ESO)](https://external-secrets.io) to sync secrets into Kubernetes automatically.

---

## Architecture

```
[Vault]  namespace: vault
   │  Kubernetes auth method (ServiceAccount token exchange)
   ▼
[ESO ClusterSecretStore]  — cluster-wide, references Vault KV v2
   │  ExternalSecret CRs per namespace
   ▼
[Kubernetes Secrets]  — consumed natively by pods / Helm charts
```

**Storage:** Vault uses Raft integrated storage backed by a `local-path` PVC — no external Consul or etcd required.

**Auth:** ESO authenticates to Vault via the Kubernetes auth method. ESO's own ServiceAccount token is exchanged for a scoped Vault token at sync time.

**UI access:** Vault UI is behind the WireGuard `vpn-only` middleware. Connect with `make wg-up` before opening the browser.

---

## Secret path layout

| Vault path | Kubernetes Secret | Namespace |
|---|---|---|
| `secret/argocd/oidc` | `argocd-secret` | `argocd` |
| `secret/grafana/admin` | `grafana-admin-secret` | `monitoring` |
| `secret/grafana/oauth` | `grafana-oauth-secret` | `monitoring` |
| `secret/traefik/dashboard` | `traefik-dashboard-auth` | `ingress` |

---

## Prerequisites

Add to `.env`:

```bash
VAULT_DOMAIN=vault.example.com
VAULT_CHART_VERSION=0.29.1   # optional — pin to avoid surprise upgrades
ESO_CHART_VERSION=0.14.3     # optional
```

Add DNS A record: `vault.example.com → SERVER_IP`

---

## Step 1 — Deploy Vault

```bash
make deploy-vault
```

This installs the `hashicorp/vault` Helm chart into the `vault` namespace with:
- Single-replica Raft storage (5 Gi PVC on `local-path`)
- UI enabled (ClusterIP, exposed via Traefik IngressRoute)
- VPN-only IngressRoute + Let's Encrypt TLS cert

> ⚠️ Vault starts **sealed and uninitialized** — proceed to Step 2.

---

## Step 2 — Initialize Vault

```bash
make vault-init
```

This script:
1. Calls `vault operator init` (3 key shares, threshold 2)
2. Unseals Vault with the generated keys
3. Enables KV v2 at `secret/`
4. Enables and configures Kubernetes auth
5. Creates the `eso-read` policy and `eso` role

**Output:**

```
════════════════════════════════════════════════════════════════
  ⚠️  VAULT INIT OUTPUT — SAVE THIS IMMEDIATELY
  These keys and token will NEVER be shown again.
════════════════════════════════════════════════════════════════

Unseal Key 1: abc123...
Unseal Key 2: def456...
Unseal Key 3: ghi789...

Root Token:   hvs.XXXXX
```

> 📋 **Store these in a password manager immediately.** You will need 2 of the 3 unseal keys any time the Vault pod restarts (e.g., after a node reboot).

Add to `.env` for convenience (never commit):
```bash
VAULT_ROOT_TOKEN=hvs.XXXXX
VAULT_UNSEAL_KEY_1=abc123...
VAULT_UNSEAL_KEY_2=def456...
```

---

## Step 3 — Seed secrets into Vault

```bash
VAULT_ROOT_TOKEN=hvs.XXXXX make vault-seed
```

The interactive prompt walks you through storing each secret:

- `secret/argocd/oidc` — Infomaniak OIDC `clientID` + `clientSecret`
- `secret/grafana/admin` — Grafana admin `username` + `password`
- `secret/grafana/oauth` — All `GF_AUTH_*` OAuth env vars
- `secret/traefik/dashboard` — Traefik BasicAuth `password`

---

## Step 4 — Deploy External Secrets Operator

```bash
make deploy-eso
```

Installs the `external-secrets/external-secrets` Helm chart into the `external-secrets` namespace.

---

## Step 5 — Apply ClusterSecretStore + ExternalSecrets

```bash
kubectl apply -f kubernetes/external-secrets/cluster-secret-store.yaml

# In your infra repo:
kubectl apply -f kubernetes/vault/external-secrets/
```

ESO immediately begins syncing. Check status:

```bash
make vault-status
```

---

## Day 2 — Unsealing after reboot

Vault becomes sealed when the pod restarts. Unseal with:

```bash
make vault-unseal   # requires VAULT_UNSEAL_KEY_1 + VAULT_UNSEAL_KEY_2 in .env
```

Or interactively:
```bash
kubectl exec -n vault vault-0 -- vault operator unseal
```

---

## Adding new secrets

1. Write to Vault:
   ```bash
   kubectl exec -n vault vault-0 -- \
     env VAULT_TOKEN=<root-token> \
     vault kv put secret/myapp/config \
       DB_PASSWORD=secret123 \
       API_KEY=key456
   ```

2. Create an ExternalSecret manifest:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: myapp-secret
     namespace: apps
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: vault
       kind: ClusterSecretStore
     target:
       name: myapp-secret
       creationPolicy: Owner
     data:
       - secretKey: DB_PASSWORD
         remoteRef:
           key: secret/myapp/config
           property: DB_PASSWORD
       - secretKey: API_KEY
         remoteRef:
           key: secret/myapp/config
           property: API_KEY
   ```

3. Apply: `kubectl apply -f myapp-externalsecret.yaml`

---

## Makefile reference

| Target | Description |
|---|---|
| `deploy-vault` | Install/upgrade Vault via Helm |
| `deploy-eso` | Install/upgrade External Secrets Operator |
| `vault-init` | Initialize, unseal, enable K8s auth, create policies |
| `vault-unseal` | Unseal Vault after a node reboot |
| `vault-configure` | Re-apply policies + roles (idempotent) |
| `vault-seed` | Interactive: store all managed secrets into Vault |
| `vault-status` | Show seal status + ESO sync status |
