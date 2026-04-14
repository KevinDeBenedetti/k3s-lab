# k3s-lab

[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/k3s-lab/ci.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci.yml)

> Reusable Kubernetes platform toolkit — Helm charts (OCI), Kustomize bases, and automation for k3s on VPS.

## Overview

`k3s-lab` is a **public, reusable template repository**. It publishes Helm charts to GitHub Container Registry (OCI) and exposes versioned Kustomize bases via Git tags. It contains **no sensitive data or cluster-specific configuration**.

For cluster-specific configuration, use a private `infra` repository that consumes `k3s-lab` via pinned versions (see [Using with infra](docs/using-with-infra.md)).

## Features

- **Helm Charts** (OCI) — platform-base, platform-monitoring, platform-security, platform-vault, platform-argocd
- **Kustomize Bases** — reusable namespace, LimitRange, RBAC, ExternalSecret, and IngressRoute templates
- Lightweight Kubernetes via [k3s](https://k3s.io) with automated control-plane and agent bootstrap
- Ingress + automatic HTTPS via [Traefik](https://traefik.io) and [cert-manager](https://cert-manager.io)
- Full observability: Prometheus, Grafana, Loki, Promtail (VPS-optimized)
- Runtime security: Falco, Tetragon, Trivy Operator
- Secret management: HashiCorp Vault + External Secrets Operator
- GitOps: ArgoCD
- Makefile-driven workflow with includeable fragments
- Static CI: ShellCheck, actionlint, kubeconform, Helm lint, resource limits check, Gitleaks
- Local testing via Lima VMs and Bats

## Repository Structure

```
k3s-lab/
├── charts/                     # Helm charts published to ghcr.io (OCI)
│   ├── platform-base/          # Namespaces, LimitRange, shared RBAC
│   ├── platform-monitoring/    # Prometheus + Grafana + Loki + Promtail
│   ├── platform-security/      # Falco + Tetragon + Trivy
│   ├── platform-vault/         # Vault + External Secrets Operator
│   └── platform-argocd/        # ArgoCD
├── kubernetes/                 # Kustomize bases
│   ├── base/                   # Namespaces, LimitRange, RBAC
│   └── components/             # Reusable ExternalSecret, IngressRoute templates
├── makefiles/                  # Includeable Makefile fragments
├── scripts/                    # Deployment + validation scripts
├── lib/                        # Shared shell libs + default values
├── tests/                      # Bats + Lima VM tests
└── docs/                       # Full documentation
```

## Quick Start

### Direct usage (standalone cluster)

```bash
cp .env.example .env          # fill in your values
make k3s-server               # bootstrap control plane
make k3s-agent                # join agent node
make kubeconfig               # fetch kubeconfig
make deploy                   # deploy Traefik + cert-manager
make deploy-monitoring        # deploy Prometheus + Grafana + Loki
make deploy-vault             # (optional) deploy Vault + ESO
```

### Consumed by a private infra repo

```bash
# In your infra repo Makefile:
K3S_LAB_RAW := https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main
# Fetches makefiles on-demand from k3s-lab
```

Charts are consumed via OCI in ArgoCD ApplicationSets:
```yaml
repoURL: ghcr.io/kevindebenedetti/charts
chart: platform-monitoring
targetRevision: "0.1.0"
```

## Release Workflow

1. Modify a chart in `charts/`
2. Bump version in `Chart.yaml`
3. Tag and push (`git tag v1.0.0 && git push --tags`)
4. CI publishes charts to GHCR (OCI)
5. Renovate opens a PR in the infra repo to bump versions
6. Merge → ArgoCD syncs automatically

## Documentation

Full documentation: **https://kevindebenedetti.github.io/k3s-lab/**

→ [Getting Started](docs/getting-started.md) · [Configuration](docs/configuration.md) · [Using with Infra](docs/using-with-infra.md)
