# =============================================================================
# Example: Refactoring homepage to use Kustomize Components
#
# This shows the BEFORE and AFTER of using components to reduce duplication.
#
# BEFORE: homepage had:
#   - deployment.yaml (with full security context boilerplate)
#   - service.yaml (standard template)
#   - ingress.yaml (Traefik IngressRoute)
#   - middleware.yaml (middleware chain)
#   - configmap.yaml (app config)
#   - serviceaccount.yaml (service account)
#   - clusterrole.yaml (RBAC)
#   - kustomization.yaml (listing all resources)
#
# AFTER: homepage uses components:
#   - kustomization.yaml (references components)
#   - deployment.yaml (ONLY app-specific spec)
#   - configmap.yaml (app config)
#   - ingress-patch.yaml (domain override)
#   - deployment-patch.yaml (resources + security override)
#
# =============================================================================

# ── BEFORE: homepage/kustomization.yaml ────────────────────────────────────

# OLD (lots of boilerplate):
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

---

# ── AFTER: homepage/kustomization.yaml ─────────────────────────────────────

# NEW (clean, components provide boilerplate):
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
patchesStrategicMerge:
  - ingress-patch.yaml
  - deployment-patch.yaml

# Standard labels (app-base provides managed-by label)
commonLabels:
  app.kubernetes.io/name: homepage

---

# ── homepage/deployment.yaml (BEFORE - FULL BOILERPLATE) ───────────────────

apiVersion: apps/v1
kind: Deployment
metadata:
  name: homepage
  namespace: apps  # OLD: namespace here
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
          securityContext:                 # ← BOILERPLATE
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
          volumeMounts:           # ← BOILERPLATE (tmp/var-run)
            - name: tmp
              mountPath: /tmp
            - name: var-run
              mountPath: /var/run
          resources:             # ← Often identical
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

---

# ── homepage/deployment.yaml (AFTER - CLEAN) ───────────────────────────────

apiVersion: apps/v1
kind: Deployment
metadata:
  name: homepage
  # namespace: ← Provided by kustomization.yaml
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
      # serviceAccountName: ← Patched by kustomization.yaml
      # automountServiceAccountToken: ← Provided by app-base
      # dnsPolicy: ← Provided by app-base
      # enableServiceLinks: ← Provided by app-base
      # securityContext: ← Provided by app-base component
      # volumes: ← Patched by deployment-patch.yaml
      containers:
        - name: homepage
          image: "ghcr.io/gethomepage/homepage:v1.12.3@sha256:abc123..."
          # imagePullPolicy: ← Provided by app-base
          # securityContext: ← Provided by app-base
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: MY_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          # volumeMounts: ← Patched by deployment-patch.yaml
          # resources: ← Patched by deployment-patch.yaml

---

# ── homepage/ingress-patch.yaml (CUSTOMIZE DOMAIN) ────────────────────────

# Patch the IngressRoute from traefik-ingress component
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: app-https
spec:
  routes:
    - match: "Host(`homepage.kevindb.dev`)"  # ← Override domain
      kind: Rule
      services:
        - name: homepage  # ← Match service name
          port: 80

---

# ── homepage/deployment-patch.yaml (OVERRIDE RESOURCES + VOLUMES) ──────────

# Patch to override resources and add volumes
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

---

# ── Files that DISAPPEAR (provided by components) ────────────────────────

# These are no longer needed because:

# service.yaml → DELETED (provided by app-base)
# ingress.yaml → DELETED (provided by traefik-ingress; use ingress-patch.yaml)
# middleware.yaml → DELETED (provided by traefik-ingress)
# serviceaccount.yaml → DELETED (provided by app-base)
# clusterrole.yaml → DELETED (provided by network-policies or base)
# configmap.yaml → KEPT (app-specific)

---

# ── BENEFITS SUMMARY ───────────────────────────────────────────────────────

# BEFORE:
# - 8 files (deployment, service, ingress, middleware, configmap, clusterrole, serviceaccount, kustomization)
# - ~350 lines of YAML
# - Boilerplate security context in EVERY app
# - Updating security policy = edit 8+ apps

# AFTER:
# - 4 files (deployment, configmap, kustomization, 2 patches)
# - ~100 lines of YAML (+ 300 lines in components, reused by ALL apps)
# - Security context defined ONCE in app-base
# - Updating security policy = edit 1 file (app-base component)
# - 70% less duplicated YAML per app
# - 100% easier to onboard new apps
