# Changelog

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
