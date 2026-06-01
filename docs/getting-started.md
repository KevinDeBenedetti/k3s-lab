# Getting Started

This guide walks you through provisioning a production-ready k3s cluster from two fresh VPS nodes.

## Two ways to use k3s-lab

| Mode                    | When to use                                                                                                               |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| **Direct** (this guide) | Evaluate the toolkit, test locally, or you don't need a private config repo                                               |
| **Infra repo**          | Production use — private repo holds your `.env`, secrets, and custom apps; k3s-lab is consumed via a pinned git submodule |

> For the infra repo pattern, see **[Using with a private infra repo](./using-with-infra.md)** once you've read this guide.

---

## Prerequisites

### Local machine

| Tool          | Purpose                            | Install                      |
| ------------- | ---------------------------------- | ---------------------------- |
| `kubectl`     | Kubernetes CLI                     | `brew install kubectl`       |
| `helm`        | Helm package manager               | `brew install helm`          |
| `ssh` / `scp` | VPS access                         | Pre-installed on macOS/Linux |
| `htpasswd`    | BasicAuth secret generation        | `brew install httpd`         |
| `envsubst`    | Variable substitution in manifests | `brew install gettext`       |
| `bats`        | Optional: run tests locally        | `brew install bats-core`     |

### VPS nodes

| Requirement        | Value                                                                   |
| ------------------ | ----------------------------------------------------------------------- |
| OS                 | Ubuntu 22.04+ or Debian 12+                                             |
| Architecture       | x86_64 or ARM64                                                         |
| Server: vCPU / RAM | 2 vCPU / 2 GB minimum (4 GB recommended)                                |
| Agent: vCPU / RAM  | 2 vCPU / 1 GB minimum (2 GB recommended)                                |
| Disk               | 20 GB+ (server), 20 GB+ (agent)                                         |
| Public IP          | Required on each node                                                   |
| DNS                | Managed by Cloudflare (A records created automatically by external-dns) |

### DNS records

> **No manual DNS setup required.** Once `external-dns` is deployed, it automatically creates and updates Cloudflare A records whenever you add an `IngressRoute` with the `external-dns.alpha.kubernetes.io/hostname` annotation.
>
> TLS certificates use the **DNS-01 challenge** (Cloudflare API), so they can be issued even before traffic is routed — no chicken-and-egg problem with DNS propagation.

---

## Step 1 — Configure environment

```bash
cp .env.example .env
```

Edit `.env` and fill in at minimum:

```bash
SERVER_IP=1.2.3.4
AGENT_IP=5.6.7.8
SSH_USER=ubuntu
SSH_KEY=~/.ssh/id_ed25519
K3S_VERSION=v1.32.2+k3s1
DOMAIN=example.com
EMAIL=you@example.com
DASHBOARD_DOMAIN=dashboard.example.com
DASHBOARD_PASSWORD=your-secure-password
GRAFANA_DOMAIN=grafana.example.com
GRAFANA_PASSWORD=your-secure-password
KUBECONFIG_CONTEXT=k3s-lab
```

See [Configuration](./configuration) for the full variable reference.

---

## Step 2 — Provision the cluster

### Option A: Full provisioning (recommended)

```bash
task provision:site
```

This runs Ansible to configure all nodes:
1. **Common setup** — packages, kernel modules, sysctl, UFW, swap disabled
2. **k3s server** — installs k3s with Flannel VXLAN, disables Traefik/servicelb
3. **WireGuard** — optional VPN (if `wireguard_enabled: true` in group_vars)
4. **k3s agents** — joins agent nodes to the cluster
5. **Kubeconfig** — saved locally for `kubectl` access

### Option B: Step by step

```bash
task provision:server      # Common + k3s server + WireGuard
task provision:agents      # Join agent nodes
task kubeconfig:fetch      # Merge kubeconfig locally
```

> Requires Ansible inventory at `ansible/inventory/hosts.yml` — see [Configuration](./configuration).

---

## Step 3 — Verify nodes

```bash
kubectl config use-context k3s-lab
task status:nodes
# NAME     STATUS   ROLES                  AGE   VERSION
# server   Ready    control-plane,master   5m    v1.32.2+k3s1
```

---

## Step 4 — Deploy the platform (ArgoCD)

The base stack (Traefik, cert-manager, ClusterIssuers), monitoring, and security
components are deployed **declaratively via Helm charts + ArgoCD** — not imperative
commands. Bootstrap ArgoCD, then it reconciles everything from Git.

```bash
task argocd:deploy         # install ArgoCD
task argocd:add-repo       # register the GitOps repo
task argocd:status         # watch applications sync
```

Some components consume secrets you create up front:

```bash
task deploy:dashboard-secret   # Traefik dashboard BasicAuth
task deploy:grafana-secret     # Grafana admin credentials
```

> TLS certificate issuance happens in the background and takes ~30s after DNS resolves.

---

## Step 5 — Verify

```bash
task status:all
```

All pods should be `Running` or `Completed`.

**Access points:**

| Service           | URL                                   | Credentials                    |
| ----------------- | ------------------------------------- | ------------------------------ |
| Traefik dashboard | `https://DASHBOARD_DOMAIN/dashboard/` | `admin` / `DASHBOARD_PASSWORD` |
| Grafana           | `https://GRAFANA_DOMAIN`              | `admin` / `GRAFANA_PASSWORD`   |

---

## Deploy an example app

Create your app manifests in `apps/` (for infra repo) or follow the
[Deploying an App](./operations/deploy-app) guide:

```bash
# ArgoCD auto-discovers apps/ directories — just push to git
mkdir -p apps/myapp/
# Add deployment.yaml, service.yaml, ingress.yaml
git add apps/myapp/ && git commit -m "feat: add myapp" && git push
```

See [Traefik → Deploying your own services](./stack/traefik#deploying-your-own-services) for the IngressRoute pattern.

---

## Next steps

- [Configuration reference](./configuration) — all `.env` variables
- [k3s details](./stack/k3s) — install flags, firewall, sysctl
- [Traefik](./stack/traefik) — IngressRoute, middlewares, TLS
- [cert-manager](./stack/cert-manager) — Let's Encrypt, staging vs production
- [Monitoring](./stack/monitoring) — Grafana dashboards, LogQL, Prometheus
- [Task targets](./operations/task-targets) — full reference
- [Troubleshooting](./operations/troubleshooting) — common issues
