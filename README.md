# k3s-lab

[![CI/CD](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/k3s-lab/ci-cd.yml?style=for-the-badge&label=CI%2FCD)](https://github.com/KevinDeBenedetti/k3s-lab/actions/workflows/ci-cd.yml)

> Production-ready k3s cluster on VPS — automated setup with Traefik, cert-manager, Prometheus, Grafana, Loki, and Promtail.

## Features

- Lightweight Kubernetes via [k3s](https://k3s.io) with automated control-plane and worker bootstrap
- Ingress + automatic HTTPS via [Traefik](https://traefik.io) and [cert-manager](https://cert-manager.io) (Let's Encrypt HTTP-01)
- Full observability stack: Prometheus, Grafana, Alertmanager, Loki, and Promtail
- Makefile-driven workflow — one target per lifecycle stage
- Static CI: ShellCheck, actionlint, kubeconform, Bats, and secret scanning (no live cluster required)
- Reusable as a git submodule with includeable Makefile fragments
- **Optional:** HashiCorp Vault + External Secrets Operator for centralized secret management

## Prerequisites

- A VPS with SSH access
- `make`, `kubectl`, `helm`
- Secrets configured in `.env` (copy from `.env.example`)

## Usage

```bash
cp .env.example .env          # fill in your values
make k3s-server               # bootstrap control plane
make k3s-agent                # join agent node
make kubeconfig               # fetch kubeconfig
make deploy                   # deploy Traefik + cert-manager
make deploy-monitoring        # deploy Prometheus + Grafana + Loki
make deploy-vault             # (optional) deploy HashiCorp Vault
make vault-init               # (optional) initialize + configure Vault
make deploy-eso               # (optional) deploy External Secrets Operator
```

→ Full guide: [docs](https://kevindebenedetti.github.io/k3s-lab/getting-started)

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/k3s-lab/**.
It is generated from the `docs/` directory and published automatically on push.
