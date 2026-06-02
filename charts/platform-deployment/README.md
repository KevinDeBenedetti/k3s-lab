# platform-deployment

Umbrella Helm chart combining all k3s-lab platform components into a single, cohesive deployment.

## Overview

This chart aggregates the following platform components as dependencies:

- **platform-argocd** (0.9.2) — GitOps via ArgoCD
- **platform-monitoring** (0.9.1) — Observability (Grafana, Prometheus, Loki)
- **platform-external-secrets** (0.9.1) — Vault integration via External Secrets Operator
- **platform-vault** (0.9.1) — Secret management
- **platform-cert-manager** (0.8.0) — TLS/ACME certificate management
- **platform-traefik** (0.8.0) — Ingress controller
- **platform-security** (0.8.0) — Pod security + network policies

Each subchart can be enabled/disabled independently and customized via values.

## Installation

### Via Helm (direct)

```bash
# Add GHCR registry (if first time)
helm registry login ghcr.io

# Pull and install
helm install platform-deployment \
  oci://ghcr.io/kevindebenedetti/charts/platform-deployment \
  --version 1.0.0 \
  -f values.yaml \
  -n argocd
```

### Via ArgoCD Application (recommended)

Create `argocd/applications/platform.yaml`:

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
      values: |
        platform-argocd:
          enabled: true
          # ... ArgoCD config
        platform-monitoring:
          enabled: true
          # ... Monitoring config
        # ... more subcharts
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Configuration

### Enable/Disable Subcharts

By default, all subcharts are enabled. To disable one:

```yaml
platform-vault:
  enabled: false  # Skip Vault deployment
```

### Subchart Configuration

All values are passed through to subcharts. Nest configuration under each subchart key:

```yaml
platform-argocd:
  enabled: true
  argo-cd:                    # ← Passed to platform-argocd chart
    global:
      domain: argocd.example.com
    configs:
      cm:
        url: https://argocd.example.com

platform-monitoring:
  enabled: true
  grafana:                    # ← Passed to platform-monitoring chart
    persistence:
      enabled: true
      size: 10Gi
```

See individual chart `values.yaml` for available options:
- `oci://ghcr.io/kevindebenedetti/charts/platform-argocd`
- `oci://ghcr.io/kevindebenedetti/charts/platform-monitoring`
- ... and so on

## Examples

### Minimal (all defaults)

```yaml
# values.yaml
# All subcharts enabled with their defaults
```

### Production (customized)

```yaml
platform-argocd:
  enabled: true
  argo-cd:
    global:
      domain: argocd.prod.example.com
    controller:
      resources:
        limits:
          memory: 2Gi
        requests:
          cpu: 100m
          memory: 512Mi

platform-monitoring:
  enabled: true
  grafana:
    admin:
      existingSecret: grafana-admin-secret
    persistence:
      enabled: true
      size: 50Gi

platform-vault:
  enabled: true
  vault:
    server:
      replicas: 3  # HA for production

platform-traefik:
  enabled: true
  traefik:
    deployment:
      replicas: 2
```

## Dependency Management

Update dependencies (fetches all platform-* charts):

```bash
helm dependency update
```

Check dependency status:

```bash
helm dependency list
```

## Verification

After installation:

```bash
# Check Helm release
helm list -n argocd | grep platform

# Check ArgoCD Application
kubectl get app platform -n argocd

# Check pods
kubectl get pods --all-namespaces | grep -E '(argocd|monitoring|vault|traefik|cert-manager)'

# Check Helm chart versions
helm show values oci://ghcr.io/kevindebenedetti/charts/platform-deployment --version 1.0.0
```

## Troubleshooting

### "Chart not found"

```bash
helm search repo platform-deployment
# If not found:
helm repo update
```

### "Dependency not found"

One of the platform-* subcharts is missing:

```bash
helm dependency update
helm dependency verify
```

### "Values not being applied"

Ensure proper nesting:

```yaml
# ✓ Correct
platform-argocd:
  argo-cd:
    global:
      domain: example.com

# ✗ Wrong (missing platform-argocd wrapper)
argo-cd:
  global:
    domain: example.com
```

### Subchart not deploying

Check if enabled:

```yaml
platform-vault:
  enabled: true  # ← Must be true
  vault:
    # ... config
```

## Upgrades

### Upgrade all subcharts

```bash
# Update dependencies
helm dependency update

# Upgrade Helm release
helm upgrade platform-deployment oci://ghcr.io/kevindebenedetti/charts/platform-deployment \
  --version 1.0.1 \
  -f values.yaml
```

### Upgrade single subchart

Edit values to change version of one platform-* chart:

```yaml
platform-argocd:
  # This version comes from Chart.yaml dependency version
  # Edit Chart.yaml to change
```

Actually, to update a subchart version, edit the wrapper's `Chart.yaml`:

```yaml
dependencies:
  - name: platform-argocd
    version: "0.9.3"  # ← Change this
```

Then run:

```bash
helm dependency update
helm upgrade platform-deployment ...
```

## Rollback

```bash
# Check release history
helm history platform-deployment -n argocd

# Rollback to previous revision
helm rollback platform-deployment 1 -n argocd
```

## See Also

- [Helm Umbrella Charts](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)
- [platform-argocd](../platform-argocd/README.md)
- [platform-monitoring](../platform-monitoring/README.md)
- [platform-vault](../platform-vault/README.md)
- [ArgoCD Helm Integration](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
