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
| `SERVER_IP` | `1.2.3.4` | ✅ | Public IP of the control-plane VPS |
| `AGENT_IP` | `5.6.7.8` | ✅ | Public IP of the agent VPS |

### SSH

| Variable | Default | Required | Description |
|---|---|---|---|
| `SSH_USER` | `ubuntu` | ✅ | SSH user after bootstrap (regular user, not root) |
| `SSH_KEY` | `~/.ssh/id_ed25519` | ✅ | Path to your SSH private key |
| `INITIAL_USER` | `root` | — | User for the very first connection (before bootstrap creates `SSH_USER`) |
| `SSH_PORT` | `22` | — | SSH port (Makefile default, not in `.env.example`) |

> `INITIAL_USER` is only used for the initial Ansible connection. After the VPS is bootstrapped, `SSH_USER` takes over.

### k3s

| Variable | Example | Required | Description |
|---|---|---|---|
| `K3S_VERSION` | `v1.32.2+k3s1` | ✅ | Pinned k3s version — must match on server and agent |
| `K3S_NODE_TOKEN` | *(auto-filled)* | ✅ | Shared secret for agent join — auto-read from server by Ansible |

> `K3S_NODE_TOKEN` is automatically read from the server by the Ansible `site.yml` playbook and passed to agents. You do not need to set it manually.

### Helm chart versions

| Variable | Default | Description |
|---|---|---|
| `TRAEFIK_CHART_VERSION` | `34.4.0` | Traefik Helm chart version |
| `CERT_MANAGER_VERSION` | `v1.17.1` | cert-manager Helm chart version |
| `GRAFANA_VERSION` | `10.5.15` | Grafana Helm chart version |
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
SERVER_IP=1.2.3.4
AGENT_IP=5.6.7.8

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

---

## OAuth2 / SSO for Grafana

Grafana supports OAuth2 login via a Kubernetes Secret — no provider-specific
configuration is hardcoded in k3s-lab. Any OIDC-compatible provider works.

### How it works

`kube-prometheus-values.yaml` declares an **optional** secret mount:

```yaml
grafana:
  envFromSecrets:
    - name: grafana-oauth-secret
      optional: true   # Grafana starts normally if the secret does not exist
```

When `grafana-oauth-secret` is absent, Grafana uses admin/password login.
When the secret is present, Grafana reads every `GF_AUTH_GENERIC_OAUTH_*` key
from it and activates the configured provider.

### Required secret keys

Create the secret in the `monitoring` namespace with these keys:

| Key | Example value |
|---|---|
| `GF_AUTH_GENERIC_OAUTH_ENABLED` | `"true"` |
| `GF_AUTH_GENERIC_OAUTH_NAME` | `"My Provider"` |
| `GF_AUTH_GENERIC_OAUTH_CLIENT_ID` | `"<your-client-id>"` |
| `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` | `"<your-client-secret>"` |
| `GF_AUTH_GENERIC_OAUTH_SCOPES` | `"openid email profile"` |
| `GF_AUTH_GENERIC_OAUTH_AUTH_URL` | `"https://provider.example.com/authorize"` |
| `GF_AUTH_GENERIC_OAUTH_TOKEN_URL` | `"https://provider.example.com/token"` |
| `GF_AUTH_GENERIC_OAUTH_API_URL` | `"https://provider.example.com/userinfo"` |
| `GF_AUTH_GENERIC_OAUTH_USE_PKCE` | `"true"` |
| `GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN` | `"true"` |
| `GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN` | `"true"` |
| `GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP` | `"true"` |
| `GF_AUTH_DISABLE_LOGIN_FORM` | `"true"` |

### Creating the secret manually

```bash
kubectl create secret generic grafana-oauth-secret \
  --from-literal=GF_AUTH_GENERIC_OAUTH_ENABLED="true" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_NAME="My Provider" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_ID="<client-id>" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="<client-secret>" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_SCOPES="openid email profile" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_AUTH_URL="https://provider.example.com/authorize" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_TOKEN_URL="https://provider.example.com/token" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_API_URL="https://provider.example.com/userinfo" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_USE_PKCE="true" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN="true" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN="true" \
  --from-literal=GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP="true" \
  --from-literal=GF_AUTH_DISABLE_LOGIN_FORM="true" \
  --namespace monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then restart Grafana to pick up the secret:

```bash
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
kubectl rollout status deployment/kube-prometheus-stack-grafana -n monitoring --timeout=120s
```

### Using with a private infra repo

If you use k3s-lab with a private `infra` repo (see [using-with-infra.md](./using-with-infra.md)),
add a `deploy-grafana-oauth-secret` Make target to your `infra/Makefile` that
creates the secret from your provider's credentials stored in `.env`.
