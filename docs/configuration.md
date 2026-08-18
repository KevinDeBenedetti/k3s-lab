# Configuration Reference

All configuration is managed through a `.env` file at the repository root. Copy the template and fill in your values:

```bash
cp .env.example .env
```

> ⚠️ **Never commit `.env` to git.** It is listed in `.gitignore`. The `.env.example` file (with placeholder values) is committed instead.

---

## All variables

### VPS nodes

| Variable    | Example   | Required | Description                        |
| ----------- | --------- | -------- | ---------------------------------- |
| `SERVER_IP` | `1.2.3.4` | ✅        | Public IP of the control-plane VPS |
| `AGENT_IP`  | `5.6.7.8` | ✅        | Public IP of the agent VPS         |

### SSH

| Variable       | Default             | Required | Description                                                              |
| -------------- | ------------------- | -------- | ------------------------------------------------------------------------ |
| `SSH_USER`     | `debian`            | ✅        | SSH user after bootstrap (regular user, not root)                        |
| `SSH_KEY`      | `~/.ssh/id_ed25519` | ✅        | Path to your SSH private key                                             |
| `INITIAL_USER` | `root`              | —        | User for the very first connection (before bootstrap creates `SSH_USER`) |
| `SSH_PORT`     | `22`                | —        | SSH port (default, not in `.env.example`)                                |

> `INITIAL_USER` is only used for the initial Ansible connection. After the VPS is bootstrapped, `SSH_USER` takes over.

### k3s

| Variable         | Example         | Required | Description                                                     |
| ---------------- | --------------- | -------- | --------------------------------------------------------------- |
| `K3S_VERSION`    | `v1.32.13+k3s1`  | ✅        | Pinned k3s version — must match on server and agent             |
| `K3S_NODE_TOKEN` | *(auto-filled)* | ✅        | Shared secret for agent join — auto-read from server by Ansible |

> `K3S_NODE_TOKEN` is automatically read from the server by the Ansible `site.yml` playbook and passed to agents. You do not need to set it manually.

### Helm chart versions

**Chart versions are not configured here.** They are pinned in
`charts/*/Chart.yaml` under `dependencies:`, which is the only place that
decides what gets installed:

```bash
grep -A2 '^dependencies:' charts/*/Chart.yaml
```

Until 2026-08-06 this section listed `TRAEFIK_CHART_VERSION`,
`CERT_MANAGER_VERSION`, `GRAFANA_VERSION`, `LOKI_VERSION` and
`PROMTAIL_VERSION` as if setting them changed something. They were read by no
taskfile, no script and no chart — only by the copy-paste `helm install`
snippets in `docs/stack/`. Every value shown had also gone stale (Traefik was
listed at `34.4.0` against a real pin of `41.1.0`, Loki `6.35.1` against
`7.0.0`), so following this page produced a cluster two majors behind the repo.
They have been dropped from `.env.example` rather than refreshed, because
refreshing them only resets the clock on the same drift.

> Earlier revisions of this page claimed these versions were "managed by
> Renovate via the shared preset in `renovate.json`". There is no `renovate.json`
> in this repo and there never was. Dependency automation is
> [`.github/dependabot.yml`](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/.github/dependabot.yml), added 2026-08-06, and it
> covers GitHub Actions only — chart pins are bumped by hand and guarded by
> `scripts/check-deployed-pins.sh` and `scripts/check-umbrella-pins.sh`.

The one exception is `ARGOCD_VERSION`, which really is read — by
`taskfiles/argocd.yml`, the Helm bootstrap that installs ArgoCD before ArgoCD
can manage anything itself:

| Variable         | Default  | Required | Description                                       |
| ---------------- | -------- | -------- | ------------------------------------------------- |
| `ARGOCD_VERSION` | `9.5.17` | —        | `argo/argo-cd` chart version used by `task argocd:install` |

Keep it equal to the `argo-cd` dependency in
[`charts/platform-argocd/Chart.yaml`](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/charts/platform-argocd/Chart.yaml).
Because ArgoCD is bootstrapped by Helm rather than by its own ApplicationSet,
this is the one component `scripts/check-deployed-pins.sh` structurally cannot
see — which is how the cluster reached `platform-argocd 0.9.2` against a
published `0.18.3` (audit finding 3). When you bump one, bump both.

### Application

| Variable | Example             | Required | Description                               |
| -------- | ------------------- | -------- | ----------------------------------------- |
| `DOMAIN` | `example.com`       | ✅        | Primary domain (used for app subdomains)  |
| `EMAIL`  | `admin@example.com` | ✅        | Email for Let's Encrypt ACME registration |

### Traefik dashboard

| Variable             | Example                 | Required | Description                                                 |
| -------------------- | ----------------------- | -------- | ----------------------------------------------------------- |
| `DASHBOARD_DOMAIN`   | `dashboard.example.com` | ✅        | Subdomain for the Traefik admin dashboard                   |
| `DASHBOARD_PASSWORD` | *(htpasswd hash)*       | ✅        | BasicAuth password — set via `task deploy:dashboard-secret` |

> `DASHBOARD_PASSWORD` is the **plain text** password. `task deploy:dashboard-secret` hashes it with `htpasswd -nb admin <password>` before storing it in the Kubernetes Secret.

### Grafana

| Variable           | Example               | Required | Description            |
| ------------------ | --------------------- | -------- | ---------------------- |
| `GRAFANA_DOMAIN`   | `grafana.example.com` | ✅        | Subdomain for Grafana  |
| `GRAFANA_PASSWORD` | *(your password)*     | ✅        | Grafana admin password |

### Kubeconfig

| Variable             | Default   | Required | Description                                             |
| -------------------- | --------- | -------- | ------------------------------------------------------- |
| `KUBECONFIG_CONTEXT` | `k3s-lab` | ✅        | kubectl context name created by `task kubeconfig:fetch` |


## Ansible role variables (not `.env`)

A few settings are **Ansible variables, not `.env` variables**. They are read by
the roles during provisioning, so putting them in `.env` has no effect — set them
in `ansible/inventory/group_vars/all.yml`, or pass them at call time with
`-e <name>=<value>`.

### Firewall

| Variable                | Default | Description                                                    |
| ----------------------- | ------- | -------------------------------------------------------------- |
| `k3s_lab_ufw_enabled`   | `true`  | Single switch for **every** UFW task in the repo               |
| `k3s_lab_ufw_retries`   | `5`     | Retries per UFW task (they race k3s rewriting nf_tables)       |
| `k3s_lab_ufw_delay`     | `3`     | Seconds between those retries                                  |

`k3s_lab_ufw_enabled: false` disables firewall management everywhere at once —
the rules in `common`, `k3s_server`, `k3s_agent` and `wireguard`, *and* the final
`ufw_enable` role that turns UFW on. Use it when the firewall is managed outside
this repo (a cloud provider's security groups, for instance). It does **not**
disable an already-active UFW; it only stops Ansible from touching it.

> Each of those five roles redeclares these three variables with the same
> default. That is deliberate, not duplication to tidy up: role defaults are only
> in scope while their own role runs, and `site.yml` applies `common` and
> `k3s_server` in **separate plays**, so a single declaration in `common` would
> read as undefined everywhere else. Setting the variable once in
> `group_vars/all.yml` overrides all five, which is the point.

The predecessor name `common_ufw_enabled` is still honoured as a fallback, so an
existing inventory keeps working, but it only ever guarded the `common` role.
Prefer `k3s_lab_ufw_enabled`.

> ⚠️ UFW is enabled by the `ufw_enable` role, which the playbooks apply as their
> **last play** — after every rule is in place. Do not move it earlier: a run
> interrupted between `common` and the end would otherwise leave the node behind
> an active default-deny firewall holding only the rules reached so far, with no
> API port and possibly no WireGuard. The trade is that a first provisioning run
> has no firewall until it completes.

## Variable precedence

Variables are loaded with **no-overwrite semantics**: a value already set in the shell environment takes precedence over the `.env` file.

This allows Task invocations to override `.env` at call time:

```bash
task deploy:dashboard-secret DASHBOARD_PASSWORD=...
```

---

## Minimal `.env` for a first deploy

```bash
# Nodes
SERVER_IP=1.2.3.4
AGENT_IP=5.6.7.8

# SSH
SSH_USER=debian
SSH_KEY=~/.ssh/id_ed25519

# k3s
K3S_VERSION=v1.32.13+k3s1

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

| Key                                       | Example value                              |
| ----------------------------------------- | ------------------------------------------ |
| `GF_AUTH_GENERIC_OAUTH_ENABLED`           | `"true"`                                   |
| `GF_AUTH_GENERIC_OAUTH_NAME`              | `"My Provider"`                            |
| `GF_AUTH_GENERIC_OAUTH_CLIENT_ID`         | `"<your-client-id>"`                       |
| `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET`     | `"<your-client-secret>"`                   |
| `GF_AUTH_GENERIC_OAUTH_SCOPES`            | `"openid email profile"`                   |
| `GF_AUTH_GENERIC_OAUTH_AUTH_URL`          | `"https://provider.example.com/authorize"` |
| `GF_AUTH_GENERIC_OAUTH_TOKEN_URL`         | `"https://provider.example.com/token"`     |
| `GF_AUTH_GENERIC_OAUTH_API_URL`           | `"https://provider.example.com/userinfo"`  |
| `GF_AUTH_GENERIC_OAUTH_USE_PKCE`          | `"true"`                                   |
| `GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN` | `"true"`                                   |
| `GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN`        | `"true"`                                   |
| `GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP`     | `"true"`                                   |
| `GF_AUTH_DISABLE_LOGIN_FORM`              | `"true"`                                   |

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
add a `deploy:grafana-oauth-secret` task to your `infra/Taskfile.yml` that
creates the secret from your provider's credentials stored in `.env`.
