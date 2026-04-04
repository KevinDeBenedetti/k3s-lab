# Troubleshooting

Common issues and how to resolve them.

---

## k3s

### Node is NotReady

```bash
kubectl get nodes
# NAME     STATUS     ROLES   AGE
# server   NotReady   ...     1m
```

**Check k3s service logs:**
```bash
ssh ubuntu@SERVER_IP "sudo journalctl -u k3s -n 50 --no-pager"
```

Common causes:
- `ip_forward` is disabled → check sysctl: `sudo sysctl net.ipv4.ip_forward`
- CNI not initialized → wait 60s after install for Flannel to come up
- Port `6443` blocked → verify UFW rules

---

### kubectl: certificate error when connecting remotely

```
Unable to connect to server: x509: certificate is valid for 127.0.0.1, not 1.2.3.4
```

**Cause:** `--tls-san` was not set with the public IP during install.

**Fix:** Re-run `make k3s-server` with the correct `SERVER_IP` set.

---

### Agent can't join cluster

```
FATA[0005] Node token or agent token is required
```

**Fix:** Ensure `K3S_NODE_TOKEN` is set in `.env`. It should have been saved automatically by `make k3s-server`. Otherwise:

```bash
ssh ubuntu@SERVER_IP "sudo cat /var/lib/rancher/k3s/server/node-token"
# Add the output to .env: K3S_NODE_TOKEN=<token>
```

---

### Stale SSH host key (after VPS reformat)

```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

**Fix:**
```bash
make known-hosts-reset
```

---

## Traefik

### Service not reachable (502 Bad Gateway)

1. Check pod is running: `kubectl get pods -n <namespace>`
2. Check Traefik logs: `kubectl logs -n ingress deploy/traefik --tail=30`
3. Check IngressRoute: `kubectl get ingressroute -A`
4. Verify service name/port in the `IngressRoute` matches the actual `Service`

---

### Dashboard returns 404

Traefik dashboard requires the path `/dashboard/` (with trailing slash). Ensure your `DASHBOARD_DOMAIN` DNS points to `SERVER_IP` and the TLS certificate is issued.

```bash
kubectl get certificate -n ingress
curl -I https://dashboard.example.com/dashboard/
```

---

## cert-manager

### Certificate stuck in `False` / not ready

```bash
kubectl describe certificate <name> -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>
kubectl describe order <name> -n <namespace>
kubectl describe challenge <name> -n <namespace>
```

Look for events at the bottom of each resource.

**Common causes:**

| Symptom                    | Cause                             | Fix                                           |
| -------------------------- | --------------------------------- | --------------------------------------------- |
| `HTTP-01 challenge failed` | Port 80 not publicly reachable    | Check UFW, DNS propagation                    |
| `HTTP-01 challenge failed` | Global HTTP→HTTPS redirect active | Remove redirect from Traefik `web` entrypoint |
| `rate limit exceeded`      | Too many production cert requests | Use staging issuer for testing, wait 1 week   |
| `DNS not resolving`        | DNS not yet propagated            | Wait and retry, check with `dig <domain>`     |

---

### Test with staging issuer first

```yaml
issuerRef:
  name: letsencrypt-staging   # Use staging before production
  kind: ClusterIssuer
```

Staging certificates are not browser-trusted but have no rate limits. Validate the full pipeline works before switching to `letsencrypt-production`.

---

### Check cert-manager logs

```bash
kubectl logs -n cert-manager deploy/cert-manager --tail=50
kubectl logs -n cert-manager deploy/cert-manager-webhook --tail=20
```

---

## Lima (local testing)

### VM stuck on first boot (Apple Silicon)

```
INFO[...] Waiting for the essential requirement 1 of 2: "ssh"
```

**Fix:** Install Rosetta:
```bash
softwareupdate --install-rosetta
```

---

### Cannot reach k3s-lima after `make vm-k3s-kubeconfig`

```
Unable to connect to the server: dial tcp 127.0.0.1:6443: connect: connection refused
```

**Check if the VM is running:**
```bash
limactl list
```

**Start a stopped VM:**
```bash
make vm-k3s-start
```

**Re-run the kubeconfig step:**
```bash
make vm-k3s-kubeconfig
kubectl config use-context k3s-lima
```

---

### Smoke test fails after `make vm-k3s-deploy`

```
Attempt 6/6: HTTP 000 — waiting 5s for Traefik...
❌ Smoke test failed after 30s
```

**Check Traefik is running:**
```bash
kubectl --context k3s-lima get pods -n ingress
kubectl --context k3s-lima logs -n ingress deploy/traefik --tail=30
```

**Check the certificate was issued:**
```bash
kubectl --context k3s-lima get certificate -A
```

---

### Grafana data sources missing after `make vm-k3s-deploy-monitoring`

The datasource sidecar may not have picked up the provisioned ConfigMap on first start.

**Fix:** Restart Grafana:
```bash
kubectl --context k3s-lima rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
kubectl --context k3s-lima rollout status deployment/kube-prometheus-stack-grafana -n monitoring
```

---

### Port 6443 already in use on the host

```
Error response from daemon: driver failed programming external connectivity: Bind for 0.0.0.0:6443 failed: port is already allocated
```

Another process (another Lima VM or local k3s) is using port `6443`.

```bash
lsof -i :6443
```

Stop the conflicting process or delete the stale Lima VM:
```bash
limactl delete --force infra-k3s-vm
```

---

## Monitoring

### Grafana is not reachable

1. Check pod: `kubectl get pods -n monitoring | grep grafana`
2. Check IngressRoute: `kubectl get ingressroute -n monitoring`
3. Check certificate: `kubectl get certificate -n monitoring`
4. Check Traefik routes the domain: `kubectl logs -n ingress deploy/traefik --tail=20`

---

### grafana-admin-secret not found

```
grafana-admin-secret not found in monitoring namespace.
Run first: make deploy-grafana-secret GRAFANA_PASSWORD=<your-password>
```

**Fix:**
```bash
make deploy-grafana-secret
make deploy-monitoring
```

---

### Prometheus not scraping Traefik

1. Verify `serviceMonitor.enabled: true` in `traefik-values.yaml`
2. Check ServiceMonitor exists: `kubectl get servicemonitor -n ingress`
3. In Grafana → Explore → Prometheus, run: `up{job="traefik"}`

---

### Promtail pods CrashLoopBackOff

```bash
kubectl logs -n monitoring daemonset/promtail --tail=30
```

Common cause: permission to read `/var/log/pods/`. Check Promtail DaemonSet hostPath mounts.

---

## kubeconfig

### Context not found

```
error: no context exists with the name: "k3s-lab"
```

**Fix:**
```bash
make kubeconfig
kubectl config use-context k3s-lab
```

---

### Can't reach cluster (timeout)

```
The connection to the server 1.2.3.4:6443 was refused
```

1. Verify k3s is running: `ssh ubuntu@SERVER_IP "sudo systemctl status k3s"`
2. If crashed: `ssh ubuntu@SERVER_IP "sudo systemctl restart k3s"`
3. Verify port 6443 is open: `curl -k https://SERVER_IP:6443/healthz`

---

## General debugging commands

```bash
# All pod statuses
kubectl get pods -A

# Describe a failing pod
kubectl describe pod <name> -n <namespace>

# Pod logs
kubectl logs <pod> -n <namespace> --tail=50

# Events (often shows the root cause)
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -A
```
