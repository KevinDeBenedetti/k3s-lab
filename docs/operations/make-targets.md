# Make Targets Reference

Run `make help` to see all available targets with their descriptions.

```bash
make help
```

---

## k3s

| Target                          | Required vars                              | Description                                                                                                                         |
| ------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `make k3s-server`               | `SERVER_IP`, `K3S_VERSION`                 | Install k3s server on the server node. Copies `install-server.sh` via SCP, runs it remotely, then saves `K3S_NODE_TOKEN` to `.env`. |
| `make k3s-agent`                | `AGENT_IP`, `SERVER_IP`, `K3S_NODE_TOKEN`  | Open server firewall for the agent, install k3s agent on the agent node.                                                            |
| `make k3s-open-server-firewall` | `AGENT_IP`, `SERVER_IP`                    | Add UFW rules on the server to allow a new agent (VXLAN `:8472/udp`, kubelet `:10250/tcp`).                                         |
| `make k3s-uninstall-server`     | `SERVER_IP`                                | ⚠️ Remove k3s from the server node (destructive).                                                                                    |
| `make k3s-uninstall-agent`      | `AGENT_IP`                                 | ⚠️ Remove k3s from the agent node (destructive).                                                                                     |

---

## Kubeconfig

| Target            | Required vars                                 | Description                                                                                                                                           |
| ----------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `make kubeconfig` | `SERVER_IP`, `SSH_USER`, `KUBECONFIG_CONTEXT` | Fetch `/etc/rancher/k3s/k3s.yaml` from the server, replace `127.0.0.1` with `SERVER_IP`, merge into `~/.kube/config` as context `KUBECONFIG_CONTEXT`. |

After running:
```bash
kubectl config use-context k3s-lab
kubectl get nodes
```

---

## Deployment

| Target                         | Required vars                                              | Description                                                                                                  |
| ------------------------------ | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `make deploy`                  | `DOMAIN`, `EMAIL`, `SERVER_IP`                             | Deploy base stack: namespaces, Traefik, cert-manager, ClusterIssuers, Traefik dashboard IngressRoute.        |
| `make deploy-dashboard-secret` | `DASHBOARD_PASSWORD`                                       | Create the `traefik-dashboard-auth` BasicAuth secret in the `ingress` namespace.                             |
| `make deploy-monitoring`       | `GRAFANA_DOMAIN`, `GRAFANA_PASSWORD`, `KUBECONFIG_CONTEXT` | Deploy observability stack: kube-prometheus-stack, Loki, Promtail, Grafana IngressRoute.                     |
| `make deploy-grafana-secret`   | `GRAFANA_PASSWORD`, `KUBECONFIG_CONTEXT`                   | Create the `grafana-admin-secret` in the `monitoring` namespace (prerequisite for `make deploy-monitoring`). |

---

## Status

| Target        | Description                                                              |
| ------------- | ------------------------------------------------------------------------ |
| `make nodes`  | Show all cluster nodes with IPs and status (`kubectl get nodes -o wide`) |
| `make status` | Show all running pods across all namespaces                              |
| `make pods`   | Show pods with resource usage (`kubectl top pods`)                       |

---

## SSH shortcuts

| Target                   | Required vars | Description                                                                                           |
| ------------------------ | ------------- | ----------------------------------------------------------------------------------------------------- |
| `make ssh-server`        | `SERVER_IP`   | Open an interactive SSH shell on the server node                                                      |
| `make ssh-agent`         | `AGENT_IP`    | Open an interactive SSH shell on the agent node                                                       |
| `make known-hosts-reset` | —             | Remove stale `~/.ssh/known_hosts` entries for `SERVER_IP` and `AGENT_IP` (useful after VPS reformat)  |

---

## Testing

| Target             | Description                                               |
| ------------------ | --------------------------------------------------------- |
| `make test`        | Run BATS unit tests (offline, no cluster required)        |
| `make test-watch`  | Re-run tests on every file change (requires `entr`)       |

---

## Dev tools

| Target                | Description                                                           |
| --------------------- | --------------------------------------------------------------------- |
| `make lint`           | Run `prek` linter on staged git changes                               |
| `make lint-install`   | Install `prek` via Homebrew (`brew install j178/tap/prek`)            |
| `make hooks-update`   | Install / update git pre-commit hooks managed by `prek`               |

---

## Provision (one-shot)

| Target           | Description                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| `make provision` | Full cluster lifecycle: VPS setup → k3s server → k3s agent → kubeconfig → deploy → monitoring    |

This is equivalent to running all individual targets in order and is the recommended entry point for a fresh cluster.

---

## Lima VM (local testing)

Lima targets are bundled directly in k3s-lab (`makefiles/99-lima.mk`) — no parent repo or submodule required.

| Target                          | Description                                                |
| ------------------------------- | ---------------------------------------------------------- |
| `make vm-k3s-full`              | Full cycle: create VM → install k3s → kubeconfig → verify  |
| `make vm-k3s-create`            | Create Debian 12 VM (2 CPU, 4 GB RAM, 20 GB disk)          |
| `make vm-k3s-install`           | Run `k3s/install-server.sh` inside the VM                  |
| `make vm-k3s-kubeconfig`        | Merge kubeconfig → context `k3s-lima`                      |
| `make vm-k3s-test`              | Verify cluster health (all 15 checks)                      |
| `make vm-k3s-deploy`            | Deploy Traefik + cert-manager (mirrors production)         |
| `make vm-k3s-deploy-monitoring` | Deploy persistent Prometheus + Grafana + Loki + Promtail   |
| `make vm-k3s-smoke`             | Ephemeral TLS pipeline smoke test (cert-manager → Traefik) |
| `make vm-k3s-smoke-monitoring`  | Ephemeral monitoring TLS smoke test                        |
| `make vm-k3s-shell`             | Open interactive shell in the VM                           |
| `make vm-k3s-stop`              | Stop VM (keep disk + state)                                |
| `make vm-k3s-start`             | Start a stopped VM                                         |
| `make vm-k3s-clean`             | ⚠️ Delete VM and free disk                                  |

See the [Local Testing guide](./local-testing) for the full step-by-step walkthrough.

---

## Full workflow example

```bash
# 1. Copy and configure environment
cp .env.example .env
# Edit .env with your VPS IPs, domain, etc.

# 2. Bootstrap k3s
make k3s-server            # Install control plane (~5 min)
make k3s-agent             # Join agent node (~3 min)

# 3. Configure kubectl
make kubeconfig
kubectl config use-context k3s-lab
make nodes                 # Verify both nodes are Ready

# 4. Deploy base stack (Traefik + cert-manager)
make deploy-dashboard-secret
make deploy                # ~3 min

# 5. Deploy monitoring (Prometheus + Grafana + Loki)
make deploy-grafana-secret
make deploy-monitoring     # ~10 min

# 6. Verify
make status
```

---

## Using from a private infra repo

k3s-lab can be consumed from a **private repo** containing only your personal configuration (`.env`, app manifests). No clone or submodule needed — makefiles are fetched on-demand via curl.

Set these variables in your consumer Makefile:

```makefile
K3S_LAB     :=       # empty → remote mode (curl from GitHub)
K3S_LAB_RAW := https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main
```

All targets resolve scripts via `K3S_LAB_RAW` automatically.

| Target           | Description                                                           |
| ---------------- | --------------------------------------------------------------------- |
| `make mk-update` | Force re-fetch all shared makefiles from k3s-lab into `.mk-cache/`   |
| `make mk-clean`  | Remove `.mk-cache/` (files are re-fetched on the next `make` run)    |

See the [Using with infra guide](../using-with-infra.md) for the complete step-by-step walkthrough.
