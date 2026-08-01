# platform-deployment

Umbrella Helm chart combining all k3s-lab platform components into a single, cohesive deployment.

> [!IMPORTANT]
> **This chart is published, but nothing currently deploys it.** As of
> 2026-08-01 no ArgoCD `ApplicationSet` references it: the cluster deploys
> `platform-cert-manager`, `platform-external-secrets` and `platform-traefik`
> individually, pinned in `infra/argocd/applicationsets/platform.yaml`. The rest
> of this page therefore describes how the chart *would* be used, not how the
> cluster is currently run. Check before relying on it:
>
> ```bash
> grep -rn platform-deployment infra/argocd/applicationsets/
> ```

## Overview

This chart aggregates the following platform components as dependencies:

- **platform-argocd** — GitOps via ArgoCD
- **platform-monitoring** — Observability (Grafana, Prometheus, Loki)
- **platform-external-secrets** — Vault integration via External Secrets Operator
- **platform-vault** — Secret management
- **platform-cert-manager** — TLS/ACME certificate management
- **platform-traefik** — Ingress controller
- **platform-security** — Pod security + network policies

All seven are pinned to the same version, and [`Chart.yaml`](Chart.yaml) is the
only place that states it — the per-component version numbers that used to be
listed here drifted five releases behind before anyone noticed, so they are
deliberately not repeated. To see what this chart actually resolves:

```bash
helm dependency list charts/platform-deployment
```

The pins are advanced by hand once per release; the `umbrella-pins` CI job
fails when they fall behind what is published on GHCR.

Each subchart can be enabled/disabled independently and customized via values.

## Installation

### Via Helm (direct)

```bash
# Add GHCR registry (if first time)
helm registry login ghcr.io

# Pull and install
helm install platform-deployment \
  oci://ghcr.io/kevindebenedetti/charts/platform-deployment \
  --version 0.15.0 \
  -f values.yaml \
  -n argocd
```

### Via ArgoCD Application (the intended path, not currently in use)

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
    targetRevision: "0.15.0"
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
helm show values oci://ghcr.io/kevindebenedetti/charts/platform-deployment --version 0.15.0
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

Upgrading means moving to a newer **published version of this chart**. The
subchart versions are fixed when the release is cut — they are not something a
consumer selects:

```bash
helm upgrade platform-deployment \
  oci://ghcr.io/kevindebenedetti/charts/platform-deployment \
  --version <newer> \
  -f values.yaml
```

> [!NOTE]
> There is no way to upgrade a single subchart from the consumer side, and the
> previous version of this section was wrong to suggest otherwise. It advised
> running `helm dependency update` and editing the wrapper's `Chart.yaml` —
> neither of which a consumer of a published chart can do. Pulling the chart
> gives you the subchart versions that were pinned at release time, and nothing
> in `values.yaml` overrides them; the `enabled` flags turn a subchart off, they
> do not re-version it.
>
> To move one component independently, deploy it as its own chart rather than
> through this umbrella — which is exactly what the cluster does today for
> `cert-manager`, `external-secrets` and `traefik`.

Changing a subchart pin is a **producer** action in this repository: edit
[`Chart.yaml`](Chart.yaml), then cut a release so the new umbrella is published.
The `umbrella-pins` CI job fails when those pins fall behind what is published.

## Rollback

```bash
# Check release history
helm history platform-deployment -n argocd

# Rollback to previous revision
helm rollback platform-deployment 1 -n argocd
```

## See Also

- [Helm Umbrella Charts](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/)
- [platform-traefik](../platform-traefik/README.md) — ingress, and the proxy-version constraint
- [platform-vault-seeder](../platform-vault-seeder/README.md) — Vault seeding jobs
- [Helm umbrella guide](../../docs/helm-platform-deployment.md) — architecture and rationale
- [ArgoCD Helm Integration](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)

The subcharts without a README of their own are documented by their
`values.yaml`; `helm show values oci://ghcr.io/kevindebenedetti/charts/<chart>`
prints it for a published version.
