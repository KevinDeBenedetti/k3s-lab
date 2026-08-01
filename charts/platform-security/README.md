# platform-security

Runtime security and admission control: Falco, Tetragon, Trivy Operator and
Kyverno, plus six Kyverno cluster policies this chart owns.

| | |
|---|---|
| Subcharts | `falco` `9.0.0`, `falcosidekick` `0.13.1`, `tetragon` `1.7.0`, `trivy-operator` `0.32.1`, `kyverno` `3.8.1` |
| Namespace | `security` |
| Per-cluster overrides | `infra/platform/security/values.yaml` |

> [!WARNING]
> **The six Kyverno policies are `Enforce`, not `Audit`.** Enabling Kyverno does
> not merely report violations — it *rejects* non-compliant pods at admission.
> Deploy this into a cluster with existing workloads and some of them will stop
> being schedulable. Read the table below first.

## Kyverno policies

All six are `ClusterPolicy` with `validationFailureAction: Enforce`, gated
collectively on `kyverno.enabled`.

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

There is no per-policy toggle: `kyverno.enabled: false` removes all six.

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
| `trivy-operator.enabled` | `true` | `ignoreUnfixed: true`, 24h interval |
| `trivy-operator.nodeCollector.enabled` | `false` | workloads only |
| `kyverno.enabled` | `true` | **enables all six Enforce policies** |
| `kyverno.metrics.serviceMonitor.enabled` | `true` | `release: prometheus` |
| `kyverno.generateSuccessEvents` | `false` | failures only |

## See also

- [`platform-base`](../platform-base/README.md) — Pod Security Standards labels, the namespace-level equivalent
- [`platform-monitoring`](../platform-monitoring/README.md) — dashboards for Falco, Tetragon and Trivy
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart
