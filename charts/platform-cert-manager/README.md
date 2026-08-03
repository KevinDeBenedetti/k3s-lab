# platform-cert-manager

Thin wrapper around the upstream `cert-manager` chart: CRDs on, resources sized
for a small node. It deliberately ships **no issuers**.

| | |
|---|---|
| Subchart | `cert-manager` [`v1.20.3`](https://charts.jetstack.io) |
| Namespace | `cert-manager` |
| Per-cluster overrides | `infra/platform/cert-manager/values.yaml` |

> [!IMPORTANT]
> No `ClusterIssuer` is created here. cert-manager alone issues nothing — an
> issuer carries an ACME account and a DNS-01 or HTTP-01 solver, both of which
> are cluster-specific (email, provider, API token). They belong in `infra`.
> A `Certificate` with no matching issuer stays `Pending` indefinitely rather
> than failing loudly, which is what makes this worth stating.

## What this wrapper changes

- **`crds.enabled: true`** — the CRDs install with the chart rather than being
  applied separately. This matters at uninstall time: removing the release
  removes the CRDs, and with them every `Certificate` and `Issuer` in the
  cluster.
- **`fullnameOverride: cert-manager`** — keeps resource names predictable so
  that issuers and annotations elsewhere can reference them without depending on
  the release name.
- **Resource requests and limits** on the controller, the webhook and the
  cainjector.

Everything else is upstream default.

## Values

All values are passed to the subchart under the `cert-manager:` key.

| Key | Default | Note |
|---|---|---|
| `cert-manager.crds.enabled` | `true` | CRDs share the release lifecycle |
| `cert-manager.fullnameOverride` | `cert-manager` | stable resource names |
| `cert-manager.resources` | `10m`/`32Mi` → `64Mi` | controller |
| `cert-manager.webhook.resources` | `10m`/`16Mi` → `32Mi` | |
| `cert-manager.cainjector.resources` | `10m`/`32Mi` → `64Mi` | |

For the full upstream list:

```bash
helm show values oci://ghcr.io/kevindebenedetti/charts/platform-cert-manager
```

## See also

- [cert-manager operations guide](../../docs/stack/cert-manager.md) — issuers, DNS-01, troubleshooting
- [`platform-traefik`](../platform-traefik/README.md) — consumer of the certificates
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart
- [Upstream cert-manager chart](https://github.com/cert-manager/cert-manager)
