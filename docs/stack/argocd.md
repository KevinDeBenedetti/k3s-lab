# ArgoCD — GitOps Continuous Delivery

[ArgoCD](https://argo-cd.readthedocs.io) is the GitOps controller for this cluster.
It watches your `infra` repo and automatically applies any changes to Kubernetes.

---

## What ArgoCD does here

| Responsibility | Detail |
|---|---|
| Continuous delivery | Syncs cluster state to Git on every push |
| Self-healing | Reverts manual `kubectl` changes automatically |
| Pruning | Removes cluster resources deleted from Git |
| Web UI | Visual overview of all apps and their sync status |
| Webhook receiver | Instant sync triggered by GitHub push events |

---

## Architecture

```
GitHub (infra repo)
      │  push
      │  webhook → https://argocd.kevindb.dev/api/webhook
      ▼
ArgoCD (argocd namespace)
  ├── repo-server   ← clones infra via SSH deploy key
  ├── application-controller ← diffs desired vs actual state
  ├── server        ← UI + API (--insecure, Traefik handles TLS)
  └── redis         ← cache

      │  kubectl apply (server-side)
      ▼
Kubernetes (apps, monitoring, … namespaces)
```

---

## Installation

ArgoCD is deployed via Helm from `infra/`:

```bash
make deploy-argocd
```

This installs `argo/argo-cd` chart at the version pinned in `ARGOCD_VERSION`
(default: `7.8.26`) with values from `kubernetes/argocd/helm-values.yaml`.

### Key configuration choices

| Setting | Value | Why |
|---|---|---|
| `server.insecure: true` | enabled | Traefik terminates TLS; ArgoCD runs plain HTTP behind it |
| `dex.enabled: false` | disabled | Single-user setup; no SSO needed |
| `redis` in-cluster | enabled | Required for app state cache |

---

## Access

| Method | URL / Command |
|---|---|
| Web UI | `https://argocd.kevindb.dev` |
| Initial password | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| CLI login | `argocd login argocd.kevindb.dev --username admin` |

> Change the default password after first login.

---

## Repo registration

ArgoCD accesses your private `infra` repo via an SSH deploy key stored as a
Kubernetes Secret:

```bash
make argocd-add-repo GITHUB_DEPLOY_KEY=~/.ssh/argocd_deploy_key
```

This creates (or updates) the `argocd-infra-repo` secret in the `argocd`
namespace with label `argocd.argoproj.io/secret-type=repository`.

The public key must be added to GitHub:
**`https://github.com/KevinDeBenedetti/infra/settings/keys`** (read-only).

> The `repoURL` in every ArgoCD `Application` manifest **must use the SSH format**
> (`git@github.com:KevinDeBenedetti/infra.git`) to match this secret.
> Using `https://` will result in `authentication required` errors.

---

## Applications

ArgoCD Applications live in `infra/kubernetes/argocd/apps/`.
Each file is an `Application` manifest declaring what to sync and where to deploy it.

Apply once to register an app with ArgoCD:

```bash
kubectl --context k3s-infra apply -f kubernetes/argocd/apps/myapp.yaml
```

After that, all updates come from `git push`.

### Example Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: whoami
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # prune on delete
spec:
  project: default
  source:
    repoURL: git@github.com:KevinDeBenedetti/infra.git
    targetRevision: main
    path: kubernetes/apps/whoami
  destination:
    server: https://kubernetes.default.svc
    namespace: apps
  syncPolicy:
    automated:
      prune: true      # delete resources removed from Git
      selfHeal: true   # revert manual kubectl changes
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

---

## GitHub Webhook

For instant sync (instead of polling every 3 minutes), configure a webhook:

| Field | Value |
|---|---|
| URL | `https://argocd.kevindb.dev/api/webhook` |
| Content type | `application/json` |
| Events | **Just the push event** |
| Secret | *(leave empty)* |

**`https://github.com/KevinDeBenedetti/infra/settings/hooks`**

---

## Traefik routing

ArgoCD requires two IngressRoute routes because the CLI uses gRPC (HTTP/2):

```yaml
routes:
  # UI + REST API
  - match: Host(`argocd.kevindb.dev`)
    priority: 10
    services:
      - name: argocd-server
        port: 80

  # gRPC (argocd CLI)
  - match: Host(`argocd.kevindb.dev`) && Header(`Content-Type`, `application/grpc`)
    priority: 11
    services:
      - name: argocd-server
        port: 80
        scheme: h2c   # plain HTTP/2 (no TLS — Traefik handles it)
```

The gRPC route has higher priority and is selected by the `Content-Type` header.

---

## Useful commands

```bash
# List all apps and their sync/health status
kubectl --context k3s-infra get applications -n argocd

# Force sync an app immediately
kubectl --context k3s-infra patch application whoami -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# See sync error details
kubectl --context k3s-infra describe application whoami -n argocd

# Tail ArgoCD server logs
kubectl --context k3s-infra logs -n argocd deploy/argocd-server -f

# List registered repos
kubectl --context k3s-infra get secrets -n argocd \
  -l argocd.argoproj.io/secret-type=repository
```

---

## See also

- [Deploy a new app](../operations/deploy-app.md) — step-by-step guide
- [Traefik](./traefik.md) — IngressRoute reference
- [ArgoCD official docs](https://argo-cd.readthedocs.io)
