# platform-external-secrets

Thin wrapper around the upstream External Secrets Operator chart. It installs
the operator only — no `SecretStore`, no `ExternalSecret`.

| | |
|---|---|
| Subchart | `external-secrets` [`2.5.0`](https://charts.external-secrets.io) |
| Namespace (convention) | `external-secrets` — set at install time; this chart neither creates nor enforces it |
| Per-cluster overrides | `infra/platform/external-secrets/values.yaml` |

> [!IMPORTANT]
> The operator is inert until something tells it where secrets live. In this
> platform that binding is created by
> [`platform-vault-seeder`](../platform-vault-seeder/README.md), which sets up
> the Vault Kubernetes auth role and policy ESO authenticates with. Installing
> this chart on its own gets you a running controller and nothing synced.

## What this wrapper changes

- **`installCRDs: true`** — the CRDs (`SecretStore`, `ClusterSecretStore`,
  `ExternalSecret`, …) install with the chart. As with cert-manager, that ties
  them to the release lifecycle: uninstalling removes every `ExternalSecret`
  object in the cluster along with the operator.
- **`fullnameOverride: external-secrets`** — stable resource names.
- **Resource requests and limits** on the controller, the webhook and the cert
  controller.

Everything else is upstream default.

## Values

All values are passed to the subchart under the `external-secrets:` key.

| Key | Default | Note |
|---|---|---|
| `external-secrets.installCRDs` | `true` | CRDs share the release lifecycle |
| `external-secrets.fullnameOverride` | `external-secrets` | stable resource names |
| `external-secrets.resources` | `10m`/`32Mi` → `64Mi` | controller |
| `external-secrets.webhook.resources` | `10m`/`16Mi` → `32Mi` | |
| `external-secrets.certController.resources` | `10m`/`32Mi` → `64Mi` | |

For the full upstream list:

```bash
helm show values oci://ghcr.io/kevindebenedetti/charts/platform-external-secrets
```

## See also

- [`platform-vault`](../platform-vault/README.md) — the backend ESO reads from
- [`platform-vault-seeder`](../platform-vault-seeder/README.md) — creates the auth role, policy and stores
- [Vault operations guide](../../docs/stack/vault.md)
- [Upstream External Secrets chart](https://github.com/external-secrets/external-secrets)
