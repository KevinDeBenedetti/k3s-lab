# Using k3s-lab with a Private Infra Repo

This guide explains how to use k3s-lab as a shared toolkit from a **private repository that holds only your personal configuration** — your IPs, domains, passwords, and custom app manifests.

---

## Architecture overview

```
k3s-lab (public)                  infra (private)
──────────────────────────────    ──────────────────────────────────
  makefiles/                        Makefile          ← thin wrapper
  scripts/                          .env              ← your secrets
  kubernetes/    (templates)        kubernetes/       ← your apps
  lib/                              .mk-cache/        ← auto-fetched
  tests/                              00-lib.mk
  k3s/                                10-help.mk
                                       ...
                                       99-lima.mk
```

**Rule:** Every file you edit lives in `infra/`. You never touch `k3s-lab/` for daily use.

| Repo | What it holds | You edit? |
|------|--------------|-----------|
| `k3s-lab` | All scripts, makefiles, manifests, tests | Only to improve the toolkit |
| `infra` | Your `.env`, your app manifests, `Makefile` | Yes — always |

k3s-lab makefiles are fetched **on-demand via curl** into `infra/.mk-cache/` the first time you run any `make` target. No clone, no submodule.

---

## 1 — Bootstrap your infra repo

### 1.1 Create the repo

```bash
mkdir ~/dev/infra && cd ~/dev/infra
git init
```

### 1.2 Create the Makefile

```makefile
# infra/Makefile
.DEFAULT_GOAL := help
SHELL         := /bin/bash

-include .env
export

# ── Your values ───────────────────────────────────────────────────────────────
SSH_USER            ?= youruser
SSH_PORT            ?= 22
SSH_KEY             ?= $(HOME)/.ssh/id_ed25519
SSH_KEY             := $(subst ~,$(HOME),$(SSH_KEY))
INITIAL_USER        ?= root
MASTER_IP           ?=
WORKER_IP           ?=
KUBECONFIG_CONTEXT  ?= k3s-infra
K3S_VERSION         ?= v1.32.2+k3s1

# ── k3s-lab source ─────────────────────────────────────────────────────────────
K3S_LAB     :=
K3S_LAB_RAW := https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/main

# ── Terminal colors ───────────────────────────────────────────────────────────
GREEN  := \033[0;32m
YELLOW := \033[1;33m
CYAN   := \033[0;36m
RED    := \033[0;31m
RESET  := \033[0m

# ── Shared makefiles (auto-fetched from k3s-lab) ──────────────────────────────
MK_CACHE   := .mk-cache
SHARED_MKS := 00-lib 10-help 20-vps 30-k3s 40-kubeconfig 50-deploy \
              60-status 70-ssh 80-dev 90-provision 99-lima

$(foreach f,$(SHARED_MKS),\
  $(if $(wildcard $(MK_CACHE)/$(f).mk),,\
    $(shell mkdir -p $(MK_CACHE) && \
            curl -fsSL $(K3S_LAB_RAW)/makefiles/$(f).mk \
                 -o $(MK_CACHE)/$(f).mk 2>/dev/null || true)))

-include $(patsubst %,$(MK_CACHE)/%.mk,$(SHARED_MKS))

# ── Cache management ──────────────────────────────────────────────────────────

.PHONY: mk-update mk-clean

mk-update: ## Force re-fetch all shared makefiles from k3s-lab
	@echo "$(YELLOW)→ Refreshing shared makefiles from k3s-lab...$(RESET)"
	@rm -rf $(MK_CACHE) && mkdir -p $(MK_CACHE)
	@$(foreach f,$(SHARED_MKS),\
	  curl -fsSL $(K3S_LAB_RAW)/makefiles/$(f).mk -o $(MK_CACHE)/$(f).mk \
	    && echo "  ✓ $(f).mk";)
	@echo "$(GREEN)✅ Shared makefiles updated$(RESET)"

mk-clean: ## Remove cached makefiles (re-fetched on next make invocation)
	@rm -rf $(MK_CACHE)
	@echo "$(GREEN)✅ .mk-cache cleared$(RESET)"
```

### 1.3 Create `.gitignore`

```gitignore
# Secrets
.env

# Auto-fetched toolkit makefiles — do not commit
.mk-cache/
```

### 1.4 Verify all targets are available

```bash
make help
```

You should see all 40+ targets from k3s-lab alongside your own `mk-update` / `mk-clean`.

---

## 2 — Personalize your `.env`

```bash
cp /dev/null .env   # or copy from k3s-lab's .env.example
```

Edit `.env` with **your** values — this is the only file that changes between users:

```bash
# VPS nodes
MASTER_IP=1.2.3.4
WORKER_IP=5.6.7.8

# SSH
SSH_USER=kevin
SSH_KEY=~/.ssh/id_ed25519
INITIAL_USER=root

# k3s
K3S_VERSION=v1.32.2+k3s1
# K3S_NODE_TOKEN is auto-filled by `make k3s-master`

# Helm chart versions (pin to avoid surprise upgrades)
TRAEFIK_CHART_VERSION=34.4.0
CERT_MANAGER_VERSION=v1.17.1
KUBE_PROMETHEUS_VERSION=82.10.3
LOKI_VERSION=6.35.1
PROMTAIL_VERSION=6.17.1

# Your domain + Let's Encrypt email
DOMAIN=example.com
EMAIL=you@example.com

# Traefik dashboard
DASHBOARD_DOMAIN=dashboard.example.com
DASHBOARD_PASSWORD=your-secure-password

# Grafana
GRAFANA_DOMAIN=grafana.example.com
GRAFANA_PASSWORD=your-secure-password

# kubectl context name
KUBECONFIG_CONTEXT=k3s-infra
```

> ⚠️ `.env` is in `.gitignore`. It is **never committed**. Add `.env.example` with placeholder values instead.

See the [Configuration reference](../configuration.md) for every variable.

---

## 3 — Deploy the cluster

Once `.env` is filled, the full deploy is identical to using k3s-lab directly. All targets are available from `infra/`:

```bash
# First time only — full provisioning
make provision
```

Or step by step:

```bash
make setup-all             # bootstrap VPS nodes (dotfiles + packages)
make k3s-master            # install k3s server + auto-save K3S_NODE_TOKEN
make k3s-worker            # join worker to cluster
make kubeconfig            # merge ~/.kube/config
kubectl config use-context k3s-infra
make nodes                 # verify both nodes Ready

make deploy-dashboard-secret
make deploy                # Traefik + cert-manager + ClusterIssuers

make deploy-grafana-secret
make deploy-monitoring     # Prometheus + Grafana + Loki + Promtail
```

See [Getting Started](../getting-started.md) for the full step-by-step walkthrough.

---

## 4 — Deploy your own apps

### 4.1 Using k3s-lab's example app

k3s-lab ships example manifests in `kubernetes/apps/` that use `${VARIABLE}` placeholders substituted from your `.env`:

```bash
# Fetch and apply the example app
curl -fsSL $K3S_LAB_RAW/kubernetes/apps/deployment.yaml \
  | envsubst | kubectl apply -f -

curl -fsSL $K3S_LAB_RAW/kubernetes/apps/service-ingress.yaml \
  | envsubst | kubectl apply -f -
```

### 4.2 Adding your own app manifests

Create a `kubernetes/` directory in your **infra repo** for app-specific manifests. These are purely yours — they never go into k3s-lab.

```
infra/
  kubernetes/
    myapp/
      namespace.yaml
      deployment.yaml
      service.yaml
      ingress.yaml        ← IngressRoute with ${DOMAIN}
      certificate.yaml    ← cert-manager Certificate
```

**Example IngressRoute + Certificate:**

```yaml
# infra/kubernetes/myapp/ingress.yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: apps
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - myapp.${DOMAIN}
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: apps
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.${DOMAIN}`)
      kind: Rule
      services:
        - name: myapp
          port: 80
  tls:
    secretName: myapp-tls
```

Apply with variable substitution:

```bash
envsubst < kubernetes/myapp/ingress.yaml | kubectl apply -f -
```

### 4.3 Add a `make` target for your app (optional)

Add infra-specific targets directly in `infra/Makefile`:

```makefile
# infra/Makefile — add below the mk-update/mk-clean block

.PHONY: deploy-myapp delete-myapp

deploy-myapp: ## Deploy myapp (Deployment + Service + IngressRoute + Certificate)
	@echo "$(YELLOW)→ Deploying myapp...$(RESET)"
	@envsubst < kubernetes/myapp/namespace.yaml   | kubectl apply -f -
	@envsubst < kubernetes/myapp/deployment.yaml  | kubectl apply -f -
	@envsubst < kubernetes/myapp/service.yaml     | kubectl apply -f -
	@envsubst < kubernetes/myapp/ingress.yaml     | kubectl apply -f -
	@echo "$(GREEN)✅ myapp deployed at https://myapp.$(DOMAIN)$(RESET)"

delete-myapp: ## Remove myapp from the cluster
	@kubectl delete -f kubernetes/myapp/ --ignore-not-found
	@echo "$(GREEN)✅ myapp removed$(RESET)"
```

Now `make help` shows your target alongside all k3s-lab targets.

---

## 5 — Update the toolkit

When k3s-lab ships improvements, update your cache:

```bash
make mk-update
```

This re-fetches all shared makefiles from `k3s-lab@main`. Your `.env` and `kubernetes/` app manifests are **untouched**.

### Pin to a specific k3s-lab version

To pin to a commit or branch instead of `main`, change `K3S_LAB_RAW` in your `infra/Makefile`:

```makefile
# Pin to a specific git ref
K3S_LAB_RAW := https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/v1.2.0

# Or test against a development branch
K3S_LAB_RAW := https://raw.githubusercontent.com/KevinDeBenedetti/k3s-lab/my-feature-branch
```

Then run `make mk-clean && make mk-update` to re-fetch for the new ref.

### What gets updated vs what stays yours

| Updated by `make mk-update` | Never touched |
|-----------------------------|---------------|
| `.mk-cache/` — all shared makefiles | `Makefile` |
| Scripts fetched at runtime via curl | `.env` |
| k3s-lab's `kubernetes/` templates | `kubernetes/` — your apps |

---

## 6 — Update Helm chart versions

Chart versions are pinned in `.env`. To upgrade:

1. Update the version in `.env`:
   ```bash
   TRAEFIK_CHART_VERSION=35.0.0
   ```

2. Re-run the deploy target:
   ```bash
   make deploy           # for Traefik / cert-manager
   make deploy-monitoring  # for Prometheus / Grafana / Loki
   ```

The deploy scripts call `helm upgrade --install`, so running them again is idempotent.

---

## 7 — Test locally (Lima VM)

Before deploying to real VPS nodes, test with a local Lima VM:

```bash
make vm-k3s-full          # create VM → install k3s → kubeconfig (≈5 min)
make vm-k3s-deploy        # deploy Traefik + cert-manager
make vm-k3s-smoke         # TLS pipeline smoke test
make vm-k3s-clean         # tear down when done
```

The Lima targets read the same `.env` but override environment-specific values (`MASTER_IP=127.0.0.1`, self-signed TLS, NodePort instead of externalIPs).

See the [Local Testing guide](../operations/local-testing.md) for the complete walkthrough.

---

## 8 — Override a k3s-lab target

If you need to customize a shared target (e.g. `deploy` has special requirements for your stack), add it directly in `infra/Makefile` **after** the `-include` block. Make uses the first definition of a target:

```makefile
# Override the shared deploy target with infra-specific steps
deploy: ## Deploy base stack + myapp
	@$(call run-local-script,scripts/deploy-stack.sh)
	@envsubst < kubernetes/myapp/ingress.yaml | kubectl apply -f -
	@echo "$(GREEN)✅ Stack + myapp deployed$(RESET)"
```

> ⚠️ Override sparingly — the shared targets are maintained and improved in k3s-lab.

---

## 9 — Full workflow summary

```bash
# ── First time ────────────────────────────────────────────────────────────────
git clone <your-infra-repo> && cd infra
cp .env.example .env     # fill in your IPs, domain, passwords

make help                # verify all targets loaded from k3s-lab

# ── Provision cluster ─────────────────────────────────────────────────────────
make provision           # one-shot: VPS → k3s → kubeconfig → deploy → monitoring

# ── Day-to-day ────────────────────────────────────────────────────────────────
make nodes               # check node status
make status              # check all pod statuses
make deploy-myapp        # deploy your custom app
kubectl logs -n apps deploy/myapp --tail=50

# ── Maintain ─────────────────────────────────────────────────────────────────
make mk-update           # pull latest makefiles from k3s-lab
# edit .env to bump TRAEFIK_CHART_VERSION=35.0.0
make deploy              # apply Helm upgrade

# ── Debug remotely ────────────────────────────────────────────────────────────
make ssh-master          # open SSH shell on master VPS
make ssh-worker          # open SSH shell on worker VPS
```
