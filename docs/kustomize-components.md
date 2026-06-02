# Kustomize Components — Usage Guide

This guide explains how to use the reusable Kustomize components from k3s-lab to reduce duplication in app manifests.

## Components Available

| Component          | Purpose                                                | Files Provided                                                                       |
| ------------------ | ------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `app-base`         | Standard pod security, labels, Service, ServiceAccount | `kustomization.yaml`, `deployment-patch.yaml`, `service.yaml`, `serviceaccount.yaml` |
| `traefik-ingress`  | IngressRoute + Middleware templates                    | `ingressroute.yaml`, `middleware.yaml`                                               |
| `network-policies` | Default-deny + allow from ingress controller + DNS     | `network-deny-all.yaml`, `network-allow-ingress.yaml`, `network-allow-dns.yaml`      |
| `vault-auth`       | ServiceAccount + RBAC for Vault authentication         | `serviceaccount-vault.yaml`, `role.yaml`, `rolebinding.yaml`                         |

## Quick Start: Create a New App

### 1. Create app directory

```bash
mkdir -p infra/apps/myapp
cd infra/apps/myapp
```

### 2. Create `kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: myapp

# Use components to get standard configs
components:
  - ../../../../vendor/k3s-lab/kubernetes/components/app-base
  - ../../../../vendor/k3s-lab/kubernetes/components/traefik-ingress
  - ../../../../vendor/k3s-lab/kubernetes/components/network-policies
  - ../../../../vendor/k3s-lab/kubernetes/components/vault-auth  # if using Vault

# Your app-specific resources
resources:
  - deployment.yaml
  - configmap.yaml                # if needed

# Customize component templates for your app
patchesStrategicMerge:
  - ingress-patch.yaml            # customize domain, paths
  - deployment-patch.yaml         # override security context, resources

# Set standard labels
commonLabels:
  app.kubernetes.io/name: myapp
  app.kubernetes.io/version: "1.0.0"
```

### 3. Create app-specific files

**`deployment.yaml`** — Your deployment (without security boilerplate):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: myapp
  template:
    metadata:
      labels:
        app.kubernetes.io/name: myapp
    spec:
      serviceAccountName: myapp    # or: vault-auth if using Vault
      containers:
        - name: myapp
          image: "ghcr.io/myorg/myapp:v1.0.0@sha256:abc123..."
          ports:
            - name: http
              containerPort: 8080
          # Note: securityContext is provided by app-base component
```

**`ingress-patch.yaml`** — Customize the Traefik IngressRoute:

```yaml
# Patch to override domain and paths
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app-https
spec:
  routes:
    - match: "Host(`myapp.kevindb.dev`)"
      kind: Rule
      services:
        - name: myapp
          port: 80
```

**`deployment-patch.yaml`** — Override security context / resources per-app:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: myapp  # must match container name in deployment.yaml
          runAsUser: 1000
          runAsGroup: 1000
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: var-run
              mountPath: /var/run
      volumes:
        - name: tmp
          emptyDir: {}
        - name: var-run
          emptyDir: {}
```

**`configmap.yaml`** (if needed):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
  namespace: myapp
data:
  config.yaml: |
    setting1: value1
```

### 4. Validate

```bash
kustomize build .
```

## Real-World Examples

### Minimal App (Dashboard-style)

```yaml
# infra/apps/homepage/kustomization.yaml
components:
  - ../../../../vendor/k3s-lab/kubernetes/components/app-base
  - ../../../../vendor/k3s-lab/kubernetes/components/traefik-ingress
  - ../../../../vendor/k3s-lab/kubernetes/components/network-policies

resources:
  - deployment.yaml
  - configmap.yaml

patchesStrategicMerge:
  - ingress-patch.yaml

commonLabels:
  app.kubernetes.io/name: homepage
```

### App with Vault Secrets

```yaml
# infra/apps/reactive-resume/kustomization.yaml
components:
  - ../../../../vendor/k3s-lab/kubernetes/components/app-base
  - ../../../../vendor/k3s-lab/kubernetes/components/traefik-ingress
  - ../../../../vendor/k3s-lab/kubernetes/components/network-policies
  - ../../../../vendor/k3s-lab/kubernetes/components/vault-auth  # ← Extra: for Vault auth

resources:
  - deployment.yaml
  - configmap.yaml
  - externalsecret.yaml             # ← Extra: fetch secrets from Vault

patchesStrategicMerge:
  - ingress-patch.yaml
  - deployment-patch.yaml           # Override for app-specific resources

commonLabels:
  app.kubernetes.io/name: reactive-resume
```

## Reducing Duplication

### Before (duplicated in each app):

```yaml
# Every app had to define this in its deployment
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  seccompProfile:
    type: RuntimeDefault

# Every app had its own Service
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 8080

# Every app had its own IngressRoute
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp-https
spec:
  entryPoints:
    - websecure
  routes:
    - match: "Host(`myapp.kevindb.dev`)"
      ...

# Every app had its own NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

### After (components provide all of this):

```yaml
# kustomization.yaml—just reference components
components:
  - ../../../../vendor/k3s-lab/kubernetes/components/app-base
  - ../../../../vendor/k3s-lab/kubernetes/components/traefik-ingress
  - ../../../../vendor/k3s-lab/kubernetes/components/network-policies

# App-specific overrides only
resources:
  - deployment.yaml      # Just the container spec
  - configmap.yaml       # App config
patchesStrategicMerge:
  - ingress-patch.yaml   # Just override domain/paths
```

**Result: 80% less manifest duplication** ✨

## Benefits

| Feature                     | Before                   | After                          |
| --------------------------- | ------------------------ | ------------------------------ |
| Security context duplicated | Every app                | Defined once in `app-base`     |
| Service template            | Every app                | Provided by `app-base`         |
| IngressRoute template       | Every app                | Provided by `traefik-ingress`  |
| NetworkPolicy               | Every app                | Provided by `network-policies` |
| Updating security policy    | Edit 8 apps              | Edit 1 component               |
| Onboarding new app          | Copy-paste 100s of lines | Reference 4 components         |

## Troubleshooting

### Q: How do I use a component?

Add to `components:` in your `kustomization.yaml`:

```yaml
components:
  - ../../../../vendor/k3s-lab/kubernetes/components/app-base
```

The path is relative from your app directory to k3s-lab.

### Q: How do I customize a component?

Use `patchesStrategicMerge` or `patchesJson6902` to override specific fields:

```yaml
patchesStrategicMerge:
  - ingress-patch.yaml              # Override IngressRoute domain
  - deployment-patch.yaml           # Override resources/security context
```

### Q: Can I skip a component?

Yes! Just don't include it in `components:`. For example:

```yaml
components:
  - ../../../../vendor/k3s-lab/kubernetes/components/app-base
  # Skip traefik-ingress if using different ingress controller
  - ../../../../vendor/k3s-lab/kubernetes/components/network-policies
```

### Q: How do I add a new app-wide best practice?

1. Create a new component in `k3s-lab/kubernetes/components/`
2. Add it to all apps via `components:` in their `kustomization.yaml`
3. Test with `kustomize build .`

No need to edit 8 individual apps! 🎉

## See Also

- [Kustomize Components Documentation](https://kubernetes-sigs.github.io/kustomize/guides/components/)
- [`vendor/k3s-lab/kubernetes/components/`](https://github.com/KevinDeBenedetti/k3s-lab/tree/main/kubernetes/components)
- [DRY Principle in Kubernetes](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself)
