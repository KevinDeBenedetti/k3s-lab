# Deploying an App

This guide explains how to add a new application to your cluster and have it
automatically deployed by ArgoCD whenever you push to your `infra` repo.

---

## How it works (GitOps loop)

```
You push to infra/       GitHub fires webhook      ArgoCD syncs cluster
kubernetes/apps/myapp/ ──────────────────────────▶ argocd.kevindb.dev ──▶ k8s applies
```

1. Create app manifests in `infra/kubernetes/apps/<appname>/`
2. Create an ArgoCD Application in `infra/kubernetes/argocd/apps/<appname>.yaml`
3. Apply the ArgoCD Application once — from then on, **git push = deploy**

---

## Step 1 — Create your app manifests

Create a directory in your `infra` repo:

```
infra/
  kubernetes/
    apps/
      myapp/
        deployment.yaml
        service.yaml
        ingress.yaml
```

### deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myimage:latest
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
```

### service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: apps
spec:
  selector:
    app: myapp
  ports:
    - port: 80
      targetPort: 80
```

### ingress.yaml

```yaml
# TLS certificate (cert-manager → Let's Encrypt)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: apps
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - myapp.kevindb.dev
---
# Traefik IngressRoute
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: apps
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

> Replace `myapp.kevindb.dev` with your actual subdomain.

---

## Step 2 — Add a DNS record

Point your subdomain to the cluster's external IP (same IP as all other apps):

```bash
kubectl --context k3s-infra get svc -n ingress traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Add an `A` record in your DNS provider:

| Type | Name | Value |
|------|------|-------|
| A | `myapp` | `<traefik-ip>` |

---

## Step 3 — Create the ArgoCD Application

Create `infra/kubernetes/argocd/apps/myapp.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: git@github.com:KevinDeBenedetti/infra.git
    targetRevision: main
    path: kubernetes/apps/myapp

  destination:
    server: https://kubernetes.default.svc
    namespace: apps

  syncPolicy:
    automated:
      prune: true      # remove resources deleted from Git
      selfHeal: true   # revert manual kubectl changes
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

> `repoURL` must use the SSH format (`git@github.com:...`) to match the deploy key secret.

---

## Step 4 — Apply and push

```bash
# Register the ArgoCD Application in the cluster
kubectl --context k3s-infra apply -f kubernetes/argocd/apps/myapp.yaml

# Commit and push all manifests
git add kubernetes/apps/myapp/ kubernetes/argocd/apps/myapp.yaml
git commit -m "feat: add myapp"
git push
```

ArgoCD detects the push (via webhook) and syncs within seconds.

---

## Step 5 — Verify

```bash
# Check ArgoCD sync status
kubectl --context k3s-infra get application myapp -n argocd

# Check pods
kubectl --context k3s-infra get pods -n apps

# Check certificate
kubectl --context k3s-infra get certificate myapp-tls -n apps
```

Or open the ArgoCD UI: **https://argocd.kevindb.dev**

---

## Day-to-day: updating an app

After initial setup, deploying a change is just:

```bash
# Edit any manifest — e.g. bump the image tag
vim infra/kubernetes/apps/myapp/deployment.yaml

git add -A && git commit -m "chore: bump myapp to v1.2.3" && git push
```

ArgoCD auto-syncs. No `kubectl apply` needed.

---

## Removing an app

```bash
# Delete the ArgoCD Application (triggers prune → removes cluster resources)
kubectl --context k3s-infra delete application myapp -n argocd

# Remove the manifests from git
rm -rf kubernetes/apps/myapp/ kubernetes/argocd/apps/myapp.yaml
git add -A && git commit -m "chore: remove myapp" && git push
```

---

## Checklist

- [ ] DNS `A` record pointing to Traefik IP
- [ ] `kubernetes/apps/myapp/` directory with deployment, service, ingress
- [ ] `kubernetes/argocd/apps/myapp.yaml` with SSH `repoURL`
- [ ] `kubectl apply -f kubernetes/argocd/apps/myapp.yaml` (once)
- [ ] `git push` — ArgoCD handles the rest

---

## See also

- [ArgoCD stack reference](../stack/argocd.md)
- [Traefik IngressRoute reference](../stack/traefik.md)
- [cert-manager TLS reference](../stack/cert-manager.md)
- [whoami example app](https://github.com/KevinDeBenedetti/infra/tree/main/kubernetes/apps/whoami) — working reference implementation
