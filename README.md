# k3s-lab

[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/k3s-lab/ci.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/KevinDeBenedetti/k3s-lab?style=for-the-badge)](https://github.com/KevinDeBenedetti/k3s-lab/releases)
[![License](https://img.shields.io/github/license/KevinDeBenedetti/k3s-lab?style=for-the-badge)](LICENSE)

> Reusable Kubernetes platform toolkit — Helm charts (OCI), Kustomize bases, and automation for k3s on VPS.

## Overview

`k3s-lab` is a **public, reusable platform toolkit**. It publishes versioned Helm charts to GitHub Container Registry (OCI), exposes reusable Kustomize bases and Ansible roles, and contains **no sensitive data or cluster-specific configuration**.

There are two ways to use it, and the rest of this page is organized around them:

| Path | You want to | Start with |
| ---- | ----------- | ---------- |
| **Try it** | See the whole platform running on a cluster, in one command | The [`platform-deployment`](charts/platform-deployment/) umbrella chart |
| **Run it** | Operate components individually, pin versions, upgrade one piece at a time | Individual charts + your own private config repo ([homelab guide](docs/homelab.md)) |

## Features

- **Helm charts** (OCI, on [GHCR](https://github.com/KevinDeBenedetti?tab=packages)) — one chart per platform component, plus an umbrella chart that aggregates them
- **Kustomize bases** — reusable namespace, LimitRange, RBAC, ExternalSecret, and IngressRoute templates
- **Ansible roles** — common (VPS base), k3s_server, k3s_agent, wireguard
- Lightweight Kubernetes via [k3s](https://k3s.io) with automated control-plane and agent bootstrap
- Ingress + automatic HTTPS via [Traefik](https://traefik.io) and [cert-manager](https://cert-manager.io)
- Full observability: Prometheus, Grafana, Loki, Promtail (VPS-optimized)
- Runtime security: Falco, Tetragon, Trivy Operator, Kyverno
- Secret management: HashiCorp Vault + External Secrets Operator
- GitOps: ArgoCD
- **Daily security watch**: the deployed Traefik proxy version is checked against upstream advisories every day, independently of repository activity
- Static CI: ShellCheck, actionlint, kubeconform, Helm lint, resource limits check, Gitleaks — plus Bats tests for every shell library

## Quick Start

### Try the platform (umbrella chart)

One command installs the stack — ArgoCD, monitoring, Vault, cert-manager, Traefik and external-secrets (verified on a blank k3d cluster with the published 0.16.0 artifact):

```bash
helm install platform oci://ghcr.io/kevindebenedetti/charts/platform-deployment \
  --version 0.24.0 --namespace platform --create-namespace
```

One caveat worth knowing up front: on stock k3s or k3d, **disable the bundled Traefik first** (`--k3s-arg "--disable=traefik@server:0"`), since its CRDs conflict with this chart's — the same thing this repo's Ansible role does on real nodes. The Kyverno ClusterPolicies also come in a second `helm upgrade`, for a Helm ordering reason explained (with the command) in the [chart's README](charts/platform-deployment/README.md), which also carries the full verified-install report. Each component can be switched off independently and configured through nested values. Check the [releases page](https://github.com/KevinDeBenedetti/k3s-lab/releases) (`vX.Y.Z` tags) for the latest version; every chart and the umbrella's sub-chart pins share that version.

### Provision a cluster from scratch (Ansible)

From two fresh VPS nodes to a running k3s cluster:

```bash
ansible-galaxy install -r ansible/requirements.yml
ansible-playbook -i <your-inventory> ansible/playbooks/site.yml
```

The full walkthrough — prerequisites, inventory, verification — is in **[Getting Started](docs/getting-started.md)**.

### Run it with GitOps (your own config repo)

For real operation, keep your cluster-specific configuration (inventory, values, pins) in a **private repo** that consumes `k3s-lab`, and deploy the individual charts via ArgoCD — pinned, so that every upgrade is an explicit, reviewable change:

```yaml
# In an ArgoCD ApplicationSet
- repoURL: ghcr.io/kevindebenedetti/charts
  chart: platform-traefik
  targetRevision: "0.24.0"   # pin to a published version — never a range
```

The full path — inventory, provisioning, kubeconfig, platform install and the checks to keep pins honest — is in **[Running a homelab](docs/homelab.md)**.

## Repository Structure

```
k3s-lab/
├── ansible/                       # Reusable Ansible roles + playbooks
│   ├── roles/                     # common, k3s_server, k3s_agent, wireguard
│   ├── playbooks/                 # site.yml, k3s-server.yml, k3s-agent.yml, reset.yml
│   └── requirements.yml           # Galaxy dependencies
├── charts/                        # Helm charts published to ghcr.io (OCI)
│   ├── platform-deployment/       # ★ Umbrella: the whole platform in one release
│   ├── platform-argocd/           # ArgoCD (GitOps)
│   ├── platform-base/             # Namespaces, LimitRange, shared RBAC
│   ├── platform-cert-manager/     # TLS certificates (cert-manager)
│   ├── platform-external-secrets/ # External Secrets Operator
│   ├── platform-monitoring/       # Prometheus + Grafana + Loki + Promtail
│   ├── platform-security/         # Falco + Tetragon + Trivy + Kyverno
│   ├── platform-traefik/          # Ingress controller (Traefik)
│   ├── platform-vault/            # HashiCorp Vault
│   └── platform-vault-seeder/     # Vault bootstrap/seeding job
├── kubernetes/                    # Kustomize bases + reusable components
├── taskfiles/                     # Includeable Task fragments (provision, deploy, …)
├── scripts/                       # Deployment + validation scripts
├── lib/                           # Shared shell libs (tested with Bats)
├── tests/                         # Bats tests
└── docs/                          # Full documentation
```

## Release Workflow

Releases are fully automated with [release-please](https://github.com/googleapis/release-please); versions follow a deliberate **0.x line**, and the **whole repository shares one version** — every chart, the umbrella's pins and the toolkit scripts move together:

| What | Tag | Changelog |
| --- | --- | --- |
| everything (charts, scripts, `lib/`, Ansible, taskfiles) | `vX.Y.Z` | `CHANGELOG.md` |

1. Merge a change to `main` (conventional commits: `feat:`, `fix:`, …)
2. release-please opens a single release PR — changelog + version bump of every `Chart.yaml`, of the umbrella's pins and of the `K3S_LAB_RAW` refs in `scripts/` and `lib/`
3. Merging it creates the GitHub release and the `vX.Y.Z` tag
4. `release-charts` publishes every chart whose version is not on GHCR yet (the umbrella last, since its pins resolve to the subcharts just pushed), then renders the umbrella as a post-publish check
5. Consumers pin `ghcr.io/kevindebenedetti/charts/<chart>` at that version (Renovate: `docker` datasource)

## Documentation

Full documentation: **https://kevindebenedetti.github.io/k3s-lab/**

→ [Getting Started](docs/getting-started.md) · [Running a homelab](docs/homelab.md) · [Configuration](docs/configuration.md)

## License

[Apache-2.0](LICENSE)
