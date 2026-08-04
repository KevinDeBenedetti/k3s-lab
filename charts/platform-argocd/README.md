# platform-argocd

Wrapper around the upstream `argo-cd` chart, sized for a single-node k3s and
with the pieces this platform does not use switched off.

| | |
|---|---|
| Subchart | `argo-cd` [`9.5.17`](https://argoproj.github.io/argo-helm) |
| Namespace (convention) | `argocd` — set at install time; this chart neither creates nor enforces it |
| Per-cluster overrides | `infra/platform/argocd/values.yaml` |

> [!IMPORTANT]
> `argo-cd.global.domain` and `argo-cd.configs.cm.url` both default to
> `argocd.example.com`. They are placeholders — set them per cluster, or the
> UI generates links to a domain you do not own.

## What this wrapper changes

- **Dex is disabled** (`dex.enabled: false`). SSO, if wanted, goes through the
  `configs.cm` OIDC settings rather than the bundled Dex.
- **`server.insecure: "false"`** — the API server terminates TLS itself rather
  than trusting an upstream proxy to have done it.
- **Resource requests and limits on all six components** (server, repoServer,
  controller, applicationSet, redis, notifications). The application controller
  is the one with real headroom (`100m`/`512Mi` up to `2` CPU / `2Gi`); it is
  what does the diffing, and starving it shows up as slow or stuck syncs rather
  than as an error.

Everything else is upstream default.

## Values

All values are passed to the subchart under the `argo-cd:` key.

| Key | Default | Note |
|---|---|---|
| `argo-cd.global.domain` | `argocd.example.com` | **override per cluster** |
| `argo-cd.configs.cm.url` | `https://argocd.example.com` | **override per cluster** |
| `argo-cd.configs.params."server.insecure"` | `"false"` | ArgoCD terminates TLS |
| `argo-cd.dex.enabled` | `false` | use `configs.cm` OIDC instead |
| `argo-cd.controller.resources` | `100m`/`512Mi` → `2`/`2Gi` | the component that needs headroom |

For the full upstream list:

```bash
helm show values oci://ghcr.io/kevindebenedetti/charts/platform-argocd
```

## See also

- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart that embeds this one
- [ArgoCD operations guide](../../docs/stack/argocd.md)
- [Upstream argo-helm chart](https://github.com/argoproj/argo-helm)
