# k3s-lab

[![CI](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/k3s-lab/ci.yml?style=for-the-badge&label=CI)](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci.yml)

> Reusable Kubernetes platform toolkit — Helm charts (OCI), Kustomize bases, and automation for k3s on VPS.

## Overview

`k3s-lab` is a **public, reusable template repository**. It publishes Helm charts to GitHub Container Registry (OCI) and exposes versioned Kustomize bases via Git tags. It contains **no sensitive data or cluster-specific configuration**.

For cluster-specific configuration, use a private `infra` repository that consumes `k3s-lab` via pinned versions (see [Using with infra](docs/using-with-infra.md)).

## Features

- **Helm Charts** (OCI) — platform-base, platform-monitoring, platform-security, platform-vault, platform-argocd
- **Kustomize Bases** — reusable namespace, LimitRange, RBAC, ExternalSecret, and IngressRoute templates
- **Ansible Roles** — common (VPS base), k3s_server, k3s_agent, wireguard
- Lightweight Kubernetes via [k3s](https://k3s.io) with automated control-plane and agent bootstrap
- Ingress + automatic HTTPS via [Traefik](https://traefik.io) and [cert-manager](https://cert-manager.io)
- Full observability: Prometheus, Grafana, Loki, Promtail (VPS-optimized)
- Runtime security: Falco, Tetragon, Trivy Operator
- Secret management: HashiCorp Vault + External Secrets Operator
- GitOps: ArgoCD
- Makefile-driven workflow with includeable fragments
- Static CI: ShellCheck, actionlint, kubeconform, Helm lint, resource limits check, Gitleaks
- Local testing via Bats

## Repository Structure

```
k3s-lab/
├── ansible/                    # Reusable Ansible roles + playbooks
│   ├── roles/
│   │   ├── common/             # VPS base: packages, sysctl, kernel modules, UFW
│   │   ├── k3s_server/         # k3s server installation + configuration
│   │   ├── k3s_agent/          # k3s agent join
│   │   └── wireguard/          # Optional WireGuard VPN setup
│   ├── playbooks/
│   │   ├── site.yml            # Full cluster provisioning
│   │   ├── k3s-server.yml      # Server node only
│   │   ├── k3s-agent.yml       # Add agent nodes
│   │   └── reset.yml           # Uninstall k3s (destructive)
│   └── requirements.yml        # Galaxy dependencies
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
├── tests/                      # Bats tests
└── docs/                       # Full documentation
```

## Quick Start

### Using Ansible (recommended)

In your private `infra` repo, configure inventory and run:

```bash
# Install Ansible dependencies
ansible-galaxy install -r k3s-lab/ansible/requirements.yml

# Provision full cluster
ansible-playbook -i ansible/inventory/hosts.yml k3s-lab/ansible/playbooks/site.yml
```

### Consumed by a private infra repo

```bash
# In your infra repo, roles_path in ansible.cfg points to k3s-lab/ansible/roles
# Terraform provisions Hetzner VPS, Ansible configures nodes using k3s-lab roles
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
