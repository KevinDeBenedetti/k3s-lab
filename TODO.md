# TODO

## Platform Chart Defaults (2026-04-15)

### Security (platform-security v0.2.0)
- Falco: requests 200m/256Mi, limits 400m/512Mi (modern_ebpf)
- Tetragon: requests 50m/64Mi, limits 100m/128Mi (minimal)
- Trivy Operator: requests 200m/256Mi, limits 400m/512Mi, node scanning disabled, daily scan interval
- Falcosidekick: disabled by default

### Monitoring (platform-monitoring v0.2.0)
- Grafana: requests 50m/150Mi, limits 100m/300Mi
- Prometheus: 7d retention, 60s scrape, WAL compression
- Loki: ingester chunk_idle 30m / max_age 1h, 7d retention, rate limit 5MB/s
- Promtail: requests 25m/64Mi, limits 150m/128Mi

### Base (platform-base v0.2.0)
- LimitRange: default 200m/256Mi, max 2 CPU / 2Gi per namespace
- Pod Security Standards enforced per namespace
