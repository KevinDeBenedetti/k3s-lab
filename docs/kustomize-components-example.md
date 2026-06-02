# Example — Refactoring `homepage` to use Kustomize Components

This guide walks through the **before** and **after** of adopting reusable
[Kustomize components](./kustomize-components.md) to remove duplicated YAML
boilerplate from an application's manifests, using the `homepage` app as a
worked example.

## Overview

|            | Files                                                                                                                                                   | Approx. lines              | Security context           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- | -------------------------- |
| **Before** | `deployment.yaml`, `service.yaml`, `ingress.yaml`, `middleware.yaml`, `configmap.yaml`, `serviceaccount.yaml`, `clusterrole.yaml`, `kustomization.yaml` | ~350                       | Repeated in every app      |
| **After**  | `kustomization.yaml`, `deployment.yaml`, `configmap.yaml`, `ingress-patch.yaml`, `deployment-patch.yaml`                                                | ~100 (+ shared components) | Defined once in `app-base` |

**Before**, `homepage` carried a full set of manifests with all the security
context, service account, networking and RBAC boilerplate inlined.

**After**, `homepage` references shared components and only keeps the
app-specific spec plus a couple of small patches.

## `kustomization.yaml`

### Before — lots of boilerplate

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: homepage
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - configmap.yaml
  - clusterrole.yaml
  - serviceaccount.yaml
  - middleware.yaml

commonLabels:
  app.kubernetes.io/name: homepage
commonAnnotations:
  description: "Dashboard UI"
```

### After — clean, components provide the boilerplate

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: homepage

# Use reusable components
components:
  - ../../../../vendor/k3s-lab/kubernetes/components/app-base
  - ../../../../vendor/k3s-lab/kubernetes/components/traefik-ingress
  - ../../../../vendor/k3s-lab/kubernetes/components/network-policies

# Only app-specific resources
resources:
  - deployment.yaml
  - configmap.yaml

# Customize component templates for this app
patches:
  - path: ingress-patch.yaml
  - path: deployment-patch.yaml

# Standard labels (app-base provides the managed-by label)
commonLabels:
  app.kubernetes.io/name: homepage
```

> [!NOTE]
> `patchesStrategicMerge` was deprecated in Kustomize v5.0.0. Use the `patches`
> field with `path:` instead — strategic merge semantics still apply, so
> existing patch files keep working. Run `kustomize edit fix` to migrate
> automatically.

## `deployment.yaml`

### Before — full boilerplate

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: homepage
  namespace: apps # OLD: namespace set here
  labels:
    app.kubernetes.io/name: homepage
spec:
  revisionHistoryLimit: 3
  replicas: 1
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: homepage
  template:
    metadata:
      labels:
        app.kubernetes.io/name: homepage
    spec:
      serviceAccountName: homepage
      automountServiceAccountToken: true
      dnsPolicy: ClusterFirst
      enableServiceLinks: true
      containers:
        - name: homepage
          image: "ghcr.io/gethomepage/homepage:v1.12.3@sha256:abc123..."
          imagePullPolicy: IfNotPresent
          securityContext: # ← boilerplate
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
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: MY_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          volumeMounts: # ← boilerplate (tmp/var-run)
            - name: tmp
              mountPath: /tmp
            - name: var-run
              mountPath: /var/run
          resources: # ← often identical across apps
            requests:
              cpu: "10m"
              memory: "32Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
      volumes:
        - name: tmp
          emptyDir: {}
        - name: var-run
          emptyDir: {}
```

### After — clean

Comments mark what is now provided by a component or a patch instead of being
declared inline.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: homepage
  # namespace: ← provided by kustomization.yaml
spec:
  revisionHistoryLimit: 3
  replicas: 1
  strategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: homepage
  template:
    metadata:
      labels:
        app.kubernetes.io/name: homepage
    spec:
      # serviceAccountName: ← patched by deployment-patch.yaml
      # automountServiceAccountToken: ← provided by app-base
      # dnsPolicy: ← provided by app-base
      # enableServiceLinks: ← provided by app-base
      # securityContext: ← provided by app-base component
      # volumes: ← patched by deployment-patch.yaml
      containers:
        - name: homepage
          image: "ghcr.io/gethomepage/homepage:v1.12.3@sha256:abc123..."
          # imagePullPolicy: ← provided by app-base
          # securityContext: ← provided by app-base
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: MY_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          # volumeMounts: ← patched by deployment-patch.yaml
          # resources: ← patched by deployment-patch.yaml
```

## `ingress-patch.yaml` — customize the domain

Patch the `IngressRoute` provided by the `traefik-ingress` component.

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app-https
spec:
  routes:
    - match: "Host(`homepage.kevindb.dev`)" # ← override domain
      kind: Rule
      services:
        - name: homepage # ← match service name
          port: 80
```

## `deployment-patch.yaml` — override resources and volumes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: homepage
spec:
  template:
    spec:
      serviceAccountName: homepage
      containers:
        - name: homepage
          runAsUser: 1000
          runAsGroup: 1000
          resources:
            requests:
              cpu: "10m"
              memory: "32Mi"
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

## Files that disappear

These files are no longer needed because the components provide them:

| File                  | Status  | Provided by                                  |
| --------------------- | ------- | -------------------------------------------- |
| `service.yaml`        | Deleted | `app-base`                                   |
| `ingress.yaml`        | Deleted | `traefik-ingress` (use `ingress-patch.yaml`) |
| `middleware.yaml`     | Deleted | `traefik-ingress`                            |
| `serviceaccount.yaml` | Deleted | `app-base`                                   |
| `clusterrole.yaml`    | Deleted | `network-policies` or base                   |
| `configmap.yaml`      | Kept    | App-specific                                 |

## Benefits summary

**Before**

- 8 files (`deployment`, `service`, `ingress`, `middleware`, `configmap`, `clusterrole`, `serviceaccount`, `kustomization`).
- ~350 lines of YAML.
- Boilerplate security context in every app.
- Updating the security policy means editing 8+ apps.

**After**

- 4 files (`deployment`, `configmap`, `kustomization`, plus 2 patches).
- ~100 lines of YAML (+ ~300 lines in components, reused by all apps).
- Security context defined once in `app-base`.
- Updating the security policy means editing 1 file (the `app-base` component).
- ~70% less duplicated YAML per app.
- Much easier to onboard new apps.
