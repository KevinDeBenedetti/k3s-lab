# Task Targets Reference

This repo is orchestrated with [Task](https://taskfile.dev). List every available
target with:

```bash
task --list
```

Targets are grouped into namespaces (`<namespace>:<task>`). The base stack,
monitoring, and security components are deployed declaratively via Helm charts +
ArgoCD — the tasks below cover provisioning, secrets, and day-2 operations.

---

## Provisioning (Ansible)

| Target                     | Required                   | Description                                                  |
| -------------------------- | -------------------------- | ------------------------------------------------------------ |
| `task provision:inventory` | Terraform outputs / hosts  | Generate the Ansible inventory                               |
| `task provision:server`    | inventory                  | Provision the server node (common + k3s server)              |
| `task provision:agents`    | inventory + running server | Join agent nodes to the cluster                              |
| `task provision:site`      | inventory                  | Full provisioning: common + k3s server + agents + kubeconfig |
| `task provision:reset`     | inventory                  | ⚠️ Uninstall k3s from all nodes (destructive)                 |

---

## Kubeconfig

| Target                  | Required vars                                 | Description                                                          |
| ----------------------- | --------------------------------------------- | -------------------------------------------------------------------- |
| `task kubeconfig:fetch` | `SERVER_IP`, `SSH_USER`, `KUBECONFIG_CONTEXT` | Fetch `k3s.yaml` from the server and merge it into `~/.kube/config`. |

`task provision:site` already fetches the kubeconfig — use this task only to
(re)fetch it standalone. After running:

```bash
kubectl config use-context k3s-lab
kubectl get nodes
```

---

## Deployment & secrets

The base stack, monitoring, and security are deployed via Helm charts + ArgoCD.
These tasks create the secrets those charts consume and handle teardown.

| Target                         | Required vars                            | Description                                                       |
| ------------------------------ | ---------------------------------------- | ----------------------------------------------------------------- |
| `task deploy:dashboard-secret` | `DASHBOARD_PASSWORD`                     | Create the `traefik-dashboard-auth` BasicAuth secret (`ingress`). |
| `task deploy:grafana-secret`   | `GRAFANA_PASSWORD`, `KUBECONFIG_CONTEXT` | Create the `grafana-admin-secret` (`monitoring`).                 |
| `task deploy:grafana-oauth`    | `GRAFANA_DOMAIN`                         | Restart Grafana to pick up the OAuth secret from Vault.           |
| `task deploy:uninstall`        | —                                        | ⚠️ Tear down all deployed workloads (destructive).                 |

---

## ArgoCD

| Target                              | Description                                |
| ----------------------------------- | ------------------------------------------ |
| `task argocd:deploy`                | Install / upgrade ArgoCD                   |
| `task argocd:add-repo`              | Register the GitOps repo with ArgoCD       |
| `task argocd:status`                | Show ArgoCD application sync/health status |
| `task argocd:password`              | Print the initial admin password           |
| `task argocd:delete-initial-secret` | Remove the bootstrap admin secret          |
| `task argocd:disable-admin`         | Disable the built-in admin account         |

---

## Vault

| Target                       | Description                                  |
| ---------------------------- | -------------------------------------------- |
| `task vault:init`            | Initialize Vault (one-time)                  |
| `task vault:unseal`          | Unseal Vault                                 |
| `task vault:configure`       | Configure Vault auth/policies/secret engines |
| `task vault:seed`            | Seed application secrets into Vault          |
| `task vault:status`          | Show Vault status                            |

---

## Status

| Target                 | Description                                            |
| ---------------------- | ------------------------------------------------------ |
| `task status:nodes`    | Show cluster nodes (`kubectl get nodes -o wide`)       |
| `task status:all`      | Show all non-completed pods across namespaces          |
| `task status:pods`     | Show pod resource usage (requires metrics-server)      |
| `task status:certs`    | Show cert-manager certificate status                   |
| `task status:security` | Show NetworkPolicies and Pod Security Standards labels |

---

## SSH shortcuts

| Target                       | Required vars | Description                                      |
| ---------------------------- | ------------- | ------------------------------------------------ |
| `task ssh:server`            | `SERVER_IP`   | Open an interactive SSH shell on the server node |
| `task ssh:agent`             | `AGENT_IP`    | Open an interactive SSH shell on the agent node  |
| `task ssh:known-hosts-reset` | —             | Remove stale `~/.ssh/known_hosts` entries        |

---

## Dev tools

| Target                  | Description                                         |
| ----------------------- | --------------------------------------------------- |
| `task dev:test`         | Run BATS unit tests (offline, no cluster required)  |
| `task dev:test-watch`   | Re-run tests on every file change (requires `entr`) |
| `task dev:lint`         | Run all linters via `prek`                          |
| `task dev:lint-install` | Install `prek` git hooks                            |
| `task dev:hooks-update` | Update `prek` hook revisions to latest              |

---

## Full workflow example

```bash
# 1. Copy and configure environment
cp .env.example .env
# Edit .env with your node IPs, domain, etc.

# 2. Provision the cluster with Ansible
task provision:inventory
task provision:site        # common + k3s server + agents + kubeconfig

# 3. Configure kubectl
kubectl config use-context k3s-lab
task status:nodes          # Verify nodes are Ready

# 4. Create stack secrets (charts are reconciled by ArgoCD)
task deploy:dashboard-secret
task deploy:grafana-secret

# 5. Verify
task status:all
```

---

## Using the taskfiles from another repo

The taskfiles are includable fragments: a config repo of your own can include
them from a pinned checkout of this repository (`includes: <ns>: taskfile:
<path>/taskfiles/<ns>.yml`). For the homelab path without Task, see
[Running a homelab](../homelab.md).
