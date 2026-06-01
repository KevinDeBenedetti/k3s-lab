# Using k3s-lab with a Private Infra Repo

This guide explains how to consume k3s-lab as a shared toolkit from a **private
`infra` repository that holds only your configuration** — your IPs, domains,
secrets, chart overrides, and app manifests.

---

## Architecture overview

```
k3s-lab (public, reusable)        infra (private, configuration)
──────────────────────────────    ──────────────────────────────────────
  ansible/roles/                    terraform/        ← Hetzner VPS
  ansible/playbooks/                ansible/          ← inventory + group_vars
  taskfiles/   (Task fragments)     clusters/         ← cluster.env (non-secret)
  charts/      (Helm → OCI)         platform/         ← chart value overrides
  kubernetes/  (Kustomize bases)    apps/             ← your apps (GitOps)
  lib/         (shell libs)         argocd/           ← projects + ApplicationSets
  scripts/                          secrets/          ← ExternalSecrets
  tests/                            .env              ← your secrets (gitignored)
                                    vendor/k3s-lab/   ← git submodule (tag-pinned)
                                    Taskfile.yml      ← thin wrapper
```

**Rule:** every file you edit lives in `infra/`. You only touch `k3s-lab/` to
improve the toolkit itself.

| Repo      | What it holds                                                          | You edit?                   |
| --------- | ---------------------------------------------------------------------- | --------------------------- |
| `k3s-lab` | Ansible roles, Helm charts, Kustomize bases, taskfiles, libs, tests    | only to improve the toolkit |
| `infra`   | Terraform, inventory, `.env`, app manifests, overrides, `Taskfile.yml` | yes — always                |

k3s-lab is consumed two ways, each pinned:

| Artifact                          | Mechanism                          | Pinning          |
| --------------------------------- | ---------------------------------- | ---------------- |
| Helm charts (platform components) | OCI pull in ArgoCD ApplicationSets | semver per chart |
| Ansible roles, taskfiles, scripts | git submodule `vendor/k3s-lab`     | semver git tag   |

> The submodule is reproducible (the pinned commit appears in `git log`), works
> offline and in CI, and updates cleanly via a single command. There is **no**
> runtime `curl` fetch and **no** `.mk-cache/`.

---

## 1 — Bootstrap your infra repo

### 1.1 Add k3s-lab as a submodule

```bash
cd ~/dev/infra
git submodule add https://github.com/KevinDeBenedetti/k3s-lab vendor/k3s-lab
git -C vendor/k3s-lab checkout v1.0.0      # pin to a released tag
git add .gitmodules vendor/k3s-lab
git commit -m "chore: vendor k3s-lab v1.0.0"
```

Clone with submodules later via:

```bash
git clone --recurse-submodules <your-infra-repo>
# or, in an existing clone:
git submodule update --init --recursive
```

### 1.2 Create `Taskfile.yml`

The infra `Taskfile.yml` is a thin wrapper that `includes:` the taskfiles from the
vendored submodule and adds repo-specific targets (Terraform, bootstrap):

```yaml
version: '3'

dotenv:
  - .env
  - clusters/hetzner-prod/cluster.env

vars:
  ANSIBLE_DIR: ansible
  PLAYBOOK_DIR: '{{.ROOT_DIR}}/vendor/k3s-lab/ansible/playbooks'
  CLUSTER_ENV: '{{.ROOT_DIR}}/.env'

includes:
  provision:
    taskfile: ./vendor/k3s-lab/taskfiles/provision.yml
    vars:
      ANSIBLE_DIR: '{{.ANSIBLE_DIR}}'
      PLAYBOOK_DIR: '{{.PLAYBOOK_DIR}}'
      CLUSTER_ENV: '{{.CLUSTER_ENV}}'
  kubeconfig:
    taskfile: ./vendor/k3s-lab/taskfiles/kubeconfig.yml
  vault:
    taskfile: ./vendor/k3s-lab/taskfiles/vault.yml
  argocd:
    taskfile: ./vendor/k3s-lab/taskfiles/argocd.yml
  deploy:
    taskfile: ./vendor/k3s-lab/taskfiles/deploy.yml
  ssh:
    taskfile: ./vendor/k3s-lab/taskfiles/ssh.yml
  status:
    taskfile: ./vendor/k3s-lab/taskfiles/status.yml

tasks:
  default:
    desc: Show available tasks
    silent: true
    cmds: [task --list]
```

### 1.3 Create `.gitignore`

```gitignore
# Secrets — never committed
.env
```

### 1.4 Verify all tasks are available

```bash
task --list
```

You should see every namespaced task (`provision:*`, `vault:*`, `argocd:*`,
`deploy:*`, `ssh:*`, `status:*`, `kubeconfig:*`) alongside your own.

---

## 2 — Personalize your `.env`

`.env` is the only file that changes between users. It is **gitignored** and never
committed — keep an `.env.example` with placeholders instead.

```bash
# VPS nodes
SERVER_IP=1.2.3.4
AGENT_IP=5.6.7.8

# SSH
SSH_USER=kevin
SSH_KEY=~/.ssh/id_ed25519

# k3s + chart versions (pin to avoid surprise upgrades)
K3S_VERSION=v1.32.13+k3s1
TRAEFIK_CHART_VERSION=39.0.8
CERT_MANAGER_CHART_VERSION=1.20.2

# Domain + Let's Encrypt email
DOMAIN=example.com
EMAIL=you@example.com

# kubectl context name
KUBECONFIG_CONTEXT=k3s-infra
```

See the [Configuration reference](./configuration.md) for every variable and the
precedence rules (`Task var > .env > cluster.env > default`).

---

## 3 — Provision the cluster

Once `.env` is filled, all tasks are available from `infra/`:

```bash
# Full provisioning (Ansible): common + k3s server + agents + kubeconfig
task provision:inventory
task provision:site
```

Or step by step:

```bash
task provision:server      # common + k3s server + wireguard
task provision:agents      # join agent nodes
task kubeconfig:fetch      # merge ~/.kube/config
kubectl config use-context k3s-infra
task status:nodes          # verify nodes Ready
```

See [Getting Started](./getting-started.md) for the full walkthrough.

---

## 4 — Deploy the platform & your apps

The platform (Traefik, cert-manager, monitoring, security) is deployed
declaratively via Helm charts + ArgoCD. Bootstrap ArgoCD once, then it reconciles
everything from Git:

```bash
task argocd:deploy
task argocd:add-repo
task argocd:status
```

Create the secrets the charts consume:

```bash
task deploy:dashboard-secret
task deploy:grafana-secret
```

### Deploy your own apps

Create app manifests under `apps/` in your infra repo. The `apps` ApplicationSet
auto-discovers new directories:

```
infra/
  apps/
    myapp/
      deployment.yaml
      service.yaml
      ingress.yaml        ← Traefik IngressRoute
```

Just `git push` — ArgoCD handles the rest. See [Deploying an App](./operations/deploy-app.md).

---

## 5 — Update the toolkit

When k3s-lab ships improvements, bump the submodule pointer to a newer tag:

```bash
git -C vendor/k3s-lab fetch --tags
git -C vendor/k3s-lab checkout v1.1.0
git add vendor/k3s-lab
git commit -m "chore: bump k3s-lab to v1.1.0"
```

Review the diff, let CI validate, and merge. Your `.env`, `apps/`, and `platform/`
overrides are untouched. Renovate can open these bump PRs automatically.

| Bumped by a submodule update                         | Never touched           |
| ---------------------------------------------------- | ----------------------- |
| `vendor/k3s-lab/` — taskfiles, roles, scripts, bases | `Taskfile.yml`          |
| —                                                    | `.env`                  |
| —                                                    | `apps/` — your apps     |
| —                                                    | `platform/` — overrides |

---

## 6 — Update Helm chart versions

Platform charts are pulled via OCI and pinned in your ArgoCD ApplicationSets /
`platform/*` values. To upgrade, bump the pinned `targetRevision` and push:

```bash
git add -A && git commit -m "chore: bump chart versions" && git push
```

ArgoCD detects the change and syncs automatically. Renovate opens these PRs for you.

---

## 7 — Override a k3s-lab task

If you need to customize a shared task, define a task with the same name **in your
infra `Taskfile.yml`** — your local definition takes precedence over the included
one. Override sparingly: shared tasks are maintained and improved in k3s-lab.

---

## 8 — Full workflow summary

```bash
# ── First time ────────────────────────────────────────────────────────────────
git clone --recurse-submodules <your-infra-repo> && cd infra
cp .env.example .env       # fill in your IPs, domain, passwords
task --list                # verify all tasks loaded from the submodule

# ── Provision cluster ─────────────────────────────────────────────────────────
task provision:inventory
task provision:site        # common → k3s → agents → kubeconfig (Ansible)

# ── Deploy platform (GitOps) ──────────────────────────────────────────────────
task argocd:deploy
task argocd:add-repo
task deploy:dashboard-secret
task deploy:grafana-secret

# ── Day-to-day ────────────────────────────────────────────────────────────────
task status:nodes          # node status
task status:all            # all pod statuses
git add apps/myapp/ && git commit -m "feat: add myapp" && git push   # ArgoCD deploys

# ── Maintain ─────────────────────────────────────────────────────────────────
git -C vendor/k3s-lab checkout v1.1.0 && git add vendor/k3s-lab   # bump toolkit

# ── Debug remotely ────────────────────────────────────────────────────────────
task ssh:server            # SSH shell on server VPS
task ssh:agent             # SSH shell on agent VPS
```
