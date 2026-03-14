# Make Targets Reference

Run `make help` to see all available targets with their descriptions.

```bash
make help
```

---

## k3s

| Target                          | Required vars                              | Description                                                                                                                         |
| ------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `make k3s-master`               | `MASTER_IP`, `K3S_VERSION`                 | Install k3s server on the master node. Copies `install-master.sh` via SCP, runs it remotely, then saves `K3S_NODE_TOKEN` to `.env`. |
| `make k3s-worker`               | `WORKER_IP`, `MASTER_IP`, `K3S_NODE_TOKEN` | Open master firewall for the worker, install k3s agent on the worker node.                                                          |
| `make k3s-open-master-firewall` | `WORKER_IP`, `MASTER_IP`                   | Add UFW rules on the master to allow a new worker (VXLAN `:8472/udp`, kubelet `:10250/tcp`).                                        |
| `make k3s-uninstall-master`     | `MASTER_IP`                                | ⚠️ Remove k3s from the master node (destructive).                                                                                    |
| `make k3s-uninstall-worker`     | `WORKER_IP`                                | ⚠️ Remove k3s from the worker node (destructive).                                                                                    |

---

## Kubeconfig

| Target            | Required vars                                 | Description                                                                                                                                           |
| ----------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `make kubeconfig` | `MASTER_IP`, `SSH_USER`, `KUBECONFIG_CONTEXT` | Fetch `/etc/rancher/k3s/k3s.yaml` from the master, replace `127.0.0.1` with `MASTER_IP`, merge into `~/.kube/config` as context `KUBECONFIG_CONTEXT`. |

After running:
```bash
kubectl config use-context k3s-lab
kubectl get nodes
```

---

## Deployment

| Target                         | Required vars                                              | Description                                                                                                  |
| ------------------------------ | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `make deploy`                  | `DOMAIN`, `EMAIL`, `MASTER_IP`                             | Deploy base stack: namespaces, Traefik, cert-manager, ClusterIssuers, Traefik dashboard IngressRoute.        |
| `make deploy-dashboard-secret` | `DASHBOARD_PASSWORD`                                       | Create the `traefik-dashboard-auth` BasicAuth secret in the `ingress` namespace.                             |
| `make deploy-monitoring`       | `GRAFANA_DOMAIN`, `GRAFANA_PASSWORD`, `KUBECONFIG_CONTEXT` | Deploy observability stack: kube-prometheus-stack, Loki, Promtail, Grafana IngressRoute.                     |
| `make deploy-grafana-secret`   | `GRAFANA_PASSWORD`, `KUBECONFIG_CONTEXT`                   | Create the `grafana-admin-secret` in the `monitoring` namespace (prerequisite for `make deploy-monitoring`). |
| `make deploy-logging`          | —                                                          | Re-run monitoring script (Loki + Promtail).                                                                  |

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
| `make ssh-master`        | `MASTER_IP`   | Open an interactive SSH shell on the master node                                                      |
| `make ssh-worker`        | `WORKER_IP`   | Open an interactive SSH shell on the worker node                                                      |
| `make known-hosts-reset` | —             | Remove stale `~/.ssh/known_hosts` entries for `MASTER_IP` and `WORKER_IP` (useful after VPS reformat) |

---

## Testing

| Target      | Description                                        |
| ----------- | -------------------------------------------------- |
| `make test` | Run BATS unit tests (offline, no cluster required) |

---

## Lima VM (local testing)

Requires the [`infra`](https://github.com/KevinDeBenedetti/infra) parent repo, which embeds this repo as a submodule and adds Lima targets in `makefiles/99-lima.mk`.

| Target                          | Description                                                |
| ------------------------------- | ---------------------------------------------------------- |
| `make vm-k3s-full`              | Full cycle: create VM → install k3s → kubeconfig → verify  |
| `make vm-k3s-create`            | Create Debian 12 VM (2 CPU, 4 GB RAM, 20 GB disk)          |
| `make vm-k3s-install`           | Run `k3s/install-master.sh` inside the VM                  |
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
make k3s-master            # Install control plane (~5 min)
make k3s-worker            # Join worker node (~3 min)

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

## Submodule usage

When this repo is embedded as a git submodule in a parent infra repo:

```makefile
K3S_LAB := $(ROOT_DIR)/k3s-lab

include $(K3S_LAB)/makefiles/30-k3s.mk
include $(K3S_LAB)/makefiles/40-kubeconfig.mk
include $(K3S_LAB)/makefiles/50-deploy.mk
include $(K3S_LAB)/makefiles/60-status.mk
include $(K3S_LAB)/makefiles/70-ssh.mk
```

All targets resolve paths relative to `K3S_LAB` so they work correctly from any parent directory.
