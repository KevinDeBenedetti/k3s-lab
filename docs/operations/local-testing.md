# Local Testing

Test the entire stack on your Mac without touching a real VPS — using BATS for offline unit tests and [Lima](https://lima-vm.io) for full end-to-end VM testing.

---

## Overview

| Method             | What it tests                                          | Cluster needed |
| ------------------ | ------------------------------------------------------ | -------------- |
| `make test` (BATS) | Shell scripts, manifests, `.env` keys                  | ❌ Offline      |
| Lima VM            | Full k3s install + Traefik + cert-manager + monitoring | ✅ Local VM     |

---

## 1. BATS unit tests (offline)

Run static checks with no cluster required:

```bash
make test
```

This runs `bats tests/bats/` which covers:

| Test file         | What it checks                            |
| ----------------- | ----------------------------------------- |
| `env.bats`        | `.env.example` has all required variables |
| `kubernetes.bats` | Kubernetes manifests are valid YAML       |
| `scripts.bats`    | Shell scripts pass `bash -n` syntax check |

**Prerequisite:**
```bash
brew install bats-core
```

---

## 2. Lima VM — full local k3s cluster

Lima runs a Debian 12 VM on macOS (Apple Virtualization framework), exposing port `6443` on `localhost`. This lets you test `install-master.sh`, Helm deployments, TLS, and Grafana exactly as they run in production.

**Prerequisites:**

```bash
brew install lima
```

> On Apple Silicon, run this first if the VM hangs on first boot:
> ```bash
> softwareupdate --install-rosetta
> ```

---

### 2.1 Full automated cycle

Run all steps in one command:

```bash
make vm-k3s-full
```

This executes: **create → install → kubeconfig → verify**

After it completes, your cluster is reachable:

```bash
kubectl --context k3s-lima get nodes
kubectl --context k3s-lima get pods -A
```

---

### 2.2 Step by step

#### Create the VM

```bash
make vm-k3s-create
```

Creates a Debian 12 VM (`infra-k3s-vm`) with:
- 2 vCPU, 4 GB RAM, 20 GB disk
- Apple VZ framework (`vmType: vz`)
- Port `6443` forwarded to `localhost:6443` (k3s API server)
- Host `~` mounted read-only inside the VM

#### Install k3s master

```bash
make vm-k3s-install
```

Runs `k3s/install-master.sh` inside the VM with:
- `K3S_NODE_TOKEN=lima-local-test-token-k3s`
- `PUBLIC_IP=127.0.0.1`

#### Merge kubeconfig

```bash
make vm-k3s-kubeconfig
```

Fetches `/etc/rancher/k3s/k3s.yaml` from the VM and merges it into `~/.kube/config` as context `k3s-lima`.

```bash
kubectl config use-context k3s-lima
kubectl get nodes
```

#### Verify the cluster

```bash
make vm-k3s-test
```

Runs `tests/scripts/verify-k3s.sh` inside the VM. Expected output:

```
✅ k3s.service active
✅ Node status: Ready
✅ coredns: Running
✅ local-path-provisioner: Running
✅ metrics-server: Running
✅ TLS: server CA cert exists
✅ All 15 checks passed — k3s cluster is healthy
```

---

### 2.3 Deploy base stack (Traefik + cert-manager)

```bash
make vm-k3s-deploy
```

Deploys Traefik (as NodePort on `:30080`/`:30443`) and cert-manager with the `selfsigned-issuer` ClusterIssuer, mirroring the production deploy.

---

### 2.4 Smoke tests

Run after `make vm-k3s-deploy` to validate the full TLS pipeline:

#### TLS pipeline smoke test

```bash
make vm-k3s-smoke
```

Deploys a `whoami` app, waits for cert-manager to issue a self-signed TLS certificate, then verifies Traefik routes HTTPS traffic:

```
✅ TLS smoke test passed — HTTP 200
Hostname: whoami-...
IP: 10.42.0.x
```

Cleans up all resources on completion.

#### Monitoring TLS smoke test

```bash
make vm-k3s-smoke-monitoring
```

Same pipeline but with a Grafana-like IngressRoute. Confirms `cert-manager → Traefik → service` works for the monitoring namespace:

```
✅ Monitoring TLS smoke test passed — HTTP 200
{"database":"ok","version":"12.4.1",...}
```

> Both smoke tests are **ephemeral** — they clean up after themselves. Run `make vm-k3s-deploy-monitoring` for a persistent Grafana instance.

---

### 2.5 Deploy persistent monitoring stack

```bash
make vm-k3s-deploy-monitoring
```

Deploys the full observability stack on the Lima cluster:
- `kube-prometheus-stack` (Prometheus + Grafana + node-exporter + kube-state-metrics)
- `Loki` (single-binary, filesystem storage)
- `Promtail` (DaemonSet log collector)
- Grafana IngressRoute with self-signed TLS certificate

**Default credentials:** `admin` / `admin`  
Override at call time: `make vm-k3s-deploy-monitoring LIMA_GRAFANA_PASSWORD=mypassword`

#### Add local DNS entry (one-time)

```bash
echo '127.0.0.1  grafana.local' | sudo tee -a /etc/hosts
```

#### Access Grafana

Open `https://grafana.local:8443` in your browser (accept the self-signed cert warning).

---

### 2.6 Verify monitoring in Grafana

After `make vm-k3s-deploy-monitoring`:

**Check pods are running:**
```bash
kubectl --context k3s-lima get pods -n monitoring
```

**Verify data sources:**

1. Open Grafana → **Connections → Data Sources**
2. Test **Prometheus** → `Data source is working`
3. Test **Loki** → `Data source connected and labels found`

> If data sources are missing, restart Grafana:
> ```bash
> kubectl --context k3s-lima rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
> ```

**Port-forward Prometheus UI (optional):**
```bash
kubectl --context k3s-lima port-forward svc/prometheus-operated -n monitoring 9090:9090
# Open: http://localhost:9090/targets — verify all targets are UP
```

**Explore logs in Grafana:**

Navigate to **Explore → Loki** and run:
```logql
{namespace=~".+"}
```

To filter for errors only (mirrors the built-in dashboard):
```logql
{namespace=~".+"} |~ "(?i)error|exception|traceback|fatal|panic"
```

**Built-in dashboards** (auto-discovered via `grafana_dashboard: "1"` labels):
- **Logs Errors Overview** — error rate by namespace + live error tail
- **Kubernetes / Nodes** — CPU, RAM, disk, network from `node-exporter`
- **Kubernetes / Pods** — pod resource usage from `kube-state-metrics`

---

### 2.7 VM lifecycle commands

| Command                         | Description                                        |
| ------------------------------- | -------------------------------------------------- |
| `make vm-k3s-full`              | Full cycle: create → install → kubeconfig → verify |
| `make vm-k3s-create`            | Create Debian 12 VM                                |
| `make vm-k3s-install`           | Run `install-master.sh` inside the VM              |
| `make vm-k3s-kubeconfig`        | Merge kubeconfig → context `k3s-lima`              |
| `make vm-k3s-test`              | Verify cluster health                              |
| `make vm-k3s-deploy`            | Deploy Traefik + cert-manager                      |
| `make vm-k3s-deploy-monitoring` | Deploy Prometheus + Grafana + Loki + Promtail      |
| `make vm-k3s-smoke`             | TLS pipeline smoke test (ephemeral)                |
| `make vm-k3s-smoke-monitoring`  | Monitoring TLS smoke test (ephemeral)              |
| `make vm-k3s-shell`             | Open interactive shell in the VM                   |
| `make vm-k3s-stop`              | Stop VM (keep disk + state)                        |
| `make vm-k3s-start`             | Start a stopped VM                                 |
| `make vm-k3s-clean`             | Delete VM and free disk                            |

---

## 3. Typical test session

```bash
# Run offline tests first (no VM needed)
make test

# Start a full k3s VM
make vm-k3s-full

# Deploy and smoke-test the full stack
make vm-k3s-deploy
make vm-k3s-smoke
make vm-k3s-smoke-monitoring

# Deploy persistent monitoring and verify in Grafana
make vm-k3s-deploy-monitoring
# Open https://grafana.local:8443

# Clean up when done
make vm-k3s-clean
```

---

## 4. What the Lima VM mirrors from production

| Production                     | Lima equivalent                      |
| ------------------------------ | ------------------------------------ |
| VPS public IP                  | `127.0.0.1` (port-forwarded)         |
| `KUBECONFIG_CONTEXT=k3s-infra` | `k3s-lima`                           |
| Let's Encrypt TLS              | `selfsigned-issuer` ClusterIssuer    |
| Traefik LoadBalancer           | Traefik NodePort (`:30080`/`:30443`) |
| `grafana.kevindb.dev`          | `grafana.local` (in `/etc/hosts`)    |
| `letsencrypt-production` cert  | Self-signed cert (no DNS required)   |

The install scripts, Helm values, and Kubernetes manifests are **identical** between the Lima test environment and production.
