# platform-monitoring

Observability stack — Grafana, Loki, Promtail and Prometheus — assembled from
four upstream charts and trimmed to fit an 8 GB single-node VPS.

| | |
|---|---|
| Subcharts | `grafana` `10.5.15`, `loki` `7.0.0`, `promtail` `6.17.1`, `kube-prometheus-stack` `86.1.0` |
| Namespace | `monitoring` |
| Per-cluster overrides | `infra/platform/monitoring/values.yaml` |

> [!IMPORTANT]
> **`grafana-admin-secret` must exist before install.** Grafana is configured
> with `admin.existingSecret`, so the chart creates no password of its own and
> the deployment blocks until the secret is there. It needs `username` and
> `password` keys.

## How the pieces fit

Two upstream charts both want to ship Grafana and Alertmanager, so this wrapper
picks a winner:

- **Grafana comes from the standalone `grafana` chart**;
  `kube-prometheus-stack.grafana.enabled` is **`false`**.
- **Alertmanager is off entirely** (`kube-prometheus-stack.alertmanager.enabled:
  false`) — there is no alert routing in this stack today.

Getting that wrong gives you two Grafanas fighting over the same service name,
which is why it is stated here rather than left to be discovered.

**Loki runs in `SingleBinary` mode**: `backend`, `read` and `write` are scaled to
zero, the gateway and both caches are disabled. It is one pod with an 8Gi PVC and
a filesystem object store — not a scalable deployment, and not intended to be.
`auth_enabled: true` means queries must carry a tenant header.

**Promtail** ships node logs to `http://loki.monitoring.svc.cluster.local:3100`.

## Dashboards and datasources

This chart owns its templates: Loki and Prometheus datasources, plus dashboards
for Kubernetes, logs, self-monitoring, Falco, Tetragon and Trivy. They are
delivered through the Grafana sidecar (`grafana_dashboard` label).

The three security dashboards are gated, because a dashboard for a component you
did not deploy is worse than no dashboard:

| Toggle | Default | Turn off when |
|---|---|---|
| `dashboards.falco.enabled` | `true` | `platform-security` runs without Falco |
| `dashboards.tetragon.enabled` | `true` | …without Tetragon |
| `dashboards.trivy.enabled` | `true` | …without Trivy Operator |

## Retention

Sized for a small disk, and worth knowing before you go looking for old data:

| What | Retention |
|---|---|
| Loki logs | `168h` (7 days) |
| Prometheus metrics | `7d` |

Loki also rate-limits ingestion (`5 MB/s`, `1MB` per stream), so a chatty
workload gets dropped lines rather than filling the disk.

## Values

| Key | Default | Note |
|---|---|---|
| `grafana.admin.existingSecret` | `grafana-admin-secret` | **must exist first** |
| `grafana.persistence` | `2Gi` | |
| `grafana.envFromSecrets` | `grafana-oauth-secret` (optional) | OAuth wiring, absent is fine |
| `loki.deploymentMode` | `SingleBinary` | one pod, filesystem store |
| `loki.singleBinary.persistence` | `8Gi` | |
| `loki.loki.limits_config.retention_period` | `168h` | |
| `promtail.config.clients[0].url` | in-cluster Loki | |
| `kube-prometheus-stack.grafana.enabled` | `false` | avoids a second Grafana |
| `kube-prometheus-stack.alertmanager.enabled` | `false` | no alert routing |
| `kube-prometheus-stack.prometheus.prometheusSpec.retention` | `7d` | |
| `dashboards.*.enabled` | `true` | per-dashboard toggles |

## See also

- [Monitoring operations guide](../../docs/stack/monitoring.md)
- [`platform-security`](../platform-security/README.md) — produces the Falco/Tetragon/Trivy signals
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart
