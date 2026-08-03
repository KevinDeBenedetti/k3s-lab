# Security Policy

## Supported Versions

Only the **latest release** on the 0.x line is supported. Published charts are
served from [GHCR](https://github.com/KevinDeBenedetti?tab=packages); older
chart versions may be purged from the registry
(`.github/workflows/cleanup-packages.yml`), so always consume a recent pin.

| Version                                                                       | Supported |
| ----------------------------------------------------------------------------- | --------- |
| [Latest release](https://github.com/KevinDeBenedetti/k3s-lab/releases/latest) | ✅         |
| Older releases                                                                | ❌         |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

1. **GitHub Private Security Advisory** — open a
   [Security Advisory](https://github.com/KevinDeBenedetti/k3s-lab/security/advisories/new)
   *(preferred)*.
2. **Email** — contact information on the owner's
   [GitHub profile](https://github.com/KevinDeBenedetti).

Include a description of the vulnerability and its impact, the affected
chart/script/workflow, reproduction steps or a proof-of-concept, and any
suggested mitigation.

| Step                         | Target time              |
| ---------------------------- | ------------------------ |
| Acknowledgement of report    | 48 hours                 |
| Initial assessment           | 5 business days          |
| Fix & coordinated disclosure | Negotiated with reporter |

## Scope

This policy covers what this repository ships: the Helm charts under
`charts/`, the shell libraries and scripts under `lib/` and `scripts/`, the
Ansible roles, and the GitHub workflows. For vulnerabilities in the wrapped
upstream components (Traefik, cert-manager, Vault, …), report to the upstream
project — but if a chart here **pins or defaults to a vulnerable version**,
that is in scope and we want to know.

## How this repository watches its own components

A daily workflow (`.github/workflows/traefik-advisories.yml`) confronts the
component versions the charts ship — and, where visible, the versions actually
deployed — with the upstream GitHub security advisories, and opens a tracking
issue when one is covered. Reports that beat the watch to it are exactly what
this policy is for.
