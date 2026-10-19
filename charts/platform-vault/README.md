# platform-vault

Wrapper around the upstream HashiCorp Vault chart, configured as a **standalone,
TLS-enabled, Raft-backed** server for a single node.

| | |
|---|---|
| Subchart | `vault` [`0.32.0`](https://helm.releases.hashicorp.com) |
| Vault image | `hashicorp/vault:1.21.2` (pinned in `values.yaml`) |
| Namespace (convention) | `vault` — set at install time; this chart neither creates nor enforces it |
| Per-cluster overrides | `<your-repo>/platform/vault/values.yaml` |

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
  PVC. No audit PVC: audit goes to stdout (see below).
- **TLS is on** (`global.tlsDisable: false`); the listener terminates TLS itself
  on `:8200`.
- **The agent injector is disabled** (`injector.enabled: false`). Secrets reach
  workloads through External Secrets Operator instead, not through sidecar
  injection — so there is no `vault.hashicorp.com/agent-inject` annotation
  handling in this cluster.
- **No ingress** (`server.ingress.enabled: false`); the UI is a `ClusterIP`
  service. Reach it by port-forward, or expose it deliberately from your config repo.

## Operational notes

A fresh Vault comes up **sealed and uninitialised**. The readiness and liveness
probes are configured to accept that (`sealedcode=204&uninitcode=204`), so the
pod reports healthy while still sealed — a running pod is not evidence of a
usable Vault. Initialisation and unsealing are handled by
[`scripts/vault-init.sh`](../../scripts/vault-init.sh) (`task vault:init`), which
also creates the ESO policy and Kubernetes auth role;
[`scripts/vault-configure.sh`](../../scripts/vault-configure.sh) re-applies them.
App secrets are yours to write, from your own config repo.

Enable auditing to **stdout**, once, after unsealing:

```bash
vault audit enable file file_path=stdout
```

A file device on a volume grows without rotation until the disk fills, and
Vault then refuses every request because no audit device can write. On stdout
the log collector (Promtail → Loki in `platform-monitoring`) ships and rotates
it.

**Upgrading an install that still has the audit PVC** (charts before this
change): `volumeClaimTemplates` are immutable, so `helm upgrade` is rejected.
Switch any file audit device to stdout first, then:

```bash
kubectl -n vault delete statefulset vault --cascade=orphan   # pod keeps running
helm upgrade …                                               # recreates the StatefulSet
kubectl -n vault delete pod vault-0                          # restart on the new spec, then unseal
kubectl -n vault delete pvc audit-vault-0
```

Or keep the PVC by setting `vault.server.auditStorage.enabled: true` in your values.

The liveness probe waits 60s before its first attempt, which is deliberate
headroom for Raft recovery on a slow disk.

## Values

All values are passed to the subchart under the `vault:` key.

| Key | Default | Note |
|---|---|---|
| `vault.server.image.tag` | `1.21.4` | pinned |
| `vault.server.ha.enabled` | `false` | single node |
| `vault.server.standalone.enabled` | `true` | Raft + TLS listener, inline config |
| `vault.server.dataStorage` | `5Gi`, `local-path` | Raft data |
| `vault.server.auditStorage.enabled` | `false` | audit goes to stdout |
| `vault.server.volumes` / `volumeMounts` | `vault-tls` secret | **must exist first** |
| `vault.injector.enabled` | `false` | ESO is used instead |
| `vault.server.ingress.enabled` | `false` | expose from your config repo if wanted |
| `vault.ui.enabled` | `true` | `ClusterIP` |
| `vault.global.tlsDisable` | `false` | TLS on |

For the full upstream list:

```bash
helm show values oci://ghcr.io/kevindebenedetti/charts/platform-vault
```

## See also

- [Vault operations guide](../../docs/stack/vault.md) — init, unseal, day-2
- [`platform-external-secrets`](../platform-external-secrets/README.md) — how secrets reach workloads
- [Upstream Vault chart](https://github.com/hashicorp/vault-helm)
