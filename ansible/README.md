# kevindebenedetti.k3s_lab

Ansible collection of [k3s-lab](https://github.com/KevinDeBenedetti/k3s-lab):
roles and playbooks that take fresh Debian/Ubuntu machines to a running k3s
cluster.

## Install

Pin the collection to a release tag of the repository:

```bash
ansible-galaxy collection install \
  "git+https://github.com/KevinDeBenedetti/k3s-lab.git#/ansible/,vX.Y.Z"
```

Or in your own `requirements.yml`:

```yaml
collections:
  - name: https://github.com/KevinDeBenedetti/k3s-lab.git#/ansible/
    type: git
    version: vX.Y.Z
```

## Use

```bash
ansible-playbook -i inventory/hosts.yml kevindebenedetti.k3s_lab.site
```

| Playbook | Does |
| --- | --- |
| `kevindebenedetti.k3s_lab.site` | Every node: base setup, k3s server, agents, kubeconfig, firewall |
| `kevindebenedetti.k3s_lab.k3s-server` | The server node only |
| `kevindebenedetti.k3s_lab.k3s-agent` | Join agent nodes to an existing server |
| `kevindebenedetti.k3s_lab.reset` | Uninstall k3s from every node (destructive) |

Roles: `common`, `k3s_server`, `k3s_agent`, `wireguard`, `ufw_enable`, usable
from your own playbooks as `kevindebenedetti.k3s_lab.<role>`.

Required in the inventory: `k3s_version` (an exact release such as
`v1.32.13+k3s1`). The roles ship no default for it. Inventory groups are
`k3s_servers` (one host) and `k3s_agents`.

The kubeconfig fetched by `site` is written to `./kubeconfig.yaml` in the
directory you run `ansible-playbook` from (`k3s_kubeconfig_dest` to change it,
`k3s_kubeconfig_fetch: false` to skip).

## Maintainers

`ansible/` is the collection root: `roles/` and `playbooks/` sit where a
collection expects them, so the same tree runs from a checkout
(`ansible-playbook ansible/playbooks/site.yml`) and as an installed collection.
Inside the collection, playbooks resolve their short role names to this
collection's roles, because ansible-core makes a collection playbook's own
collection the default one.

`galaxy.yml`'s `version` is bumped by release-please with the rest of the
repository; never edit it by hand. It carries no comments because
release-please rewrites the file.

Full documentation: <https://kevindebenedetti.github.io/k3s-lab/>
