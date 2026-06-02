# platform-vault-seeder

> Helm chart for declarative Vault secret seeding via Kubernetes Jobs

Replaces manual `task vault:seed` and `task vault:seed-apps` scripts with declarative, idempotent Kubernetes Job orchestration using `kubectl exec` into `vault-0`.

## Overview

This chart deploys **two sequential Kubernetes Jobs**:

### Job 1: `vault-seeder-core`
Runs **vault-configure** logic via `kubectl exec vault-0`:
- Creates **ESO read policy** + Kubernetes auth role
- Configures **OIDC auth method** (optional, conditional on `oidcClientId`)
- Creates **vault-admin policy** + OIDC role for admin access

### Job 2: `vault-seeder-apps`
Runs **vault-seed-apps** logic via `kubectl exec vault-0` (waits for Job 1):
- Seeds `secret/argocd/oidc`
- Seeds `secret/grafana/admin` + `secret/grafana/oauth`
- Seeds `secret/ghcr/pull`
- Seeds `secret/reactive-resume/prod`

**Dependency Orchestration**: Job 2 includes an initContainer that polls Job 1 status and waits for successful completion before starting.

## Design Philosophy

- **Option B** (kubectl exec): No direct Vault HTTP API exposure; leverages existing pod access
- **Declarative**: All logic in ConfigMaps + Job specs (no external scripts required)
- **Idempotent**: Jobs can be re-run safely (Vault `policy write` + `kv put` are idempotent)
- **Security**: Secrets in K8s Secret, scripts in ConfigMap, containers non-root + read-only filesystems
- **Conditional**: All secrets are optional; skipped if not provided in values

## Installation

### Helm CLI (Direct)

```bash
# Create values file from example
cat > /tmp/vault-seeder-values.yaml <<EOF
namespace:
  create: true
  name: vault-seeder

secrets:
  vaultRootToken: "hvs.xxxxxxxxxxxx"  # VAULT_ROOT_TOKEN

  # OIDC (optional, for argocd + grafana oauth)
  oidcClientId: "my-oidc-client-id"
  oidcClientSecret: "my-client-secret"
  vaultDomain: "vault.kevindb.dev"
  adminEmail: "admin@example.com"

  # ArgoCD
  argocdServerSecretKey: "my-secret-key"

  # Grafana
  grafanaPassword: "admin-password"

  # GHCR
  ghcrPat: "ghcr_xxxxxxxxxxxx"

  # Reactive Resume
  rrAuthSecret: "my-auth-secret"
  rrDbPassword: "db-password"
  rrBrowserlessToken: "browserless-token"
  rrS3AccessKeyId: "s3-key-id"
  rrS3SecretAccessKey: "s3-secret-key"
EOF

# Install chart
helm upgrade --install vault-seeder ./charts/platform-vault-seeder \
  -n vault-seeder --create-namespace \
  -f /tmp/vault-seeder-values.yaml
```

### ArgoCD Application (GitOps)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-seeder
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: "oci://ghcr.io/kevindebenedetti/charts"
    chart: platform-vault-seeder
    targetRevision: "0.1.0"
    helm:
      releaseName: vault-seeder
      values: |
        namespace:
          create: true
          name: vault-seeder

        secrets:
          vaultRootToken: xxxxxx  # From ExternalSecret
          oidcClientId: xxxxxx
          # ... all secrets here
  destination:
    server: https://kubernetes.default.svc
    namespace: vault-seeder
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Configuration

### Required Secrets

| Key                      | Description                       | Example            |
| ------------------------ | --------------------------------- | ------------------ |
| `secrets.vaultRootToken` | Vault root token (from bootstrap) | `hvs.xxxxxxxxxxxx` |

### Optional Secrets

**OIDC** (argocd + grafana oauth):
- `secrets.oidcClientId`
- `secrets.oidcClientSecret`
- `secrets.vaultDomain` (e.g., `vault.kevindb.dev`)
- `secrets.adminEmail`

**ArgoCD**:
- `secrets.argocdServerSecretKey` (random string for server auth)
- `secrets.homepageArgocdToken` (optional, for homepage integration)

**Grafana**:
- `secrets.grafanaPassword`

**GHCR** (private image pull):
- `secrets.ghcrPat` (GitHub Container Registry PAT)

**Reactive Resume**:
- `secrets.rrAuthSecret`
- `secrets.rrDbPassword`
- `secrets.rrBrowserlessToken`
- `secrets.rrS3AccessKeyId`
- `secrets.rrS3SecretAccessKey`

### Job Configuration

```yaml
jobCore:
  enabled: true
  image:
    repository: bitnami/kubectl
    tag: "1.32"
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "256Mi"
      cpu: "500m"
  ttlSecondsAfterFinished: 3600  # Auto-cleanup

jobApps:
  enabled: true
  # ... same structure
```

## Verification

### Watch Jobs

```bash
# Real-time job status
kubectl -n vault-seeder get jobs -w

# View logs
kubectl -n vault-seeder logs -f job/vault-seeder-core
kubectl -n vault-seeder logs -f job/vault-seeder-apps
```

### Verify Vault Configuration

After `vault-seeder-core` completes:

```bash
# ESO role
kubectl exec -n vault vault-0 -- vault read auth/kubernetes/role/eso

# OIDC config
kubectl exec -n vault vault-0 -- vault read auth/oidc/config

# Policies
kubectl exec -n vault vault-0 -- vault policy list
```

### Verify App Secrets

After `vault-seeder-apps` completes:

```bash
# Get secrets (requires VAULT_ROOT_TOKEN)
export VAULT_TOKEN="hvs.xxxxxxxxxxxx"
kubectl exec -n vault vault-0 -- vault kv get secret/argocd/oidc
kubectl exec -n vault vault-0 -- vault kv get secret/grafana/admin
kubectl exec -n vault vault-0 -- vault kv get secret/ghcr/pull
kubectl exec -n vault vault-0 -- vault kv get secret/reactive-resume/prod
```

### Verify ExternalSecrets Sync

Force immediate sync of all ExternalSecrets:

```bash
kubectl annotate externalsecret --all -A force-sync=$(date +%s) --overwrite
```

Check synced K8s Secrets:

```bash
kubectl get secret -n argocd argocd-secret
kubectl get secret -n monitoring grafana-admin-secret grafana-oauth-secret
kubectl get secret -n reactive-resume reactive-resume-secrets
```

## Troubleshooting

### Job Status Pending

**Cause**: Image pull timeout (bitnami/kubectl may need pull)  
**Fix**: Pre-pull image on cluster, or use local image

```bash
docker pull bitnami/kubectl:1.32
k3s ctr images import vault-seeder.tar.gz
```

### Job Fails with "kubectl: not found"

**Cause**: Image missing `kubectl` binary  
**Fix**: Use `bitnami/kubectl` which includes kubectl, or add sidecar

### Apps Job Fails to Wait for Core Job

**Cause**: initContainer timeout (default 5 min)  
**Fix**: Increase timeout in `job-apps.yaml` line ~120

```yaml
for i in {1..600}; do  # 300 → 600 = 20 minutes
```

### Vault Commands Hang or Timeout

**Cause**: Network isolation or firewall blocking `vault-0`  
**Fix**: Check pod-to-pod connectivity

```bash
kubectl exec -it -n vault-seeder vault-seeder-core-xxxx -- \
  kubectl exec -n vault vault-0 -- vault status
```

### Secrets Not Syncing to K8s

**Cause**: ExternalSecret not reading Vault correctly  
**Fix**:

```bash
# Check ESO logs
kubectl logs -n external-secrets -l app=external-secrets

# Check ExternalSecret status
kubectl describe externalsecret -n argocd argocd-oidc
kubectl describe externalsecret -n monitoring grafana-admin-secret
```

## FAQ

**Q: Can I run both jobs together (not sequential)?**  
A: Yes, disable the initContainer in `jobApps` and set `restartPolicy: Never`. Both will run in parallel, but Job 2 may fail if Vault isn't fully configured yet.

**Q: Can I use this in production?**  
A: Yes, it's idempotent and safe to re-run. But typically you'll run it once during cluster bootstrap, then clean up.

**Q: Where are the old `vault-seed-*.sh` scripts?**  
A: They're still in k3s-lab and infra `scripts/` directories, deprecated but not removed. You can delete them after this chart is validated.

**Q: How do I update existing secrets?**  
A: Re-run the chart with updated values. The `vault kv put` commands are idempotent.

**Q: Can I seed custom paths?**  
A: Yes, add more `_seed()` calls in `configmap-apps.yaml`. The chart is designed to be extended.

## Migration Path (from old scripts)

**Old workflow** (imperative):
```bash
task vault:seed            # vault-configure.sh
task vault:seed-apps       # vault-seed-apps.sh
task vault:seed-cloudflare # vault-seed-cloudflare.sh (infra-specific)
```

**New workflow** (declarative):
```bash
helm install vault-seeder ./charts/platform-vault-seeder \
  -n vault-seeder --create-namespace \
  -f values.yaml
```

**CloudFlare seeding** (separate chart or manual job):
```yaml
# TODO: platform-vault-seeder-cloudflare chart
# For now, keep task vault:seed-cloudflare in infra repo
```

## Clean Up

Jobs are auto-deleted after TTL (default 3600 seconds). Manual cleanup:

```bash
helm uninstall vault-seeder -n vault-seeder
kubectl delete ns vault-seeder
```

## See Also

- [k3s-lab Vault documentation](https://github.com/KevinDeBenedetti/k3s-lab/tree/main/docs)
- [External Secrets Operator](https://external-secrets.io)
- [Vault Kubernetes Auth](https://www.vaultproject.io/docs/auth/kubernetes)
