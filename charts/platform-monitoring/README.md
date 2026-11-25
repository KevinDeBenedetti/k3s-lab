# platform-monitoring

Observability stack — Grafana, Loki, Alloy and Prometheus — assembled from
four upstream charts and trimmed to fit an 8 GB single node.

| | |
|---|---|
| Subcharts | `grafana` [`10.5.15`](https://grafana.github.io/helm-charts), `loki` [`7.0.0`](https://grafana.github.io/helm-charts), `alloy` [`1.16.0`](https://grafana.github.io/helm-charts), `kube-prometheus-stack` [`86.1.0`](https://prometheus-community.github.io/helm-charts) |
| Namespace (convention) | `monitoring` — set at install time; this chart neither creates nor enforces it |
| Per-cluster overrides | `<your-repo>/platform/monitoring/values.yaml` |

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

**Alloy ships the pod logs** to `http://loki:3100`: a DaemonSet (`alloy`)
tailing the kubelet's files under `/var/log/pods` on every node. Its pipeline in
`values.yaml` is Promtail's `kubernetes-pods` job rule for rule, so the streams
carry the same labels: `namespace`, `pod`, `container`, `node_name`, `app`,
`instance`, `component`, `job`, `filename` and `stream`. Its read positions
live on the node, under `/var/lib/alloy`, so a restarted pod resumes where it
stopped.

The chart trims Alloy to that one job: no PodLogs CRD, no config-reloader
sidecar (a config change rolls the DaemonSet instead), no Service, no usage
report, and a ServiceAccount that can only read pods, where the upstream
default reads every Secret and ConfigMap of the cluster.

### Upgrading from a release that shipped Promtail

Alloy replaced the `promtail` subchart, which is end of life. The upgrade
removes the `promtail` DaemonSet, ServiceAccount, ClusterRole and Secret and
creates the `alloy` ones, so:

- **Values under `promtail:` are ignored.** Move what you had overridden to the
  `alloy:` key. A custom Loki client (URL, tenant) or pipeline stage now lives
  in `alloy.alloy.configMap.content`, which replaces the default as a whole.
- **Alloy starts from its own positions**, not Promtail's: on its first start it
  reads every log file still on the node from the beginning, so the lines
  Promtail had already shipped reach Loki a second time, or are rejected as too
  old.
- **Anything that names the promtail pods** (a NetworkPolicy, a policy
  exception, an alert on `daemonset="promtail"`) has to follow.

## Dashboards and datasources

This chart owns its templates: Loki and Prometheus datasources, plus dashboards
for Kubernetes, logs, self-monitoring, Tetragon and Trivy. They are
delivered through the Grafana sidecar (`grafana_dashboard` label).

There is no Falco dashboard. The one shipped until 0.24 read Falcosidekick's
metrics only, and no configuration of `platform-security` produces them:
Falcosidekick is off by default, and Falco is not set to send it events even
when it is on. Falco writes its alerts to its pods' stdout, so they are in Loki: the
logs dashboard finds them (filter on the Falco pods).

Every dashboard is gated. The security ones because a dashboard for a component
you did not deploy is worse than no dashboard; the generic ones so a consumer
that ships its own dashboards can drop them:

| Toggle | Default | Turn off when |
|---|---|---|
| `dashboards.tetragon.enabled` | `true` | `platform-security` runs without Tetragon |
| `dashboards.trivy.enabled` | `true` | …without Trivy Operator |
| `dashboards.kubernetes.enabled` | `true` | you ship your own cluster overview |
| `dashboards.logs.enabled` | `true` | you ship your own logs dashboard |
| `dashboards.selfMonitoring.enabled` | `true` | you do not want the Prometheus/Grafana self-monitoring view |

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
| `alloy.alloy.configMap.content` | Promtail's `kubernetes-pods` pipeline, pushing to in-cluster Loki | rendered through `tpl`: no double braces in it |
| `alloy.alloy.resources` | `128Mi` requested, `256Mi` limit | per node |
| `kube-prometheus-stack.grafana.enabled` | `false` | avoids a second Grafana |
| `kube-prometheus-stack.alertmanager.enabled` | `false` | no alert routing |
| `kube-prometheus-stack.prometheus.prometheusSpec.retention` | `7d` | |
| `dashboards.*.enabled` | `true` | per-dashboard toggles |

## See also

- [Monitoring operations guide](../../docs/stack/monitoring.md)
- [`platform-security`](../platform-security/README.md) — produces the Falco/Tetragon/Trivy signals
- [`platform-deployment`](../platform-deployment/README.md) — umbrella chart
