# Getting Started

This guide walks you through provisioning a production-ready k3s cluster from two fresh VPS nodes.

## Two ways to use k3s-lab

| Mode | When to use |
|------|-------------|
| **Direct** (this guide) | Evaluate the toolkit, test locally, or you don't need a private config repo |
| **Infra repo** | Production use — private repo holds your `.env`, secrets, and custom apps; k3s-lab is fetched on-demand |

> For the infra repo pattern, see **[Using with a private infra repo](./using-with-infra.md)** once you've read this guide.

---

## Prerequisites

### Local machine

| Tool | Purpose | Install |
|---|---|---|
| `kubectl` | Kubernetes CLI | `brew install kubectl` |
| `helm` | Helm package manager | `brew install helm` |
| `ssh` / `scp` | VPS access | Pre-installed on macOS/Linux |
| `htpasswd` | BasicAuth secret generation | `brew install httpd` |
| `envsubst` | Variable substitution in manifests | `brew install gettext` |
| `bats` | Optional: run tests locally | `brew install bats-core` |

### VPS nodes

| Requirement | Value |
|---|---|
| OS | Ubuntu 22.04+ or Debian 12+ |
| Architecture | x86_64 or ARM64 |
| Master: vCPU / RAM | 2 vCPU / 2 GB minimum (4 GB recommended) |
| Worker: vCPU / RAM | 2 vCPU / 1 GB minimum (2 GB recommended) |
| Disk | 20 GB+ (master), 20 GB+ (worker) |
| Public IP | Required on each node |
| DNS | A records pointing to `MASTER_IP` for all subdomains |

### DNS records (before deploy)

Set the following A records to `MASTER_IP`:

```
dashboard.example.com → MASTER_IP
grafana.example.com   → MASTER_IP
app.example.com       → MASTER_IP   (your apps)
```

> DNS must propagate before TLS certificates can be issued. Use `dig dashboard.example.com` to verify.

---

## Step 1 — Configure environment

```bash
cp .env.example .env
```

Edit `.env` and fill in at minimum:

```bash
MASTER_IP=1.2.3.4
WORKER_IP=5.6.7.8
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

## Step 2 — Bootstrap master node

```bash
make k3s-master
```

This installs k3s server on `MASTER_IP` with:
- Traefik and built-in LB **disabled** (managed via Helm)
- `--tls-san` set to the public IP for remote `kubectl` access
- Secrets encryption at rest
- Flannel VXLAN overlay network
- UFW rules for HTTP/HTTPS/API server

When it completes, `K3S_NODE_TOKEN` is automatically saved to `.env`.

> ⏱️ Takes ~5 minutes on a typical VPS.

---

## Step 3 — Join worker node

```bash
make k3s-worker
```

This:
1. Opens the master UFW for the worker IP (VXLAN + kubelet ports)
2. Installs k3s agent on `WORKER_IP`

> ⏱️ Takes ~3 minutes.

---

## Step 4 — Fetch kubeconfig

```bash
make kubeconfig
kubectl config use-context k3s-lab
```

Verify both nodes are ready:

```bash
make nodes
# NAME     STATUS   ROLES                  AGE   VERSION
# master   Ready    control-plane,master   5m    v1.32.2+k3s1
# worker   Ready    <none>                 2m    v1.32.2+k3s1
```

---

## Step 5 — Deploy base stack

### Create the dashboard secret

```bash
make deploy-dashboard-secret
```

### Deploy Traefik + cert-manager

```bash
make deploy
```

This deploys in order:
1. **Namespaces** — `ingress`, `cert-manager`, `monitoring`, `apps`
2. **Traefik** — Helm chart with values from `kubernetes/ingress/traefik-values.yaml`
3. **cert-manager** — with CRDs installed
4. **ClusterIssuers** — Let's Encrypt staging + production
5. **Traefik dashboard** — secured IngressRoute at `DASHBOARD_DOMAIN`

> ⏱️ Takes ~3 minutes. TLS certificate issuance happens in the background and takes ~30s after DNS resolves.

---

## Step 6 — Deploy monitoring

### Create Grafana admin secret

```bash
make deploy-grafana-secret
```

### Deploy observability stack

```bash
make deploy-monitoring
```

This deploys:
1. **kube-prometheus-stack** — Prometheus + Grafana + Alertmanager
2. **Loki** — centralized log storage
3. **Promtail** — log collector DaemonSet
4. **Grafana IngressRoute** — HTTPS at `GRAFANA_DOMAIN`

> ⏱️ Takes ~10 minutes (large chart images).

---

## Step 7 — Verify

```bash
make status
```

All pods should be `Running` or `Completed`.

**Access points:**

| Service | URL | Credentials |
|---|---|---|
| Traefik dashboard | `https://DASHBOARD_DOMAIN/dashboard/` | `admin` / `DASHBOARD_PASSWORD` |
| Grafana | `https://GRAFANA_DOMAIN` | `admin` / `GRAFANA_PASSWORD` |
| Prometheus | `kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090` | — |

---

## Deploy an example app

The `kubernetes/apps/` directory contains an example app:

```bash
# Deploy example app with ingress + TLS
envsubst < kubernetes/apps/deployment.yaml | kubectl apply -f -
envsubst < kubernetes/apps/service-ingress.yaml | kubectl apply -f -
```

See [Traefik → Deploying your own services](./stack/traefik#deploying-your-own-services) for the IngressRoute pattern.

---

## Next steps

- [Configuration reference](./configuration) — all `.env` variables
- [k3s details](./stack/k3s) — install flags, firewall, sysctl
- [Traefik](./stack/traefik) — IngressRoute, middlewares, TLS
- [cert-manager](./stack/cert-manager) — Let's Encrypt, staging vs production
- [Monitoring](./stack/monitoring) — Grafana dashboards, LogQL, Prometheus
- [Make targets](./operations/make-targets) — full reference
- [Troubleshooting](./operations/troubleshooting) — common issues
