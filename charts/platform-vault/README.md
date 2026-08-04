# platform-vault

Wrapper around the upstream HashiCorp Vault chart, configured as a **standalone,
TLS-enabled, Raft-backed** server for a single node.

| | |
|---|---|
| Subchart | `vault` [`0.32.0`](https://helm.releases.hashicorp.com) |
| Vault image | `hashicorp/vault:1.21.2` (pinned in `values.yaml`) |
| Namespace (convention) | `vault` — set at install time; this chart neither creates nor enforces it |
| Per-cluster overrides | `infra/platform/vault/values.yaml` |

> [!WARNING]
> **The `vault-tls` secret must exist before the pod is scheduled.** The
> listener reads its certificate from `/vault/userconfig/vault-tls`, and the
> chart mounts the `vault-tls` secret there unconditionally. Without it the pod
> does not start — create it first (a cert-manager `Certificate` in the `vault`
> namespace, or by hand). This is the single most common way to get a Vault
> that never comes up.

## Topology

- **Standalone, not HA** (`server.ha.enabled: false`,
  `server.standalone.enabled: true`) — one node, one Vault.
- **Raft storage** at `/vault/data`, node ID `vault-0`, on a 5Gi `local-path`
  PVC. Audit logs get their own 2Gi PVC.
- **TLS is on** (`global.tlsDisable: false`); the listener terminates TLS itself
  on `:8200`.
- **The agent injector is disabled** (`injector.enabled: false`). Secrets reach
  workloads through External Secrets Operator instead, not through sidecar
  injection — so there is no `vault.hashicorp.com/agent-inject` annotation
  handling in this cluster.
- **No ingress** (`server.ingress.enabled: false`); the UI is a `ClusterIP`
  service. Reach it by port-forward, or expose it deliberately from `infra`.

## Operational notes

A fresh Vault comes up **sealed and uninitialised**. The readiness and liveness
probes are configured to accept that (`sealedcode=204&uninitcode=204`), so the
pod reports healthy while still sealed — a running pod is not evidence of a
usable Vault. Initialisation and unsealing are handled by
[`scripts/vault-init.sh`](../../scripts/vault-init.sh); the seeding of policies,
auth roles and app secrets is [`platform-vault-seeder`](../platform-vault-seeder/README.md).

The liveness probe waits 60s before its first attempt, which is deliberate
headroom for Raft recovery on a slow disk.

## Values

All values are passed to the subchart under the `vault:` key.

| Key | Default | Note |
|---|---|---|
| `vault.server.image.tag` | `1.21.2` | pinned |
| `vault.server.ha.enabled` | `false` | single node |
| `vault.server.standalone.enabled` | `true` | Raft + TLS listener, inline config |
| `vault.server.dataStorage` | `5Gi`, `local-path` | Raft data |
| `vault.server.auditStorage` | `2Gi`, `local-path` | audit log |
| `vault.server.volumes` / `volumeMounts` | `vault-tls` secret | **must exist first** |
| `vault.injector.enabled` | `false` | ESO is used instead |
| `vault.server.ingress.enabled` | `false` | expose from `infra` if wanted |
| `vault.ui.enabled` | `true` | `ClusterIP` |
| `vault.global.tlsDisable` | `false` | TLS on |

For the full upstream list:

```bash
helm show values oci://ghcr.io/kevindebenedetti/charts/platform-vault
```

## See also

- [Vault operations guide](../../docs/stack/vault.md) — init, unseal, day-2
- [`platform-vault-seeder`](../platform-vault-seeder/README.md) — policies, auth roles, app secrets
- [`platform-external-secrets`](../platform-external-secrets/README.md) — how secrets reach workloads
- [Upstream Vault chart](https://github.com/hashicorp/vault-helm)
