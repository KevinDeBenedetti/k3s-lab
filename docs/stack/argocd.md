# ArgoCD — GitOps Continuous Delivery

[ArgoCD](https://argo-cd.readthedocs.io) is the GitOps controller for this cluster.
It watches your own config repo and applies any change to the cluster.

---

## What ArgoCD does here

| Responsibility      | Detail                                            |
| ------------------- | ------------------------------------------------- |
| Continuous delivery | Syncs cluster state to Git on every push          |
| Self-healing        | Reverts manual `kubectl` changes automatically    |
| Pruning             | Removes cluster resources deleted from Git        |
| Web UI              | Visual overview of all apps and their sync status |
| Webhook receiver    | Instant sync triggered by GitHub push events      |

---

## Architecture

```
GitHub (your config repo)
      │  push
      │  webhook → https://<ARGOCD_DOMAIN>/api/webhook
      ▼
ArgoCD (argocd namespace)
  ├── repo-server   ← clones the config repo via SSH deploy key
  ├── application-controller ← diffs desired vs actual state
  ├── server        ← UI + API (--insecure, Traefik handles TLS)
  └── redis         ← cache

      │  kubectl apply (server-side)
      ▼
Kubernetes (apps, monitoring, … namespaces)
```

---

## Installation

ArgoCD is bootstrapped with Helm from this repo:

```bash
task argocd:deploy
```

This installs `argo/argo-cd` chart at the version pinned in `ARGOCD_VERSION`
(default: `7.8.26`) with values from `platform/argocd/values.yaml`
(consuming repo override) or `charts/platform-argocd/values.yaml` (k3s-lab defaults).

### Key configuration choices

| Setting                 | Value    | Why                                                      |
| ----------------------- | -------- | -------------------------------------------------------- |
| `server.insecure: true` | enabled  | Traefik terminates TLS; ArgoCD runs plain HTTP behind it |
| `dex.enabled: false`    | disabled | Single-user setup; no SSO needed                         |
| `redis` in-cluster      | enabled  | Required for app state cache                             |

---

## Access

| Method           | URL / Command                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| Web UI           | `https://<ARGOCD_DOMAIN>`                                                                              |
| Initial password | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |
| CLI login        | `argocd login <ARGOCD_DOMAIN> --username admin`                                                        |

> Change the default password after first login.

---

## Repo registration

ArgoCD accesses your private config repo via an SSH deploy key stored as a
Kubernetes Secret:

```bash
task argocd:add-repo ARGOCD_REPO_URL=git@github.com:<you>/<config-repo>.git \
  GITHUB_DEPLOY_KEY=~/.ssh/argocd_deploy_key
```

This creates (or updates) the repository secret in the `argocd`
namespace with label `argocd.argoproj.io/secret-type=repository`.

Add the public key to the repo as a **read-only** deploy key
(GitHub → Settings → Deploy keys).

> The `repoURL` in every ArgoCD `Application` manifest **must use the SSH format**
> (`git@github.com:<you>/<config-repo>.git`) to match this secret.
> Using `https://` will result in `authentication required` errors.

---

## Applications

ArgoCD Applications are managed via **ApplicationSets** that auto-discover
app directories. A typical layout for your config repo:

```
<config-repo>/
  argocd/
    projects/         ← AppProjects (RBAC boundaries)
    applicationsets/  ← Git directory generators (auto-discover apps/ and platform/)
    applications/     ← Standalone Applications (security, secrets)
  apps/               ← App manifests (one dir per app)
  platform/           ← Platform component overrides
```

ApplicationSets are applied once during bootstrap:

```bash
kubectl --context homelab apply -f argocd/projects/
kubectl --context homelab apply -f argocd/applicationsets/
kubectl --context homelab apply -f argocd/applications/
```

After that, adding a new app is just `mkdir apps/myapp/ && git push`.

### Example ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: git@github.com:<you>/<config-repo>.git
        revision: main
        directories:
          - path: apps/*
  template:
    metadata:
      name: "{{path.basename}}"
    spec:
      project: apps
      source:
        repoURL: git@github.com:<you>/<config-repo>.git
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

---

## GitHub Webhook

For instant sync (instead of polling every 3 minutes), configure a webhook:

| Field        | Value                                 |
| ------------ | ------------------------------------- |
| URL          | `https://<ARGOCD_DOMAIN>/api/webhook` |
| Content type | `application/json`                    |
| Events       | **Just the push event**               |
| Secret       | *(leave empty)*                       |

Configure it in the config repo under GitHub → Settings → Webhooks.

---

## Traefik routing

ArgoCD requires two IngressRoute routes because the CLI uses gRPC (HTTP/2):

```yaml
routes:
  # UI + REST API
  - match: Host(`<ARGOCD_DOMAIN>`)
    priority: 10
    services:
      - name: argocd-server
        port: 80

  # gRPC (argocd CLI)
  - match: Host(`<ARGOCD_DOMAIN>`) && Header(`Content-Type`, `application/grpc`)
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
kubectl --context homelab get applications -n argocd

# Force sync an app immediately
kubectl --context homelab patch application whoami -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# See sync error details
kubectl --context homelab describe application whoami -n argocd

# Tail ArgoCD server logs
kubectl --context homelab logs -n argocd deploy/argocd-server -f

# List registered repos
kubectl --context homelab get secrets -n argocd \
  -l argocd.argoproj.io/secret-type=repository
```

---

## See also

- [Traefik](./traefik.md) — IngressRoute reference
- [ArgoCD official docs](https://argo-cd.readthedocs.io)
