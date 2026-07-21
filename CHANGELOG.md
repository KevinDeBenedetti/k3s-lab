# Changelog

## [1.2.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.13.0...v1.2.0) (2026-07-21)


### Features

* add .vitepressrc.json for VitePress configuration ([bb50f0c](https://github.com/KevinDeBenedetti/k3s-lab/commit/bb50f0cf857c6f021cdc094960afe5e2962460b7))
* add ArgoCD deployment and configuration with VPN-only access and OIDC support ([af14743](https://github.com/KevinDeBenedetti/k3s-lab/commit/af147435a61720cde459e26a631a4f67f8e72996))
* add auto-tagging on chart version bump to trigger OCI chart releases ([6d926cc](https://github.com/KevinDeBenedetti/k3s-lab/commit/6d926cc6be394e7d0fa3c9d6296a24f4c8ab423e))
* add CI/CD workflow for linting, testing, and security checks ([c5189ae](https://github.com/KevinDeBenedetti/k3s-lab/commit/c5189aeb17aa8b4129c610072e7b3e01d8383c59))
* add cluster status reporting targets in Makefile for monitoring nodes and pods ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* add deploy-monitoring script for observability stack deployment ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* add deployment and configuration guide for ArgoCD applications ([660e8d5](https://github.com/KevinDeBenedetti/k3s-lab/commit/660e8d5b56cf41e73645408847bb83d3eca6dd96))
* add docs link check to CI/CD workflow and update documentation links to be relative ([555a331](https://github.com/KevinDeBenedetti/k3s-lab/commit/555a3314372b83a5516210deffee180a3627bcad))
* add extend section to gitleaks configuration for default usage ([1c880df](https://github.com/KevinDeBenedetti/k3s-lab/commit/1c880df6417ff887a0e5513831098387e3eab6a1))
* add get-kubeconfig script for fetching and merging kubeconfig from master ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* add gitleaks configuration to ignore Makefile loop variable credentials ([3f12530](https://github.com/KevinDeBenedetti/k3s-lab/commit/3f1253083516263b5ec9a4540bd6fccd9b190464))
* add Grafana Loki datasource configuration and remove legacy datasource entries ([4c3e8d6](https://github.com/KevinDeBenedetti/k3s-lab/commit/4c3e8d630940f251db15eb0f71fc448d7e10a039))
* add HashiCorp Vault and External Secrets Operator integration with deployment scripts and configuration ([9fc52df](https://github.com/KevinDeBenedetti/k3s-lab/commit/9fc52df949c5fe103e80b06537a31aec11c6e47e))
* add kubeconfig fetching target in Makefile for easier access to cluster ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* add Lima VM configurations and tests for k3s and Debian VPS ([2243ab6](https://github.com/KevinDeBenedetti/k3s-lab/commit/2243ab60c7f51a899cbbf9c360f0dd6556c3e4f5))
* add OAuth2/SSO support for Grafana using Kubernetes Secret configuration ([99f9216](https://github.com/KevinDeBenedetti/k3s-lab/commit/99f9216e758c97e0b8ef904ade843b2d41d51bf6))
* add platform charts for ArgoCD, monitoring, security, and vault ([668d22f](https://github.com/KevinDeBenedetti/k3s-lab/commit/668d22febdc4f74649d40c27e0704013258efef9))
* add platform-cert-manager and platform-external-secrets Helm charts with initial configurations ([6976456](https://github.com/KevinDeBenedetti/k3s-lab/commit/6976456ad238a2077d7096859c7db033b31f69a9))
* add platform-traefik Helm chart with initial configuration and values ([00f3c34](https://github.com/KevinDeBenedetti/k3s-lab/commit/00f3c34fc2330bcf8437e06d91489258735517dd))
* add release automation with release-please and update chart versions to 0.2.0 ([867ac1c](https://github.com/KevinDeBenedetti/k3s-lab/commit/867ac1c02f9a2f7f540d21f8ef2473c3cc541a9b))
* add renovate.json configuration for dependency management ([c6e0888](https://github.com/KevinDeBenedetti/k3s-lab/commit/c6e08886122446a592db919c51ba73bcd13dec2a))
* add root Taskfile.yml for standalone k3s-lab usage ([2fc313e](https://github.com/KevinDeBenedetti/k3s-lab/commit/2fc313e6cfa1c20735eece5b3db81bc031616acc))
* add SSH options helper script and build SSH_OPTS array from environment variables ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* add Traefik ServiceMonitor configuration and update deploy-monitoring.sh to apply it ([9e6de9b](https://github.com/KevinDeBenedetti/k3s-lab/commit/9e6de9b2c784b76c796bfcffe5c86906162295dd))
* Add vault-seeder Helm chart with job configurations and validation scripts ([7dc5d8e](https://github.com/KevinDeBenedetti/k3s-lab/commit/7dc5d8e1e8d76763db6a21c88508eefda686c3b7))
* **ansible/roles/common:** add log-only config for chkrootkit daily scan ([3f7b080](https://github.com/KevinDeBenedetti/k3s-lab/commit/3f7b080377bf6f24740ba83a3f075090e96b359f))
* **ansible:** add dynamic MOTD for server overview on SSH login ([f9381ca](https://github.com/KevinDeBenedetti/k3s-lab/commit/f9381ca174800861fca65bbdeded2e19fabb51f3))
* **charts/platform-vault-seeder/templates/configmap-apps.yaml:** update URL encoding for sensitive values ([1916a41](https://github.com/KevinDeBenedetti/k3s-lab/commit/1916a41eb61e92ac5d21ea03d961cdfb30a24a0b))
* **charts:** update chart versions and dependencies for platform-argocd, platform-external-secrets, platform-monitoring, platform-security, and platform-traefik ([8756683](https://github.com/KevinDeBenedetti/k3s-lab/commit/8756683a3aad18a08f66b95db67ead7eec47f67e))
* create deploy-stack script for bootstrapping the base cluster stack ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* create help target in Makefile to display available commands ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* **docs:** Add monitoring and observability documentation ([61f7146](https://github.com/KevinDeBenedetti/k3s-lab/commit/61f7146774a24074f1aea77d2352e209f4c8ee61))
* **docs:** Add troubleshooting guide for k3s, Traefik, cert-manager, and monitoring ([61f7146](https://github.com/KevinDeBenedetti/k3s-lab/commit/61f7146774a24074f1aea77d2352e209f4c8ee61))
* **docs:** Document cert-manager installation and usage ([61f7146](https://github.com/KevinDeBenedetti/k3s-lab/commit/61f7146774a24074f1aea77d2352e209f4c8ee61))
* **docs:** Document Traefik ingress controller setup ([61f7146](https://github.com/KevinDeBenedetti/k3s-lab/commit/61f7146774a24074f1aea77d2352e209f4c8ee61))
* **docs:** Introduce k3s documentation ([61f7146](https://github.com/KevinDeBenedetti/k3s-lab/commit/61f7146774a24074f1aea77d2352e209f4c8ee61))
* enable Traefik ServiceMonitor in deploy-monitoring.sh and update deploy-stack.sh for improved observability ([136a29c](https://github.com/KevinDeBenedetti/k3s-lab/commit/136a29cf23976798930bbdb6a34a75a296165f6e))
* enhance _k8s_file function to use a shared temp directory for remote downloads ([6bffabf](https://github.com/KevinDeBenedetti/k3s-lab/commit/6bffabff1efae97e0642bfa041e32e5cf1b980bc))
* enhance documentation with usage guide for private infra repo and update make targets reference ([f320214](https://github.com/KevinDeBenedetti/k3s-lab/commit/f32021485b18e0e46878cf8fbbd058da12362801))
* enhance makefile functionality with shared cache management and improve Vault initialization script ([ac56740](https://github.com/KevinDeBenedetti/k3s-lab/commit/ac5674046e841e663d3fa458cd616f6f283e3cc8))
* enhance vault deployment script with status checks and improved initialization prompts ([2a9e9a6](https://github.com/KevinDeBenedetti/k3s-lab/commit/2a9e9a6597587ebf510dba7e27bf39667e301f52))
* enhance Vault deployment with OIDC support, add service-registration RBAC, and update Traefik configurations ([0949d4b](https://github.com/KevinDeBenedetti/k3s-lab/commit/0949d4be8ba5f0769f47713f2e2f038b5ea58f19))
* enhance vault initialization and seeding process with improved prompts and error handling ([93ae47b](https://github.com/KevinDeBenedetti/k3s-lab/commit/93ae47b27dc71f438bb30f7be9fc97f21a303248))
* enhance WireGuard role with improved key management and configuration updates ([7d6eb07](https://github.com/KevinDeBenedetti/k3s-lab/commit/7d6eb07233ffae82c4e408559cc3eca47fbf7eda))
* **helm:** Add platform-deployment umbrella chart (v0.1.0) ([26271c0](https://github.com/KevinDeBenedetti/k3s-lab/commit/26271c007ae335b4777bb461a66692c46c4d63e8))
* implement dual-mode execution for scripts and enhance Makefile structure ([0cb28cb](https://github.com/KevinDeBenedetti/k3s-lab/commit/0cb28cb275d392cf071d02962f2d0d72299a069c))
* implement external-dns for automatic Cloudflare DNS management and update Traefik version ([1dec7ff](https://github.com/KevinDeBenedetti/k3s-lab/commit/1dec7ff40d941bbd4fbdd8b00f918743062ed382))
* implement k3s installation and management targets in Makefile ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* implement SSH access targets in Makefile for master and worker nodes ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* implement WireGuard role with configuration, handlers, and tasks ([340cf2f](https://github.com/KevinDeBenedetti/k3s-lab/commit/340cf2f54475771fdbe0348965e7f4a47d806683))
* introduce stack deployment targets in Makefile for observability and logging ([923d366](https://github.com/KevinDeBenedetti/k3s-lab/commit/923d366b1f3bf62bd7de51aae090871a329c821c))
* **kubernetes:** add Kustomize components for app modularity ([e3d5c04](https://github.com/KevinDeBenedetti/k3s-lab/commit/e3d5c04267a99981d18554371fa10f173fa3e30f))
* Refactor k3s setup and WireGuard integration ([cd42538](https://github.com/KevinDeBenedetti/k3s-lab/commit/cd4253810176f9ed5043865e44c80dfcbf74e979))
* remove VitePress configuration file ([281e535](https://github.com/KevinDeBenedetti/k3s-lab/commit/281e535e8f0aa1ef21216d4603976fdabe42efe1))
* **scripts:** add vault-seed.sh — extracted from vault.mk inline shell ([d6ad15e](https://github.com/KevinDeBenedetti/k3s-lab/commit/d6ad15e29810432ed244fb5c7d6cbe6b0b1291d0))
* **taskfiles:** add argocd.yml — ArgoCD deployment and management tasks ([ae60dc2](https://github.com/KevinDeBenedetti/k3s-lab/commit/ae60dc2cd976049f7b34f0801ffb2c15e987eb6f))
* **taskfiles:** add deploy.yml — secret creation and grafana oauth tasks ([37d2ece](https://github.com/KevinDeBenedetti/k3s-lab/commit/37d2ece42aae3d17736dbff8df70b42b08f72519))
* **taskfiles:** add provision.yml — Ansible provisioning tasks ([daa15d3](https://github.com/KevinDeBenedetti/k3s-lab/commit/daa15d3328e94634503bc2803036fa84f379f53f))
* **taskfiles:** add ssh.yml — SSH access tasks ([fdbac45](https://github.com/KevinDeBenedetti/k3s-lab/commit/fdbac45cca8c9f2149c43728fc50b2181058ca13))
* **taskfiles:** add status.yml — cluster status and health check tasks ([98cf48a](https://github.com/KevinDeBenedetti/k3s-lab/commit/98cf48a2afbe92396b05bd86fd7ae193637bf5f9))
* **taskfiles:** add vault.yml — Vault + ESO tasks ([2a8b61c](https://github.com/KevinDeBenedetti/k3s-lab/commit/2a8b61c3e046d851657a581268b3867da30d67ab))
* **taskfiles:** update argocd and vault taskfiles for improved admin commands ([fecdcff](https://github.com/KevinDeBenedetti/k3s-lab/commit/fecdcff5ffaacc14fc0c424a50ee2c72edf79d50))
* update CI workflows and cleanup packages; refine vault configurations and documentation ([d095987](https://github.com/KevinDeBenedetti/k3s-lab/commit/d095987938853e2981dc425fa83478623c1c9bba))
* update CI/CD workflows for enhanced documentation dispatch and scheduling ([2aee789](https://github.com/KevinDeBenedetti/k3s-lab/commit/2aee789286c69e461fd4505c769afb7174704aed))
* update configuration files and scripts for agent role, OIDC support, and improved prompts ([b73349f](https://github.com/KevinDeBenedetti/k3s-lab/commit/b73349f7ccc89b779d186ccc720b50f1e49fa5b7))
* update deploy-stack script to include Prometheus Operator CRDs and adjust step numbering ([8f4ce98](https://github.com/KevinDeBenedetti/k3s-lab/commit/8f4ce984a6f8b10bdc27d416c1a33752e19672d1))
* update lima-run-script to use pipe for script execution in Lima VMs ([b3adbde](https://github.com/KevinDeBenedetti/k3s-lab/commit/b3adbde2bc7446ec046865e07211665650265032))
* update platform chart defaults and resource limits for security and monitoring components ([0683184](https://github.com/KevinDeBenedetti/k3s-lab/commit/0683184f5276424cc819f182844aaf083367ccbe))
* update README to streamline features and prerequisites sections ([bfac4c7](https://github.com/KevinDeBenedetti/k3s-lab/commit/bfac4c74f52c49cf613c391795b957685f3fff01))
* **vault.mk:** add VAULT_CONFIGURE_SCRIPT / VAULT_SEED_SCRIPT override hooks ([6719158](https://github.com/KevinDeBenedetti/k3s-lab/commit/6719158df3736b0fce5109e6d66d51feac7c852c))


### Bug Fixes

* add .editorconfig and ansible.cfg files, update SSH_USER in configuration, and implement unit tests for logging and variable requirements ([5d93a7a](https://github.com/KevinDeBenedetti/k3s-lab/commit/5d93a7ae61cd44c0fb288c24062a119a2f692860))
* add platform-security chart dependencies and their respective packages ([294e9e4](https://github.com/KevinDeBenedetti/k3s-lab/commit/294e9e433a0cfe69f8ac867ec27278c4a9eaf075))
* add retry logic for helm dependency update in release workflow ([3bfaf09](https://github.com/KevinDeBenedetti/k3s-lab/commit/3bfaf09296c05d1aaeaf624f3b78e28d3485aa70))
* add scripts for Grafana OAuth deployment and Cloudflare API token seeding, enhance inventory generation ([62ca74e](https://github.com/KevinDeBenedetti/k3s-lab/commit/62ca74e013276a92432a2a152175d59e4c098859))
* **ci:** Fix GitHub Actions validation for platform-deployment chart ([f3d6960](https://github.com/KevinDeBenedetti/k3s-lab/commit/f3d6960e63cbfe8df5b647cc77af9542d0526301))
* correct capitalization of repository title in vitepress configuration ([a685b22](https://github.com/KevinDeBenedetti/k3s-lab/commit/a685b22398cfafcae65a3b933ff01f3f7f0c173d))
* correct K3S_LAB assignment in Makefile for proper path resolution ([f9e8a2f](https://github.com/KevinDeBenedetti/k3s-lab/commit/f9e8a2f4e9723085ee4b517f296c5b120d76d0ac))
* disable CodeQL analysis due to unsupported languages in the repository ([8c94631](https://github.com/KevinDeBenedetti/k3s-lab/commit/8c94631eb90c3174b7bfbc9f3e07c6997ebfb9e5))
* enable CodeQL analysis, improve error handling in k3s checks, and update WireGuard configuration ([71ac577](https://github.com/KevinDeBenedetti/k3s-lab/commit/71ac5773867cd87290e0b7482f7dbf4cdc9126e0))
* enhance Falco dashboard with improved metrics, dynamic data sources, and updated visualizations ([76d56d4](https://github.com/KevinDeBenedetti/k3s-lab/commit/76d56d482ba69fa4ad26def11c801b7503f3f5b9))
* enhance security and logging configurations across k3s and WireGuard setups ([0d1eac2](https://github.com/KevinDeBenedetti/k3s-lab/commit/0d1eac25c639972c7f25201385e1c9ee2a9176ce))
* **gitleaks:** add global allowlist for historical commits with placeholder values ([b57496a](https://github.com/KevinDeBenedetti/k3s-lab/commit/b57496ad953e6946f37cbdfa4b825f085bedf9eb))
* improve script initialization by adding dynamic sourcing for script-init.sh ([fa952ac](https://github.com/KevinDeBenedetti/k3s-lab/commit/fa952ac5578d8cf2b7fcbd644a71870c3a90dd6d))
* **makefiles:** Update paths for k3s-lab ([61f7146](https://github.com/KevinDeBenedetti/k3s-lab/commit/61f7146774a24074f1aea77d2352e209f4c8ee61))
* **platform-argocd:** bump to 0.9.2 — increase controller memory default to 2Gi (OOMKill prevention) ([5909fcf](https://github.com/KevinDeBenedetti/k3s-lab/commit/5909fcf2e7de931f6a20432300fc323a45492aa4))
* refactor Makefiles and Scripts for Improved Structure and Functionality ([7d01cb9](https://github.com/KevinDeBenedetti/k3s-lab/commit/7d01cb98245b13904e4d1a3a887e985c3fc3fe43))
* refactor Makefiles to Taskfiles and Update Load Env Script ([e7d7783](https://github.com/KevinDeBenedetti/k3s-lab/commit/e7d77832b8490da69405813be1bfc498c6c1f7c0))
* refactor provisioning workflow to use Ansible ([cffe97b](https://github.com/KevinDeBenedetti/k3s-lab/commit/cffe97bcc5d230ce55245bd96387afaaa62074da))
* remove deprecated Kubernetes manifests and Helm values for ExternalSecrets, Traefik, Grafana, and Vault ([49f56b1](https://github.com/KevinDeBenedetti/k3s-lab/commit/49f56b15ea36a167e8ba962dad9c7cc02c184f84))
* remove obsolete test scripts and configuration files for Lima and k3s ([678061c](https://github.com/KevinDeBenedetti/k3s-lab/commit/678061ce9a04f10b3e197ac9a0aab37587c243d0))
* remove stale context/cluster/user from kubeconfig to prevent x509/Unauthorized errors ([080b48c](https://github.com/KevinDeBenedetti/k3s-lab/commit/080b48c92ae87527940626a528ea90304837e8e7))
* remove unnecessary issues permission from release workflow ([99d4945](https://github.com/KevinDeBenedetti/k3s-lab/commit/99d4945daaf8775397bf31f1d36ece15af1be817))
* replace hardcoded vault pod name with variable for improved flexibility ([b859050](https://github.com/KevinDeBenedetti/k3s-lab/commit/b8590503fea5d033af5298b1080e65936253165d))
* restore issues permission in release workflow ([78a703a](https://github.com/KevinDeBenedetti/k3s-lab/commit/78a703aba90e511f21f54c3390b297ca20fd1523))
* restructure documentation and deployment scripts for ArgoCD integration ([ed811d5](https://github.com/KevinDeBenedetti/k3s-lab/commit/ed811d552e6f3e4bf8d0a89e22ee194f31ece75d))
* security ([2822852](https://github.com/KevinDeBenedetti/k3s-lab/commit/2822852eeb1a8738f11d6819deeccc76966471ea))
* security & improvements ([cb7d1be](https://github.com/KevinDeBenedetti/k3s-lab/commit/cb7d1be76670aa19c5414aa092f539bef5db9e57))
* **traefik:** bump subchart 40.2.0 -&gt; 40.3.0 and pin proxy v3.7.8 ([7c84052](https://github.com/KevinDeBenedetti/k3s-lab/commit/7c840527bf8f2a35f19588286f8ecfba050dbad3))
* update docs dispatch job to correct PAT_TOKEN permissions and change workflow file reference ([bbb38e0](https://github.com/KevinDeBenedetti/k3s-lab/commit/bbb38e0f935dd05bdf814513a9f3fa7110cc9d8e))
* update environment variable names in CI/CD configuration ([77df697](https://github.com/KevinDeBenedetti/k3s-lab/commit/77df697d4bb813ce2af6f3d8d3a84205259d6374))
* update GitHub Actions to use checkout@v5 and setup-helm@v5 ([137af67](https://github.com/KevinDeBenedetti/k3s-lab/commit/137af671bf0960ce364cf885684894886afc652b))
* update Helm chart versions to 0.4.5, refactor CI workflows, and enhance Grafana OAuth deployment ([74efec3](https://github.com/KevinDeBenedetti/k3s-lab/commit/74efec3406ea0ca0519af0e12ebc4afe8f52f24b))
* update kubeconform exclude pattern to correctly match values files ([4fa7eb7](https://github.com/KevinDeBenedetti/k3s-lab/commit/4fa7eb728a99921e8357bb7782463bab1333510e))
* update kubeconform exclusion patterns to include kustomization.yaml ([6c1b099](https://github.com/KevinDeBenedetti/k3s-lab/commit/6c1b0992ba90683b1eb5495217be62173150d430))
* update Makefile and scripts for improved validation and secret management ([e88cfb9](https://github.com/KevinDeBenedetti/k3s-lab/commit/e88cfb900fd0541a2ac41ef3c5f879abcde8e675))
* update platform-monitoring charts to version 0.6.0 and add new Grafana dashboards for Falco, Kubernetes, Tetragon, and Trivy ([aa2f621](https://github.com/KevinDeBenedetti/k3s-lab/commit/aa2f6218901d0d4f9325a144962a311179b75da7))
* update platform-security chart dependencies to existing versions ([6380b0b](https://github.com/KevinDeBenedetti/k3s-lab/commit/6380b0bbb2a6186c7e90b56b574026404fca4870))
* update Prometheus queries in Grafana Falco dashboard to use correct metric names ([e0e50c6](https://github.com/KevinDeBenedetti/k3s-lab/commit/e0e50c605c818743ddea21953bf74d028ed7b9b7))
* update registry path handling in release charts workflow ([8519fa9](https://github.com/KevinDeBenedetti/k3s-lab/commit/8519fa9e36b33b73c5b8ebac88288ce4072e4448))
* update release-please config to include platform-cert-manager and platform-external-secrets, and update platform-traefik version to 0.1.1 ([610ff0b](https://github.com/KevinDeBenedetti/k3s-lab/commit/610ff0b7bc61cc62ea88cdcbd1ed26c67a6128b9))
* update SSH_SERVER_HOST variable and improve error handling in SSH makefile ([cbf0024](https://github.com/KevinDeBenedetti/k3s-lab/commit/cbf0024e3a21a8d691b03599cfae26d798a71da1))
* update Traefik values.yaml to correct HTTP to HTTPS redirection configuration ([9aeaf00](https://github.com/KevinDeBenedetti/k3s-lab/commit/9aeaf00a8f50e3886fa655bbe0812a9f28f57f0c))
* update wireguard ([81a9788](https://github.com/KevinDeBenedetti/k3s-lab/commit/81a97881935f677df07ad5575b54d7616e65b25c))


### Miscellaneous Chores

* release 1.2.0 ([686d7c9](https://github.com/KevinDeBenedetti/k3s-lab/commit/686d7c9b9afe3ae18559eb094f477f169b453cac))

## [0.13.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.12.0...v0.13.0) (2026-07-21)

Les versions 1.2.0, 1.3.0 et 1.4.0 ont été produites par erreur (commit
`Release-As: 1.2.0`) et n'ont jamais été taguées ni releasées. Elles sont
renumérotées ici en 0.13.0 pour rester sur la ligne 0.x.


### Features

* **charts/platform-vault-seeder/templates/configmap-apps.yaml:** update URL encoding for sensitive values ([1916a41](https://github.com/KevinDeBenedetti/k3s-lab/commit/1916a41eb61e92ac5d21ea03d961cdfb30a24a0b))
* **ansible/roles/common:** add log-only config for chkrootkit daily scan ([3f7b080](https://github.com/KevinDeBenedetti/k3s-lab/commit/3f7b080377bf6f24740ba83a3f075090e96b359f))

## [0.12.0](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.11.2...v0.12.0) (2026-06-29)


### Features

* **ansible:** add dynamic MOTD for server overview on SSH login ([f9381ca](https://github.com/KevinDeBenedetti/k3s-lab/commit/f9381ca174800861fca65bbdeded2e19fabb51f3))

## [0.11.2](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.11.1...v0.11.2) (2026-06-16)


### Bug Fixes

* update wireguard ([81a9788](https://github.com/KevinDeBenedetti/k3s-lab/commit/81a97881935f677df07ad5575b54d7616e65b25c))

## [0.11.1](https://github.com/KevinDeBenedetti/k3s-lab/compare/v0.11.0...v0.11.1) (2026-06-11)


### Bug Fixes

* security ([2822852](https://github.com/KevinDeBenedetti/k3s-lab/commit/2822852eeb1a8738f11d6819deeccc76966471ea))
* security & improvements ([cb7d1be](https://github.com/KevinDeBenedetti/k3s-lab/commit/cb7d1be76670aa19c5414aa092f539bef5db9e57))

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
