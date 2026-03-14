# Configuration Reference

All configuration is managed through a `.env` file at the repository root. Copy the template and fill in your values:

```bash
cp .env.example .env
```

> ⚠️ **Never commit `.env` to git.** It is listed in `.gitignore`. The `.env.example` file (with placeholder values) is committed instead.

---

## All variables

### VPS nodes

| Variable | Example | Required | Description |
|---|---|---|---|
| `MASTER_IP` | `1.2.3.4` | ✅ | Public IP of the control-plane VPS |
| `WORKER_IP` | `5.6.7.8` | ✅ | Public IP of the worker VPS |

### SSH

| Variable | Default | Required | Description |
|---|---|---|---|
| `SSH_USER` | `ubuntu` | ✅ | SSH user after bootstrap (regular user, not root) |
| `SSH_KEY` | `~/.ssh/id_ed25519` | ✅ | Path to your SSH private key |
| `INITIAL_USER` | `root` | — | User for the very first connection (before bootstrap creates `SSH_USER`) |
| `SSH_PORT` | `22` | — | SSH port (Makefile default, not in `.env.example`) |

> `INITIAL_USER` is only used for the first `make k3s-master` run. After the VPS is bootstrapped with your regular user, `SSH_USER` takes over.

### k3s

| Variable | Example | Required | Description |
|---|---|---|---|
| `K3S_VERSION` | `v1.32.2+k3s1` | ✅ | Pinned k3s version — must match on master and worker |
| `K3S_NODE_TOKEN` | *(auto-filled)* | ✅ | Shared secret for worker join — auto-saved by `make k3s-master` |

> `K3S_NODE_TOKEN` is automatically written to `.env` after `make k3s-master` completes. You do not need to generate it manually.

### Helm chart versions

| Variable | Default | Description |
|---|---|---|
| `TRAEFIK_CHART_VERSION` | `34.4.0` | Traefik Helm chart version |
| `CERT_MANAGER_VERSION` | `v1.17.1` | cert-manager Helm chart version |
| `KUBE_PROMETHEUS_VERSION` | `82.10.3` | kube-prometheus-stack chart version |
| `LOKI_VERSION` | `6.35.1` | Loki Helm chart version |
| `PROMTAIL_VERSION` | `6.17.1` | Promtail Helm chart version |

Helm chart versions are pinned and managed by [Renovate](https://docs.renovatebot.com/) via the shared preset in `renovate.json`.

### Application

| Variable | Example | Required | Description |
|---|---|---|---|
| `DOMAIN` | `example.com` | ✅ | Primary domain (used for app subdomains) |
| `EMAIL` | `admin@example.com` | ✅ | Email for Let's Encrypt ACME registration |

### Traefik dashboard

| Variable | Example | Required | Description |
|---|---|---|---|
| `DASHBOARD_DOMAIN` | `dashboard.example.com` | ✅ | Subdomain for the Traefik admin dashboard |
| `DASHBOARD_PASSWORD` | *(htpasswd hash)* | ✅ | BasicAuth password — set via `make deploy-dashboard-secret` |

> `DASHBOARD_PASSWORD` is the **plain text** password. `make deploy-dashboard-secret` hashes it with `htpasswd -nb admin <password>` before storing it in the Kubernetes Secret.

### Grafana

| Variable | Example | Required | Description |
|---|---|---|---|
| `GRAFANA_DOMAIN` | `grafana.example.com` | ✅ | Subdomain for Grafana |
| `GRAFANA_PASSWORD` | *(your password)* | ✅ | Grafana admin password |

### Kubeconfig

| Variable | Default | Required | Description |
|---|---|---|---|
| `KUBECONFIG_CONTEXT` | `k3s-lab` | ✅ | kubectl context name created by `make kubeconfig` |

---

## Variable precedence

Variables are loaded with **no-overwrite semantics**: a value already set in the shell environment takes precedence over the `.env` file.

This allows Makefile targets to override `.env` at call time:

```bash
make deploy DOMAIN=staging.example.com
```

---

## Minimal `.env` for a first deploy

```bash
# Nodes
MASTER_IP=1.2.3.4
WORKER_IP=5.6.7.8

# SSH
SSH_USER=ubuntu
SSH_KEY=~/.ssh/id_ed25519

# k3s
K3S_VERSION=v1.32.2+k3s1

# Application
DOMAIN=example.com
EMAIL=you@example.com

# Traefik dashboard
DASHBOARD_DOMAIN=dashboard.example.com
DASHBOARD_PASSWORD=changeme

# Grafana
GRAFANA_DOMAIN=grafana.example.com
GRAFANA_PASSWORD=changeme

# Kubeconfig
KUBECONFIG_CONTEXT=k3s-lab
```
