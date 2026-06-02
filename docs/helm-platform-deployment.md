# Platform Deployment — Helm Wrapper Chart

This document explains the new `platform-deployment` umbrella chart and how to refactor `infra` to consume it.

## What's Changed (v0.1.0)

**Before:** Each platform component was deployed separately via ArgoCD Applications
- `argocd/applications/argocd.yaml` → platform-argocd chart
- `argocd/applications/monitoring.yaml` → platform-monitoring chart
- `argocd/applications/vault.yaml` → platform-vault chart
- ... (8+ separate Applications)

**After:** All components deployed via a single umbrella chart
- Single `argocd/applications/platform.yaml` → platform-deployment chart
- Dependencies managed by Helm (like npm, pip)
- Cleaner dependency graph
- Single source of truth for versions

## Architecture

```
platform-deployment (umbrella chart v0.1.0)
├─ platform-argocd (0.9.2)
│  └─ argo-cd (9.5.17)
├─ platform-monitoring (0.9.1)
│  ├─ kube-prometheus-stack
│  ├─ loki
│  └─ promtail
├─ platform-vault (0.9.1)
│  └─ vault (Helm chart)
├─ platform-external-secrets (0.9.1)
│  └─ external-secrets (operator)
├─ platform-cert-manager (0.8.0)
│  └─ cert-manager
├─ platform-traefik (0.8.0)
│  └─ traefik
└─ platform-security (0.8.0)
   └─ Various PSS + NetworkPolicy manifests
```

## Benefits

| Aspect                 | Before                                 | After                                |
| ---------------------- | -------------------------------------- | ------------------------------------ |
| **Dependencies**       | Manual version tracking in cluster.env | Helm manages via Chart.yaml          |
| **Update versions**    | Edit cluster.env + run 8 updates       | `helm dependency update` (1 command) |
| **Deploy all**         | Commit 8 Applications + ArgoCD syncs   | 1 Application (`platform.yaml`)      |
| **Rollback**           | Roll back each component separately    | Helm rollback (atomic)               |
| **Troubleshoot**       | Check 8 Application statuses           | `helm status platform-deployment`    |
| **CI/CD validation**   | Check each chart version               | `helm dependency verify`             |
| **Dependency clarity** | Read docs for each chart               | `helm dependency list` shows all     |

## Usage

### Option 1: Deploy via ArgoCD Application (Recommended)

Create `infra/argocd/applications/platform.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: "oci://ghcr.io/kevindebenedetti/charts"
    chart: platform-deployment
    targetRevision: "0.1.0"
    helm:
      releaseName: platform
      values: |
        # Cluster-specific overrides (from infra/platform/deployment/values.yaml)
        platform-argocd:
          argo-cd:
            global:
              domain: argocd.kevindb.dev
            # ... more ArgoCD config

        platform-monitoring:
          grafana:
            # ... Grafana config
            adminPassword: "..."

        # ... more platform-* configs
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Option 2: Deploy via Helm directly

```bash
# Update dependencies (fetches all platform-* charts)
helm dependency update k3s-lab/charts/platform-deployment

# Install with cluster-specific values
helm install platform-deployment \
  k3s-lab/charts/platform-deployment \
  --version 0.1.0 \
  -f infra/platform/deployment/values.yaml \
  -n argocd
```

## Refactoring `infra` to Use platform-deployment

### Step 1: Create deployment values file

Create `infra/platform/deployment/values.yaml`:

```yaml
# Platform deployment — Hetzner prod configuration
#
# This file contains ONLY cluster-specific overrides for platform-deployment chart.
# All values are passed directly to subcharts (platform-argocd, platform-monitoring, etc.)

platform-argocd:
  enabled: true
  argo-cd:
    global:
      domain: argocd.kevindb.dev
    configs:
      cm:
        url: https://argocd.kevindb.dev
        # ... rest of ArgoCD config (move from current argocd/values.yaml)

platform-monitoring:
  enabled: true
  grafana:
    adminPassword: "..."
    # ... rest of Grafana config

platform-vault:
  enabled: true
  vault:
    server:
      # ... Vault config

platform-external-secrets:
  enabled: true
  externalSecrets:
    # ... ESO config

# ... and so on
```

### Step 2: Replace multiple Applications with one

**Delete:**
- `argocd/applications/argocd.yaml`
- `argocd/applications/monitoring.yaml`
- `argocd/applications/vault.yaml`
- `argocd/applications/external-secrets.yaml`
- `argocd/applications/cert-manager.yaml` (if exists)
- `argocd/applications/traefik.yaml` (if exists)
- `argocd/applications/security.yaml` (if exists)

**Create:** `argocd/applications/platform.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: "oci://ghcr.io/kevindebenedetti/charts"
    chart: platform-deployment
    targetRevision: "1.0.0"
    helm:
      releaseName: platform
      valuesObject:
        # Load from infra/platform/deployment/values.yaml
        $patch: merge
        # Will be specified via ArgoCD UI or GitOps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Or use a plugin to load `platform/deployment/values.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: "https://github.com/KevinDeBenedetti/infra"
    path: "argocd/applications"
    plugin:
      name: helm
      env:
        - name: HELM_RELEASENAME
          value: platform
        - name: HELM_VALUES_FILE
          value: "../../platform/deployment/values.yaml"
  # ... rest of spec
```

### Step 3: Update CI/CD

Update `task` or GitHub Actions to validate the wrapper chart:

```bash
# Validate chart
helm lint k3s-lab/charts/platform-deployment

# Check dependencies
helm dependency list k3s-lab/charts/platform-deployment

# Verify all subcharts are available
helm dependency verify k3s-lab/charts/platform-deployment
```

### Step 4: Move values

Move per-component values to `platform/deployment/values.yaml`:

```
Before:
infra/platform/
├─ argocd/values.yaml          → Move to platform/deployment/values.yaml
├─ monitoring/values.yaml      → Move to platform/deployment/values.yaml
├─ vault/values.yaml           → Move to platform/deployment/values.yaml
├─ external-secrets/values.yaml → Move to platform/deployment/values.yaml
└─ traefik/values.yaml         → Move to platform/deployment/values.yaml

After:
infra/platform/
└─ deployment/
   └─ values.yaml              ← Single file with all overrides
```

## Validation Checklist

- [ ] `helm dependency update k3s-lab/charts/platform-deployment` succeeds
- [ ] `helm lint` passes
- [ ] `helm template` generates valid YAML
- [ ] All subcharts versions in Chart.yaml match cluster.env
- [ ] `infra/platform/deployment/values.yaml` contains all cluster-specific config
- [ ] Old per-component values files deleted
- [ ] Single `argocd/applications/platform.yaml` created
- [ ] Old per-component Applications deleted
- [ ] ArgoCD syncs without errors
- [ ] All pods are running
- [ ] `helm list` shows `platform` release

## Troubleshooting

### Chart dependency mismatch

```bash
# Check which versions are in Chart.yaml
helm dependency list k3s-lab/charts/platform-deployment

# Update if stale
helm dependency update k3s-lab/charts/platform-deployment
```

### Subchart values not applied

Check that values are nested correctly:

```yaml
# ✓ CORRECT
platform-argocd:
  argo-cd:
    configs:
      cm:
        url: https://...

# ✗ WRONG
argo-cd:
  configs:
    cm:
      url: https://...
```

### Some subcharts not deploying

Check if they're enabled:

```yaml
platform-vault:
  enabled: true  # ← Make sure this is true
  vault:
    # ... config
```

### Rollback to previous version

```bash
# List releases
helm history platform-deployment

# Rollback to previous revision
helm rollback platform-deployment 1
```

## Migration Timeline

**Phase 1 (immediately):**
- Create `charts/platform-deployment/Chart.yaml`
- Document the change

**Phase 2 (next sprint):**
- Create `infra/platform/deployment/values.yaml`
- Create `argocd/applications/platform.yaml`
- Test in dev/staging

**Phase 3 (when ready):**
- Backup current state
- Delete old Applications
- Deploy via platform.yaml
- Verify all services running

**Phase 4 (cleanup):**
- Delete old per-component values files
- Remove per-component Applications
- Update documentation

## See Also

- [Helm Dependency Management](https://helm.sh/docs/helm/helm_dependency/)
- [Helm Umbrella Charts](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)
- [ArgoCD Helm Integration](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
