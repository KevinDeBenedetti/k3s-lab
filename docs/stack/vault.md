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

**UI access:** the chart exposes no ingress: the UI is the `vault` ClusterIP service. Use `kubectl -n vault port-forward svc/vault 8200` and open `https://localhost:8200`, or publish it yourself from your config repo (behind a VPN or an IP allow-list, preferably).

---

## Secret path layout

| Vault path                 | Kubernetes Secret        | Namespace    |
| -------------------------- | ------------------------ | ------------ |
| `secret/argocd/oidc`       | `argocd-secret`          | `argocd`     |
| `secret/grafana/admin`     | `grafana-admin-secret`   | `monitoring` |
| `secret/grafana/oauth`     | `grafana-oauth-secret`   | `monitoring` |
| `secret/traefik/dashboard` | `traefik-dashboard-auth` | `ingress`    |

---

## Prerequisites

Add to `.env`:

```bash
VAULT_DOMAIN=vault.example.com
```

Add DNS A record: `vault.example.com → SERVER_IP`

---

## Step 1 — Deploy Vault

**First, the `vault-tls` secret.** The listener terminates TLS itself and the
chart mounts the `vault-tls` secret unconditionally: without it the pod never
starts. Create it in the `vault` namespace before installing, with a
cert-manager `Certificate` (see [cert-manager](./cert-manager.md)) or by hand.

Then deploy the `platform-vault` OCI chart, via ArgoCD or directly with Helm:

```bash
helm upgrade --install platform-vault \
  oci://ghcr.io/kevindebenedetti/charts/platform-vault \
  --version <k3s-lab release, e.g. 0.25.0> \
  --namespace vault --create-namespace \
  --values <your config repo>/platform/vault/values.yaml   # optional overrides
```

This installs Vault into the `vault` namespace (StatefulSet `vault`, pod
`vault-0`, the defaults of the `task vault:*` scripts) with:
- Single-replica Raft storage (5 Gi PVC on `local-path`)
- TLS on the listener (`:8200`), from the `vault-tls` secret
- The UI as a `ClusterIP` service only: the chart ships **no ingress**. Reach it
  with `kubectl -n vault port-forward svc/vault 8200`, or expose it
  deliberately from your config repo.

See the [chart README](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/charts/platform-vault/README.md)
for the full topology.

> ⚠️ Vault starts **sealed and uninitialized** — proceed to Step 2.

---

## Step 2 — Initialize Vault

```bash
task vault:init
```

This script:
1. Calls `vault operator init` (3 key shares, threshold 2: `VAULT_KEY_SHARES`
   and `VAULT_KEY_THRESHOLD`)
2. Unseals Vault with the generated keys, stopping at the threshold
3. Runs the configure steps — the same ones `task vault:configure` re-applies
   at any time:
   - enables KV v2 at `secret/`
   - enables and configures Kubernetes auth
   - writes every `*.hcl` file of the policy directory as a policy named after
     the file
   - creates the `eso` role (policy `eso-read`)
   - sets up OIDC login (policy `vault-admin`) when `OIDC_CLIENT_ID`,
     `OIDC_CLIENT_SECRET`, `OIDC_ISSUER_URL`, `VAULT_DOMAIN` and `ADMIN_EMAIL`
     are **all** set; with only some of them it stops before changing anything

On an already initialised Vault it skips step 1, unseals if needed, and
configures. All of it lives in `lib/vault.sh`; see
[Configuration](../configuration.md) for every variable.

### Policies

The shipped policies are in `vault/policies/`: `eso-read` lets External Secrets
read all of `secret/`, and `vault-admin` is the OIDC administrator. To narrow
them, copy the directory into your config repo, edit it, and set
`VAULT_POLICY_DIR` to the copy. Every `*.hcl` file there becomes a policy, so
you can add your own. `configure` refuses a directory without `eso-read.hcl`,
and without `vault-admin.hcl` when OIDC is on.

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
VAULT_ROOT_TOKEN=hvs.XXXXX task vault:seed
```

It reads its values from `.env` (or the environment) and writes each secret
whose values are set, skipping the others with a message:

- `secret/argocd/oidc`: OIDC `clientID` + `clientSecret` (`OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`)
- `secret/grafana/admin`: Grafana admin `username` + `password` (`GRAFANA_PASSWORD`)
- `secret/grafana/oauth`: all `GF_AUTH_*` OAuth settings (`OIDC_CLIENT_ID`, `OIDC_AUTH_URL`, …)
- `secret/traefik/dashboard`: the htpasswd `users` string (`DASHBOARD_PASSWORD`, needs `htpasswd`)

---

## Step 4 — Deploy External Secrets Operator

```bash
ArgoCD deploys External Secrets Operator from Git. No manual deploy command is needed.
```

Installs the `external-secrets/external-secrets` Helm chart into the `external-secrets` namespace.

---

## Step 5 — Apply ClusterSecretStore + ExternalSecrets

```bash
# In your config repo:
kubectl apply -f secrets/cluster-secret-store.yaml
kubectl apply -f secrets/
```

ESO immediately begins syncing. Check status:

```bash
task vault:status
```

---

## Day 2 — Unsealing after reboot

Vault becomes sealed when the pod restarts. Unseal with:

```bash
task vault:unseal
```

It feeds `VAULT_UNSEAL_KEY_1`, `VAULT_UNSEAL_KEY_2`, … from `.env` one at a
time and stops as soon as Vault reports unsealed. A key that is not set is asked
for on the terminal.

Or interactively:
```bash
kubectl exec -it -n vault vault-0 -- env VAULT_SKIP_VERIFY=true vault operator unseal
```

## Audit log

Enable it once, to **stdout** — never to a file on a volume: an unrotated file
fills the disk, and Vault then refuses every request.

```bash
kubectl exec -it -n vault vault-0 -- env VAULT_SKIP_VERIFY=true VAULT_TOKEN=<root> \
  vault audit enable file file_path=stdout
```

---

## Adding new secrets

1. Write to Vault:
   ```bash
    kubectl exec -n vault vault-0 -- \
      env VAULT_TOKEN="${VAULT_TOKEN:?set-from-vault-init}" VAULT_SKIP_VERIFY=true \
      vault kv put secret/myapp/config \
        DB_PASSWORD=secret123 \
        API_KEY=key456
   ```

2. Create an ExternalSecret manifest:
   ```yaml
   apiVersion: external-secrets.io/v1
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

## Taskfile reference
