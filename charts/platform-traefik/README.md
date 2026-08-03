# platform-traefik

Wrapper around the upstream Traefik chart, with defaults suited to a
single-node k3s: HTTP → HTTPS redirect, CRD + Ingress providers, dashboard
disabled, resource limits sized for a small node.

| | |
|---|---|
| Subchart | `traefik` [`41.1.0`](https://traefik.github.io/charts) |
| Deployed proxy | `docker.io/traefik:v3.7.10` (**pinned** via `image.tag` since 2026-08-03, see below) |
| Per-cluster overrides | `infra/platform/traefik/values.yaml` |

> The two versions in that table are copies of `Chart.lock` and of the value
> `lib/traefik-pin.sh` resolves. They are **verified, not generated**:
> `scripts/check-traefik-image.sh` fails if either falls out of step, so a
> subchart bump is not finished until this page agrees with it. The advisory
> table further down intentionally names older versions and is not checked.

> [!IMPORTANT]
> Before adding `traefik.image.tag` or bumping the subchart, read
> [The `traefik.io/proxy-max-version` constraint](#the-traefikioproxy-max-version-constraint).
> This ceiling is invisible from the parent chart and has already caused two
> outages.

## The `traefik.io/proxy-max-version` constraint

### What it is

The upstream Traefik chart declares, **in its `Chart.yaml` annotations**, the
range of proxy versions it knows how to configure:

```yaml
# charts/traefik/Chart.yaml (subchart 41.1.0)
annotations:
  traefik.io/proxy-min-version: v3.6.0
  traefik.io/proxy-max-version: v3.7.9
appVersion: v3.7.9
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
3. otherwise the subchart's `.Chart.AppVersion` (so `v3.7.9` here).

Step 2 is where we sit today (`image.tag: v3.7.10`, re-added 2026-08-03 —
three advisories cover `<= v3.7.9` and no upstream chart ships v3.7.10 yet).
Step 3 is the resting state whenever upstream is current. The pinless state is
also a trap in the other direction: *forgetting* `image.tag` back when it was
load-bearing raised no error at all, it just silently downgraded the proxy.
`lib/traefik-pin.sh` mirrors steps 2 and 3 so that both checks always speak
about the version really shipped, whether or not a pin exists.

| | `traefik.image.tag` set | not set |
|---|---|---|
| Version deployed | the pin | subchart appVersion |
| What the checks compare against | the pin | subchart appVersion |
| When it applies | an advisory is ahead of upstream (**today**) | upstream is current |

### What fails, and what only warns

Since subchart **41.0.0**, the guard has been relaxed
(`relax max-version guard to warn on minor/patch, fail only on major mismatch`):

| Situation | Effect |
|---|---|
| Proxy below `proxy-min-version` | **`fail`** — render impossible |
| Proxy whose **major** exceeds `proxy-max-version` | **`fail`** — render impossible |
| Proxy at a minor/patch above the max | warning in `NOTES.txt` only |

Since the pin was dropped we no longer trip any of these: the proxy *is* the
subchart's appVersion, so it sits exactly on the ceiling. Between 2026-07-22 and
2026-07-30 we were in the third row.

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

### Procedure — pinning the proxy ahead of the subchart

Needed when an advisory lands before upstream ships the fix. Prefer bumping the
subchart (next section); pin only when upstream has nothing newer to offer.

1. Check that the gap is only a minor/patch one. **A major above the ceiling
   cannot be worked around**: the subchart has to be bumped.
2. Add `traefik.image.tag` to [`values.yaml`](values.yaml), documenting the
   advisory or the reason right above it. Both checks pick the pin up
   automatically — it takes precedence over the subchart's appVersion.
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
3. Read the new `proxy-min-version` / `proxy-max-version` annotations, and the
   new `appVersion`: with no pin set, that appVersion *is* the proxy you are
   about to deploy.
4. If a pin is currently set, check whether the new appVersion has caught up
   with it — if so, drop the pin rather than carrying it forward.
5. `./scripts/check-traefik-image.sh` must pass, and
   `./scripts/check-traefik-advisories.sh` must come back clean on the version
   the bump lands on.

## Proxy version history — why there was a pin

The proxy version is a **security decision**, not a preference: for most of
July 2026 the upstream chart lagged behind the proxy's own fixes, so
`traefik.image.tag` was carried here to get ahead of it.

| Advisory | Affected versions | Patched in |
|---|---|---|
| `GHSA-cxjq-mrr5-89rv` — auth bypass via path traversal in `ReplacePathRegex` | v3.7.0 – v3.7.6 | v3.7.7 |
| `GHSA-3ccp-42pg-hgv6` — cross-user response poisoning via proxied CONNECT | <= v3.7.8 | v3.7.9 |
| `GHSA-fgjj-px3w-67xx` (HIGH) — Gateway API route identity collision, cross-namespace backend hijacking | v3.7.0 – v3.7.9 | v3.7.10 |
| `GHSA-62fc-8686-hfmq` — `allowCrossNamespace=false` bypass via `@kubernetescrd` TraefikService backendRef | v3.7.0 – v3.7.9 | v3.7.10 |
| `GHSA-6765-c87h-8mrf` — BasicAuth singleflight key collision, identity spoofing | v3.7.0 – v3.7.9 | v3.7.10 |

`GHSA-8rxv-jg7p-wvg3`, which motivated the original pin, **does not concern
us**: it targets the `kubernetesIngressNGINX` provider, which we do not enable.

Chart **41.1.0** (2026-07-30) ships appVersion `v3.7.9` — the exact version the
pin was then forcing — so the pin was dropped on 2026-07-30: it had become a
duplicate statement of upstream's own value, and a duplicate that only drifts.

It came **back** on 2026-08-03, when the three v3.7.10 advisories landed with
no upstream chart shipping the fix (41.1.1 still declares appVersion v3.7.9) —
the exact scenario the escape hatch exists for. Drop it again at the first
subchart bump whose appVersion reaches v3.7.10.

> [!WARNING]
> Dropping the pin removed a redundancy, **not** the risk. The version still
> goes stale silently, and now nothing in this repository even names it:
> `GHSA-3ccp` was published **12 days** after we froze v3.7.8, with nothing to
> signal it, and an upstream chart sitting on a vulnerable appVersion would be
> just as quiet. Always query the **repository** advisories, never the global
> database — see [Looking Traefik advisories up](#looking-traefik-advisories-up):
>
> ```bash
> gh api /repos/traefik/traefik/security-advisories \
>   --jq '.[] | {ghsa_id, severity, published_at, vulnerable: [.vulnerabilities[].vulnerable_version_range]}'
> ```
>
> `scripts/check-traefik-advisories.sh` automates exactly this comparison
> against the version we really deploy, and the `traefik-advisories` workflow
> runs it daily.

> [!CAUTION]
> **"What this repo deploys" and "what the cluster runs" are different
> questions.** The cluster resolves a *published* chart, pinned in
> `infra/argocd/applicationsets/platform.yaml`, which can lag this source by any
> number of releases. Between 2026-07-27 and 2026-08-01 the two disagreed: the
> repository was on v3.7.9 and the daily watch reported clean every morning,
> while production ran v3.7.8 under `GHSA-3ccp` because infra still pinned the
> previous chart. Fixing the version here does **not** fix production — it has
> to be released *and* pinned. `scripts/check-deployed-traefik.sh` is the check
> that asks the second question.

## Looking Traefik advisories up

Getting this wrong has already cost us a wrong conclusion recorded for nine
days: a 404 was read as "that CVE is made up", and the mistaken finding was then
propagated into a triage comment in `infra`. Two rules.

**1. To list what affects Traefik, query the repository, not the global
database.** Only the advisories that were assigned a CVE ID are mirrored
globally; the ones without one exist *only* on the repository endpoint:

| Advisory | CVE | `GET /advisories/<GHSA>` |
|---|---|---|
| `GHSA-xf64-8mw2-4gr2` | CVE-2026-48020 | found |
| `GHSA-6jwx-7vp4-9847` | CVE-2026-40912 | found |
| `GHSA-6384-m2mw-rf54` | CVE-2026-35051 | found |
| `GHSA-3ccp-42pg-hgv6` | *none* | **404** |
| `GHSA-cxjq-mrr5-89rv` | *none* | **404** |
| `GHSA-8rxv-jg7p-wvg3` | *none* | **404** |

So a 404 there proves nothing at all — and `GHSA-3ccp`, the one that mattered
most to us, is in the 404 column.

**2. To go from a CVE ID to an advisory, use the query parameter.** The path
form takes a *GHSA* ID, so handing it a CVE returns 404 — which reads exactly
like "this CVE does not exist", and is what misled us:

```bash
gh api "/advisories?cve_id=CVE-2026-48020"   # ✅ correct
gh api /advisories/CVE-2026-48020            # ❌ always 404, whatever the CVE
```

## Values

All values are passed to the subchart under the `traefik:` key. See
[`values.yaml`](values.yaml) for the defaults, and
`helm show values oci://ghcr.io/kevindebenedetti/charts/platform-traefik` for the
full list.

| Key | Default | Note |
|---|---|---|
| `traefik.image.tag` | *unset* | escape hatch only — see above |
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
- [`scripts/check-traefik-advisories.sh`](../../scripts/check-traefik-advisories.sh) — advisory watch, on the version *this repo* would deploy
- [`scripts/check-deployed-traefik.sh`](../../scripts/check-deployed-traefik.sh) — advisory watch, on the version the *cluster is running*
- [`lib/traefik-pin.sh`](../../lib/traefik-pin.sh) — resolves the effective proxy version for both
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart that embeds this one
- [Upstream Traefik chart](https://github.com/traefik/traefik-helm-chart)
