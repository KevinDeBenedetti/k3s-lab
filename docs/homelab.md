# Running a homelab with k3s-lab

From a few machines on your LAN to a running k3s cluster with the platform on
top. Everything here uses only this repository and its published charts; your
own configuration (inventory, values, secrets) stays on your side.

> New to the toolkit? [Getting Started](./getting-started.md) explains the
> prerequisites and each role in more detail. This page is the short path.

---

## 1 — Describe your machines

```bash
mkdir -p ansible/inventory
cp ansible/inventory.example.yml ansible/inventory/hosts.yml
$EDITOR ansible/inventory/hosts.yml        # hosts, SSH user
```

`ansible/inventory/` is gitignored: it holds your node addresses. Role defaults
(`ansible/roles/*/defaults/main.yml`) cover the rest; override what you need in
`ansible/inventory/group_vars/all.yml` — typically `k3s_version` and
`k3s_ufw_allow_from` (your LAN CIDR).

## 2 — Provision the nodes and install k3s

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml
```

`site.yml` runs `common` on every node, `k3s_server` (+ `wireguard` if enabled)
on the server, `k3s_agent` on the agents, and turns the firewall on last.

## 3 — Get a kubeconfig

```bash
./scripts/get-kubeconfig.sh <server-ip> <ssh-user> homelab
kubectl --context homelab get nodes -o wide
```

## 4 — Install the platform

Pick one.

**One command (umbrella chart).** Everything — ArgoCD, monitoring, Vault,
cert-manager, Traefik, external-secrets, security — at once:

```bash
helm install platform oci://ghcr.io/kevindebenedetti/charts/platform-deployment \
  --version <latest vX.Y.Z without the v> --namespace platform --create-namespace
```

See [`charts/platform-deployment/README.md`](https://github.com/KevinDeBenedetti/k3s-lab/blob/main/charts/platform-deployment/README.md)
for the Traefik and Kyverno caveats and how to switch components off.

**GitOps (recommended once it runs).** Keep a small private repo of your own
with ArgoCD Applications that pin individual charts and carry your values:

```yaml
sources:
  - repoURL: ghcr.io/kevindebenedetti/charts
    chart: platform-traefik
    targetRevision: "X.Y.Z"          # a published version — never a range
    helm:
      valueFiles: ['$values/platform/traefik/values.yaml']
  - repoURL: https://github.com/<you>/<your-homelab-config>.git
    targetRevision: main
    ref: values
```

Upgrades are then a pin bump in that repo, reviewed like any other change.

## 5 — Keep an eye on it

Run from this repo against your own cluster or config:

| Script | Question it answers |
| ------ | ------------------- |
| `scripts/check-kyverno-crds.sh` | Are the Kyverno policies installable, present, and enforcing what the chart renders? (current kube context) |
| `scripts/check-deployed-pins.sh --applicationset <file>` | How far behind the published charts are your pins? |
| `scripts/check-deployed-charts.sh --applicationset <file>` | Do the versions you deploy carry known advisories? |

## Updating the toolkit

Pull a newer tag of this repo for the Ansible roles, and bump your chart pins
for the platform. Releases share one version (`vX.Y.Z`) across every chart; see
the [releases page](https://github.com/KevinDeBenedetti/k3s-lab/releases).
