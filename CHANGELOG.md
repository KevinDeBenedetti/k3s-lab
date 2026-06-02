# Changelog

## [0.11.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.10.0...v0.11.0) (2026-06-02)


### Features

* Add vault-seeder Helm chart with job configurations and validation scripts ([7dc5d8e](https://github.com/KevinDeBenedetti/k3s-lab/commit/7dc5d8e1e8d76763db6a21c88508eefda686c3b7))

## [0.10.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.9.1...v0.10.0) (2026-06-02)


### Features

* **helm:** Add platform-deployment umbrella chart (v0.1.0) ([26271c0](https://github.com/KevinDeBenedetti/k3s-lab/commit/26271c007ae335b4777bb461a66692c46c4d63e8))
* **kubernetes:** add Kustomize components for app modularity ([e3d5c04](https://github.com/KevinDeBenedetti/k3s-lab/commit/e3d5c04267a99981d18554371fa10f173fa3e30f))


### Bug Fixes

* **ci:** Fix GitHub Actions validation for platform-deployment chart ([f3d6960](https://github.com/KevinDeBenedetti/k3s-lab/commit/f3d6960e63cbfe8df5b647cc77af9542d0526301))
* **platform-argocd:** bump to 0.9.2 — increase controller memory default to 2Gi (OOMKill prevention) ([5909fcf](https://github.com/KevinDeBenedetti/k3s-lab/commit/5909fcf2e7de931f6a20432300fc323a45492aa4))

## [0.9.1](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.9.0...v0.9.1) (2026-06-01)


### Bug Fixes

* refactor Makefiles to Taskfiles and Update Load Env Script ([e7d7783](https://github.com/KevinDeBenedetti/k3s-lab/commit/e7d77832b8490da69405813be1bfc498c6c1f7c0))

## [0.9.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.8.0...v0.9.0) (2026-05-31)


### Features

* **charts:** update chart versions and dependencies for platform-argocd, platform-external-secrets, platform-monitoring, platform-security, and platform-traefik ([8756683](https://github.com/KevinDeBenedetti/k3s-lab/commit/8756683a3aad18a08f66b95db67ead7eec47f67e))

## [0.8.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.7.4...v0.8.0) (2026-05-25)


### Features

* add root Taskfile.yml for standalone k3s-lab usage ([2fc313e](https://github.com/KevinDeBenedetti/k3s-lab/commit/2fc313e6cfa1c20735eece5b3db81bc031616acc))
* **scripts:** add vault-seed.sh — extracted from vault.mk inline shell ([d6ad15e](https://github.com/KevinDeBenedetti/k3s-lab/commit/d6ad15e29810432ed244fb5c7d6cbe6b0b1291d0))
* **taskfiles:** add argocd.yml — ArgoCD deployment and management tasks ([ae60dc2](https://github.com/KevinDeBenedetti/k3s-lab/commit/ae60dc2cd976049f7b34f0801ffb2c15e987eb6f))
* **taskfiles:** add deploy.yml — secret creation and grafana oauth tasks ([37d2ece](https://github.com/KevinDeBenedetti/k3s-lab/commit/37d2ece42aae3d17736dbff8df70b42b08f72519))
* **taskfiles:** add provision.yml — Ansible provisioning tasks ([daa15d3](https://github.com/KevinDeBenedetti/k3s-lab/commit/daa15d3328e94634503bc2803036fa84f379f53f))
* **taskfiles:** add ssh.yml — SSH access tasks ([fdbac45](https://github.com/KevinDeBenedetti/k3s-lab/commit/fdbac45cca8c9f2149c43728fc50b2181058ca13))
* **taskfiles:** add status.yml — cluster status and health check tasks ([98cf48a](https://github.com/KevinDeBenedetti/k3s-lab/commit/98cf48a2afbe92396b05bd86fd7ae193637bf5f9))
* **taskfiles:** add vault.yml — Vault + ESO tasks ([2a8b61c](https://github.com/KevinDeBenedetti/k3s-lab/commit/2a8b61c3e046d851657a581268b3867da30d67ab))
* **taskfiles:** update argocd and vault taskfiles for improved admin commands ([fecdcff](https://github.com/KevinDeBenedetti/k3s-lab/commit/fecdcff5ffaacc14fc0c424a50ee2c72edf79d50))
* update CI workflows and cleanup packages; refine vault configurations and documentation ([d095987](https://github.com/KevinDeBenedetti/k3s-lab/commit/d095987938853e2981dc425fa83478623c1c9bba))
* **vault.mk:** add VAULT_CONFIGURE_SCRIPT / VAULT_SEED_SCRIPT override hooks ([6719158](https://github.com/KevinDeBenedetti/k3s-lab/commit/6719158df3736b0fce5109e6d66d51feac7c852c))


### Bug Fixes

* **gitleaks:** add global allowlist for historical commits with placeholder values ([b57496a](https://github.com/KevinDeBenedetti/k3s-lab/commit/b57496ad953e6946f37cbdfa4b825f085bedf9eb))

## [0.7.4](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.7.3...v0.7.4) (2026-04-23)


### Bug Fixes

* enhance Falco dashboard with improved metrics, dynamic data sources, and updated visualizations ([76d56d4](https://github.com/KevinDeBenedetti/k3s-lab/commit/76d56d482ba69fa4ad26def11c801b7503f3f5b9))

## [0.7.3](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.7.2...v0.7.3) (2026-04-18)


### Bug Fixes

* add retry logic for helm dependency update in release workflow ([3bfaf09](https://github.com/KevinDeBenedetti/k3s-lab/commit/3bfaf09296c05d1aaeaf624f3b78e28d3485aa70))

## [0.7.2](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.7.1...v0.7.2) (2026-04-18)


### Bug Fixes

* update Prometheus queries in Grafana Falco dashboard to use correct metric names ([e0e50c6](https://github.com/KevinDeBenedetti/k3s-lab/commit/e0e50c605c818743ddea21953bf74d028ed7b9b7))

## [0.7.1](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.7.0...v0.7.1) (2026-04-18)


### Bug Fixes

* remove unnecessary issues permission from release workflow ([99d4945](https://github.com/KevinDeBenedetti/k3s-lab/commit/99d4945daaf8775397bf31f1d36ece15af1be817))
* restore issues permission in release workflow ([78a703a](https://github.com/KevinDeBenedetti/k3s-lab/commit/78a703aba90e511f21f54c3390b297ca20fd1523))

## [0.7.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.6.0...v0.7.0) (2026-04-18)


### Features

* add platform-traefik Helm chart with initial configuration and values ([00f3c34](https://github.com/KevinDeBenedetti/k3s-lab/commit/00f3c34fc2330bcf8437e06d91489258735517dd))


### Bug Fixes

* update release-please config to include platform-cert-manager and platform-external-secrets, and update platform-traefik version to 0.1.1 ([610ff0b](https://github.com/KevinDeBenedetti/k3s-lab/commit/610ff0b7bc61cc62ea88cdcbd1ed26c67a6128b9))
* update Traefik values.yaml to correct HTTP to HTTPS redirection configuration ([9aeaf00](https://github.com/KevinDeBenedetti/k3s-lab/commit/9aeaf00a8f50e3886fa655bbe0812a9f28f57f0c))

## [0.6.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.5.3...v0.6.0) (2026-04-17)


### Features

* add platform-cert-manager and platform-external-secrets Helm charts with initial configurations ([6976456](https://github.com/KevinDeBenedetti/k3s-lab/commit/6976456ad238a2077d7096859c7db033b31f69a9))

## [0.5.3](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.5.2...v0.5.3) (2026-04-17)


### Bug Fixes

* add .editorconfig and ansible.cfg files, update SSH_USER in configuration, and implement unit tests for logging and variable requirements ([5d93a7a](https://github.com/KevinDeBenedetti/k3s-lab/commit/5d93a7ae61cd44c0fb288c24062a119a2f692860))
* update platform-monitoring charts to version 0.6.0 and add new Grafana dashboards for Falco, Kubernetes, Tetragon, and Trivy ([aa2f621](https://github.com/KevinDeBenedetti/k3s-lab/commit/aa2f6218901d0d4f9325a144962a311179b75da7))

## [0.5.2](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.5.1...v0.5.2) (2026-04-17)


### Bug Fixes

* disable CodeQL analysis due to unsupported languages in the repository ([8c94631](https://github.com/KevinDeBenedetti/k3s-lab/commit/8c94631eb90c3174b7bfbc9f3e07c6997ebfb9e5))
* enable CodeQL analysis, improve error handling in k3s checks, and update WireGuard configuration ([71ac577](https://github.com/KevinDeBenedetti/k3s-lab/commit/71ac5773867cd87290e0b7482f7dbf4cdc9126e0))

## [0.5.1](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.5.0...v0.5.1) (2026-04-17)


### Bug Fixes

* enhance security and logging configurations across k3s and WireGuard setups ([0d1eac2](https://github.com/KevinDeBenedetti/k3s-lab/commit/0d1eac25c639972c7f25201385e1c9ee2a9176ce))

## [0.5.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.4.6...v0.5.0) (2026-04-17)


### Features

* add Grafana Loki datasource configuration and remove legacy datasource entries ([4c3e8d6](https://github.com/KevinDeBenedetti/k3s-lab/commit/4c3e8d630940f251db15eb0f71fc448d7e10a039))

## [0.4.6](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.4.5...v0.4.6) (2026-04-17)


### Bug Fixes

* update Helm chart versions to 0.4.5, refactor CI workflows, and enhance Grafana OAuth deployment ([74efec3](https://github.com/KevinDeBenedetti/k3s-lab/commit/74efec3406ea0ca0519af0e12ebc4afe8f52f24b))

## [0.4.5](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.4.4...v0.4.5) (2026-04-16)


### Bug Fixes

* refactor Makefiles and Scripts for Improved Structure and Functionality ([7d01cb9](https://github.com/KevinDeBenedetti/k3s-lab/commit/7d01cb98245b13904e4d1a3a887e985c3fc3fe43))

## [0.4.4](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.4.3...v0.4.4) (2026-04-16)


### Bug Fixes

* add scripts for Grafana OAuth deployment and Cloudflare API token seeding, enhance inventory generation ([62ca74e](https://github.com/KevinDeBenedetti/k3s-lab/commit/62ca74e013276a92432a2a152175d59e4c098859))

## [0.4.3](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.4.2...v0.4.3) (2026-04-16)


### Bug Fixes

* update Makefile and scripts for improved validation and secret management ([e88cfb9](https://github.com/KevinDeBenedetti/k3s-lab/commit/e88cfb900fd0541a2ac41ef3c5f879abcde8e675))

## [0.4.2](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.4.1...v0.4.2) (2026-04-16)


### Bug Fixes

* improve script initialization by adding dynamic sourcing for script-init.sh ([fa952ac](https://github.com/KevinDeBenedetti/k3s-lab/commit/fa952ac5578d8cf2b7fcbd644a71870c3a90dd6d))
* restructure documentation and deployment scripts for ArgoCD integration ([ed811d5](https://github.com/KevinDeBenedetti/k3s-lab/commit/ed811d552e6f3e4bf8d0a89e22ee194f31ece75d))

## [0.4.1](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.4.0...v0.4.1) (2026-04-16)


### Bug Fixes

* replace hardcoded vault pod name with variable for improved flexibility ([b859050](https://github.com/KevinDeBenedetti/k3s-lab/commit/b8590503fea5d033af5298b1080e65936253165d))

## [0.4.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.3.1...v0.4.0) (2026-04-16)


### Features

* enhance WireGuard role with improved key management and configuration updates ([7d6eb07](https://github.com/KevinDeBenedetti/k3s-lab/commit/7d6eb07233ffae82c4e408559cc3eca47fbf7eda))

## [0.3.1](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.3.0...v0.3.1) (2026-04-15)


### Bug Fixes

* refactor provisioning workflow to use Ansible ([cffe97b](https://github.com/KevinDeBenedetti/k3s-lab/commit/cffe97bcc5d230ce55245bd96387afaaa62074da))

## [0.3.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.2.1...v0.3.0) (2026-04-15)


### Features

* implement WireGuard role with configuration, handlers, and tasks ([340cf2f](https://github.com/KevinDeBenedetti/k3s-lab/commit/340cf2f54475771fdbe0348965e7f4a47d806683))
* update platform chart defaults and resource limits for security and monitoring components ([0683184](https://github.com/KevinDeBenedetti/k3s-lab/commit/0683184f5276424cc819f182844aaf083367ccbe))

## [0.2.1](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.2.0...v0.2.1) (2026-04-15)


### Bug Fixes

* update GitHub Actions to use checkout@v5 and setup-helm@v5 ([137af67](https://github.com/KevinDeBenedetti/k3s-lab/commit/137af671bf0960ce364cf885684894886afc652b))

## [0.2.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.1.0...v0.2.0) (2026-04-15)


### Features

* add release automation with release-please and update chart versions to 0.2.0 ([867ac1c](https://github.com/KevinDeBenedetti/k3s-lab/commit/867ac1c02f9a2f7f540d21f8ef2473c3cc541a9b))


### Bug Fixes

* remove deprecated Kubernetes manifests and Helm values for ExternalSecrets, Traefik, Grafana, and Vault ([49f56b1](https://github.com/KevinDeBenedetti/k3s-lab/commit/49f56b15ea36a167e8ba962dad9c7cc02c184f84))
