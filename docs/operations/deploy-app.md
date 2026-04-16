# Deploying an App

This guide explains how to add a new application to your cluster and have it
automatically deployed by ArgoCD whenever you push to your `infra` repo.

---

## How it works (GitOps loop)

```
You push to infra/       GitHub fires webhook      ArgoCD syncs cluster
apps/myapp/ ─────────────────────────────────────▶ argocd.example.com ──▶ k8s applies
```

1. Create app manifests in `infra/apps/<appname>/`
2. ArgoCD ApplicationSets auto-discover the new app directory
3. **git push = deploy** — no manual `kubectl apply` needed

---

## Step 1 — Create your app manifests

Create a directory in your `infra` repo:

```
infra/
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
# TLS certificate (cert-manager → Let's Encrypt via DNS-01/Cloudflare)
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
  annotations:
    # external-dns: automatically creates/updates the A record in Cloudflare
    external-dns.alpha.kubernetes.io/hostname: myapp.kevindb.dev
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

## Step 2 — ArgoCD auto-discovers via ApplicationSets

ArgoCD uses **ApplicationSets** with a Git directory generator that automatically
creates an Application for every subdirectory in `apps/`. No manual Application
manifest is needed.

The ApplicationSet is defined in `infra/argocd/applicationsets/apps.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: git@github.com:KevinDeBenedetti/infra.git
        revision: main
        directories:
          - path: apps/*
  template:
    metadata:
      name: "{{path.basename}}"
    spec:
      project: apps
      source:
        repoURL: git@github.com:KevinDeBenedetti/infra.git
        targetRevision: main
        path: "{{path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: apps
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

> Add a new directory under `apps/` and push — ArgoCD handles the rest.

---

## Step 3 — Push

```bash
# Commit and push all manifests
git add apps/myapp/
git commit -m "feat: add myapp"
git push
```

ArgoCD detects the push (via webhook) and syncs within seconds.

---

## Step 4 — Verify

```bash
# Check DNS was created in Cloudflare (within ~1 min)
dig myapp.kevindb.dev +short

# Check ArgoCD sync status
kubectl --context k3s-infra get application myapp -n argocd

# Check pods
kubectl --context k3s-infra get pods -n apps

# Check certificate (DNS-01 — works even before DNS resolves)
kubectl --context k3s-infra get certificate myapp-tls -n apps

# Check external-dns logs
make external-dns-logs
```

Or open the ArgoCD UI: **https://argocd.kevindb.dev**

---

## Day-to-day: updating an app

After initial setup, deploying a change is just:

```bash
# Edit any manifest — e.g. bump the image tag
vim infra/apps/myapp/deployment.yaml

git add -A && git commit -m "chore: bump myapp to v1.2.3" && git push
```

ArgoCD auto-syncs. No `kubectl apply` needed.

---

## Removing an app

```bash
# Remove the app directory from git — ArgoCD prunes cluster resources
rm -rf apps/myapp/
git add -A && git commit -m "chore: remove myapp" && git push
```

---

## Checklist

- [ ] `external-dns.alpha.kubernetes.io/hostname` annotation on IngressRoute (DNS A record auto-created)
- [ ] `apps/myapp/` directory with deployment, service, ingress
- [ ] `git push` — ApplicationSets auto-discover and ArgoCD handles the rest

---

## See also

- [ArgoCD stack reference](../stack/argocd.md)
- [Traefik IngressRoute reference](../stack/traefik.md)
- [cert-manager TLS reference](../stack/cert-manager.md)
- [whoami example app](https://github.com/KevinDeBenedetti/infra/tree/main/apps/whoami) — working reference implementation
