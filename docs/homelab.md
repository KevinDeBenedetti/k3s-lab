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

`ansible/inventory/` is gitignored: it holds your node addresses. Set
`k3s_version` there (it is **required**: the roles ship no default, so a run can
never downgrade a node). Role defaults (`ansible/roles/*/defaults/main.yml`)
cover the rest; override what you need in
`ansible/inventory/group_vars/all.yml`, typically `k3s_ufw_allow_from` (your
LAN CIDR).

## 2 — Provision the nodes and install k3s

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml
```

`site.yml` runs `common` on every node, `k3s_server` (+ `wireguard` if enabled)
on the server, `k3s_agent` on the agents, and turns the firewall on last. It
writes the kubeconfig to `./kubeconfig.yaml` in the directory you run it from.

### From your own config repo

Keep the inventory in your own repository and install the roles from a pinned
release as the `kevindebenedetti.k3s_lab` collection, instead of copying them:

```yaml
# requirements.yml in your repo
collections:
  - name: https://github.com/KevinDeBenedetti/k3s-lab.git#/ansible/
    type: git
    version: vX.Y.Z
```

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.yml kevindebenedetti.k3s_lab.site
```

The scripts and taskfiles work from a pinned checkout too. They read `.env`
from the directory they run from (your repo), not from the checkout. Set
`K3S_LAB_ENV_FILE` to point at another file.

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

## 5 — Check the install

```bash
./scripts/check-kyverno-crds.sh   # Kyverno policies installed and enforcing what the chart renders
```

Day-2 work — deploying apps, bumping pins, watching drift and advisories on what
the cluster runs, shipping backups off-site — lives in your own config repo, not
here. Renovate (`docker` datasource on `ghcr.io/kevindebenedetti/charts/*`) is
the simplest way to get pin bumps as PRs there.

## Updating the toolkit

Pull a newer tag of this repo for the Ansible roles, and bump your chart pins
for the platform. Releases share one version (`vX.Y.Z`) across every chart; see
the [releases page](https://github.com/KevinDeBenedetti/k3s-lab/releases).
