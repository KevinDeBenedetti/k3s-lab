# platform-traefik

Wrapper around the upstream Traefik chart, with defaults suited to a
single-node k3s: HTTP → HTTPS redirect, CRD + Ingress providers, dashboard
disabled, resource limits sized for a small node.

| | |
|---|---|
| Subchart | `traefik` [`41.0.2`](https://traefik.github.io/charts) |
| Deployed proxy | `docker.io/traefik:v3.7.9` (pinned, see below) |
| Per-cluster overrides | `infra/platform/traefik/values.yaml` |

> [!IMPORTANT]
> Before touching `traefik.image.tag` or bumping the subchart, read
> [The `traefik.io/proxy-max-version` constraint](#the-traefikioproxy-max-version-constraint).
> This ceiling is invisible from the parent chart and has already caused two
> outages.

## The `traefik.io/proxy-max-version` constraint

### What it is

The upstream Traefik chart declares, **in its `Chart.yaml` annotations**, the
range of proxy versions it knows how to configure:

```yaml
# charts/traefik/Chart.yaml (subchart 41.0.2)
annotations:
  traefik.io/proxy-min-version: v3.6.0
  traefik.io/proxy-max-version: v3.7.6
appVersion: v3.7.6
```

`templates/requirements.yaml` compares the proxy version against that range on
every render. That is where the trap lies: **none of this is visible from
`charts/platform-traefik/`**. Neither the annotation nor the `fail` shows up
until you open the subchart tarball. `helm lint` does not see them either, since
it does not download dependencies.

### How the proxy version is determined

`traefik.proxyVersion` (in the subchart's `_helpers.tpl`) resolves, in order:

1. `versionOverride` if set — **it short-circuits everything else**;
2. otherwise `image.tag`;
3. otherwise the subchart's `.Chart.AppVersion` (so `v3.7.6` here).

In other words, forgetting `image.tag` raises no error at all: you silently fall
back to the subchart's appVersion. That is exactly what the `traefik-image` CI
job (`scripts/check-traefik-image.sh`) exists to catch.

### What fails, and what only warns

Since subchart **41.0.0**, the guard has been relaxed
(`relax max-version guard to warn on minor/patch, fail only on major mismatch`):

| Situation | Effect |
|---|---|
| Proxy below `proxy-min-version` | **`fail`** — render impossible |
| Proxy whose **major** exceeds `proxy-max-version` | **`fail`** — render impossible |
| Proxy at a minor/patch above the max (our case: v3.7.9 > v3.7.6) | warning in `NOTES.txt` only |

Before 41.0.0, the third row was a `fail` too. That is the root cause of the two
outages on **2026-07-20** and **2026-07-21**: `platform-traefik` was published as
0.13.0, 0.13.1 and then 0.13.2 in an unrenderable state without any CI
complaining — `helm lint` alone does not download dependencies, so the
subchart's `fail` was never reached. Fixed since by `run-template: true` in
`.github/workflows/ci.yml`.

### Why `versionOverride` is no longer used

`versionOverride: v3.7.4` was the 2026-07-22 escape hatch: it made the chart lie
about the proxy version to get back under the ceiling, while `image.tag` really
deployed v3.7.8.

It was **removed** when moving to 41.0.2 (2026-07-28), and should not come back
without a precise reason. The hidden cost: `requirements.yaml` uses that version
not only for the ceiling, but also for around twenty feature-gating guards
(`accessLog.dualOutput` >= v3.7.0, `providers.*.crossProviderNamespaces` >=
v3.7.1, `http.underscoreHeadersStrategy` >= v3.7.6, …). Lying about the version
makes the chart take the wrong decision on all of those at once.

### Procedure — raising the proxy above the ceiling

1. Check that the gap is only a minor/patch one. **A major above the ceiling
   cannot be worked around**: the subchart has to be bumped.
2. Update `traefik.image.tag` in [`values.yaml`](values.yaml), documenting the
   advisory or the reason right above it.
3. Render and verify the image actually produced:

   ```bash
   ./scripts/check-traefik-image.sh
   ```

4. Replay the check with the cluster overlay:

   ```bash
   ./scripts/check-traefik-image.sh -- -f ../infra/platform/traefik/values.yaml
   ```

### Procedure — bumping the subchart

1. Bump `version` in [`Chart.yaml`](Chart.yaml), then
   `helm dependency update charts/platform-traefik`.
2. Read the upstream changelog for **values breakages**: the schema declares
   `additionalProperties: false`, so a renamed key is not ignored, it is
   **fatal**. 41.0.0 renamed `logs.general` → `log` and `logs.access` →
   `accessLog` this way.
3. Read the new `proxy-min-version` / `proxy-max-version` annotations: that is
   the only way to know whether the `image.tag` pin remains tenable.
4. `./scripts/check-traefik-image.sh` must pass.

## The `traefik.image.tag` pin

This is a **security decision**, not a preference: the upstream chart is
consistently behind on proxy fixes.

| Advisory | Affected versions | Patched in |
|---|---|---|
| `GHSA-cxjq-mrr5-89rv` — auth bypass via path traversal in `ReplacePathRegex` | v3.7.0 – v3.7.6 | v3.7.7 |
| `GHSA-3ccp-42pg-hgv6` — cross-user response poisoning via proxied CONNECT | <= v3.7.8 | v3.7.9 |

`GHSA-8rxv-jg7p-wvg3`, which motivated the original pin, **does not concern
us**: it targets the `kubernetesIngressNGINX` provider, which we do not enable.

> [!WARNING]
> This pin goes stale silently. `GHSA-3ccp` was published **12 days** after we
> froze v3.7.8, with nothing to signal it. Traefik advisories are not in
> GitHub's global database — `GET /advisories/<GHSA>` returns 404 — so the
> repository has to be queried:
>
> ```bash
> gh api /repos/traefik/traefik/security-advisories \
>   --jq '.[] | {ghsa_id, severity, published_at, vulnerable: [.vulnerabilities[].vulnerable_version_range]}'
> ```
>
> `scripts/check-traefik-advisories.sh` automates exactly this comparison, and
> the `traefik-advisories` workflow runs it daily.

The pin can only be dropped once an upstream chart ships a proxy at least as
recent — tracked in [`TODO.md`](../../TODO.md).

## Values

All values are passed to the subchart under the `traefik:` key. See
[`values.yaml`](values.yaml) for the defaults, and
`helm show values oci://ghcr.io/kevindebenedetti/charts/platform-traefik` for the
full list.

| Key | Default | Note |
|---|---|---|
| `traefik.image.tag` | `v3.7.9` | security pin — see above |
| `traefik.ingressRoute.dashboard.enabled` | `false` | exposed separately if needed |
| `traefik.ports.web` | `8000`, exposed as `80` | redirects to `websecure` |
| `traefik.ports.websecure` | `8443`, exposed as `443` | |
| `traefik.providers.kubernetesCRD.enabled` | `true` | `allowCrossNamespace: true` |
| `traefik.providers.kubernetesIngress.enabled` | `true` | |
| `traefik.service.type` | `LoadBalancer` | klipper-lb on k3s |
| `traefik.log.level` | `INFO` | `log`, not `logs.general` (41.0.0 breakage) |
| `traefik.accessLog.enabled` | `true` | `accessLog`, not `logs.access` |

## See also

- [`scripts/check-traefik-image.sh`](../../scripts/check-traefik-image.sh) — render conformance check
- [`scripts/check-traefik-advisories.sh`](../../scripts/check-traefik-advisories.sh) — advisory watch
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart that embeds this one
- [Upstream Traefik chart](https://github.com/traefik/traefik-helm-chart)
