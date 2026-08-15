# platform-security

Runtime security and admission control: Falco, Tetragon, Trivy Operator and
Kyverno, plus six Kyverno cluster policies this chart owns.

| | |
|---|---|
| Subcharts | `falco` `9.0.0`, `falcosidekick` `0.13.1`, `tetragon` `1.7.0`, `trivy-operator` `0.32.1`, `kyverno` `3.8.1` |
| Namespace (convention) | `security` — set at install time; this chart neither creates nor enforces it |
| Per-cluster overrides | `infra/platform/security/values.yaml` |

## Installing on a cluster without the Kyverno CRDs

The six ClusterPolicies below and the Kyverno engine that evaluates them
cannot be created by the same Helm release on a cluster that does not already
have the Kyverno CRDs. Helm builds and validates **every** rendered manifest
against the API server before applying any of it, so a `ClusterPolicy` whose
kind is not yet registered fails the whole install:

```
no matches for kind "ClusterPolicy" in version "kyverno.io/v1"
ensure CRDs are installed first
```

This is not a packaging mistake here: Kyverno delivers its CRDs through a
`crds` subchart rendered from `templates/` rather than from a `crds/`
directory — deliberately, since Helm never upgrades what it finds in `crds/`.
Upstream answers the same constraint by publishing `kyverno` and
`kyverno-policies` as two separate charts.

So on a **blank** cluster, install in two steps:

```bash
helm install security . --set kyvernoPolicies.enabled=false
helm upgrade security . --reuse-values --set kyvernoPolicies.enabled=true
```

`kyvernoPolicies.enabled` defaults to **`true`** on purpose: everywhere the
CRDs already exist — re-installs, upgrades, and ArgoCD, which retries until
they do — the policies must ship with the chart. A security chart that
silently enforces nothing is a worse outcome than one that fails loudly. The
`platform-deployment` umbrella is the one place that flips it to `false`, for
its first install only, and its `NOTES.txt` says so every time.

> [!IMPORTANT]
> **The six Kyverno policies default to `Audit`, not `Enforce`.** They record
> violations in a PolicyReport and let the pod through. Nothing is rejected at
> admission until you set `kyvernoPolicies.failureAction: Enforce`.
>
> This was the reverse until 2026-08-05, when an audit found the policies had
> shipped hardcoded to `Enforce` while being installed on no cluster at all — so
> the setting had never been exercised against a real workload. `Audit` first is
> the only way to learn what a cluster actually violates before it starts losing
> pods over it.

## Kyverno policies

All six are `ClusterPolicy`, gated collectively on `kyverno.enabled` **and**
`kyvernoPolicies.enabled` — the engine and the policies are separate switches,
for the reason above. Their failure action comes from a single value:

```yaml
kyvernoPolicies:
  failureAction: Audit   # or Enforce
```

It renders into each rule's `validate.failureAction`, not the chart-level
`spec.validationFailureAction` that Kyverno 3.8 deprecated. The old value key
`kyvernoPolicies.validationFailureAction` is still accepted as a deprecated
alias so existing overrides do not silently fall back to the default.

### Checking the policies actually landed

```bash
scripts/check-kyverno-crds.sh              # CRDs + the policies really exist
scripts/check-kyverno-crds.sh --crds-only  # installability only
```

Rendering six policies is not the same as having six policies. The chart can be
correct, the render valid, and the cluster still hold none of them — either
because the Kyverno CRDs are not installed yet (the first-install order below),
or because something upstream refused the kind. The second is not theoretical:
in August 2026 the ArgoCD AppProject did not whitelist `kyverno.io/ClusterPolicy`
and rejected all six for 32 hours, with the Application reporting
`OutOfSync`/`Healthy` throughout. This script is the only check here that looks
at a cluster, so it is the only one that can tell the difference.

### Going from Audit to Enforce

Deploy with `Audit`, let the background scan run, then read what actually
violates:

```bash
kubectl get policyreport -A
kubectl get clusterpolicyreport
```

Fix or exclude each violation, then flip to `Enforce`. Treat it as a per-policy
decision rather than one switch for the whole set — `require-ro-rootfs` and
`require-non-root` are the two that most workloads fail first, and they can stay
on `Audit` long after the other four are enforced. Per-policy overrides go
through Kyverno's own `failureActionOverrides`, alongside `failureAction` on
the rule's `validate` block.

Every policy carries its **own** exclusion list — they are not uniform, and the
differences are deliberate: each one exempts exactly the platform namespaces
whose components cannot satisfy that particular rule. `kube-system` and
`kyverno` are the only two excluded everywhere.

| Policy | Requires | Also excluded |
|---|---|---|
| `disallow-latest-tag` | an explicit image tag, not `:latest` | — |
| `disallow-privilege-escalation` | `allowPrivilegeEscalation: false` | `vault` |
| `require-non-root` | `securityContext.runAsNonRoot: true` | `argocd`, `vault`, `ingress` |
| `require-pod-resources` | CPU and memory requests **and** limits | `argocd`, `cert-manager`, `external-secrets`, `vault` |
| `restrict-capabilities` | all capabilities dropped | `argocd`, `vault`, `ingress`, `cert-manager`, `monitoring` |
| `require-ro-rootfs` | read-only root filesystem | `argocd`, `vault`, `monitoring`, `external-secrets`, `cert-manager`, `ingress` |

Read that column as a map of which components fall short of which control: the
further down the table, the more of the platform has to be exempted. The lists
live in the policy templates, so widening one means editing the template, not
the values.

There is no per-policy toggle: either switch set to `false` removes all six —
`kyvernoPolicies.enabled: false` keeps the engine and drops the policies,
`kyverno.enabled: false` drops both.

## The other three tools

- **Falco** (`modern_ebpf` driver) — syscall-level runtime detection. The
  heaviest component here (`200m`/`256Mi` up to `400m`/`512Mi`).
- **Falcosidekick** is **disabled by default**, because it is only useful once
  `falcosidekick.config.webhook.address` points somewhere real (Slack,
  PagerDuty, …). Enabling it without an address gets you a pod that forwards
  alerts nowhere.
- **Tetragon** — eBPF process and network observability.
- **Trivy Operator** — continuous vulnerability scanning, with
  `ignoreUnfixed: true` (findings with no available fix are not reported) and a
  24h scan interval and report TTL. The node collector is **off**, so this scans
  workloads rather than the host.

  **Disabled by default since 2026-08-05.** infra installs the upstream
  `aquasecurity/trivy-operator` chart directly into `trivy-system` via its
  `platform-vendor` ApplicationSet, and two operators reconciling the same
  `VulnerabilityReport` CRDs is not a configuration worth having. Set
  `trivy-operator.enabled: true` only on a cluster where nothing else provides
  it.

Kyverno exposes metrics with a `ServiceMonitor` labelled `release: prometheus`
to match the Prometheus selector in
[`platform-monitoring`](../platform-monitoring/README.md), and only emits events
for policy *failures* (`generateSuccessEvents: false`) to keep the event stream
readable.

## Values

| Key | Default | Note |
|---|---|---|
| `falco.enabled` | `true` | `modern_ebpf` driver |
| `falcosidekick.enabled` | `false` | needs `config.webhook.address` first |
| `tetragon.enabled` | `true` | |
| `trivy-operator.enabled` | `false` | infra deploys it upstream; `ignoreUnfixed: true`, 24h interval when on |
| `trivy-operator.nodeCollector.enabled` | `false` | workloads only |
| `kyverno.enabled` | `true` | the admission engine; `false` also drops the policies |
| `kyvernoPolicies.enabled` | `true` | the six policies; needs the CRDs to already exist |
| `kyvernoPolicies.failureAction` | `Audit` | `Enforce` rejects non-compliant pods at admission; `validationFailureAction` still accepted as a deprecated alias |
| `kyverno.metrics.serviceMonitor.enabled` | `true` | `release: prometheus` |
| `kyverno.generateSuccessEvents` | `false` | failures only |

## See also

- [`platform-base`](../platform-base/README.md) — Pod Security Standards labels, the namespace-level equivalent
- [`platform-monitoring`](../platform-monitoring/README.md) — dashboards for Falco, Tetragon and Trivy
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart
