# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] CHORE: trancher sur `platform-deployment` — soit l'ApplicationSet infra le déploie, soit on retire le chart et ses scripts de pins (corvée d'alignement récurrente pour un artefact non consommé) — §4

## 🟢 Idées / backlog

## 🤖 Claude — recommandations
- [ ] FIX: le pin `hashicorp/vault:1.21.2` de `charts/platform-vault/values.yaml` est écrasé par infra (cluster en 1.21.4) — généraliser `check-traefik-image.sh` en check par chart — §8
- [ ] DOCS: rafraîchir ou supprimer les pins de version périmés de `.env.example` (ArgoCD 7.8.26 vs 9.5.17, Loki 6.x vs 7.0.0) — §9
- [ ] FIX: `failedJobsHistoryLimit` sur les CronJobs `vault-auto-unseal` / `portfolio-purge`, et corriger la détection du seal status qui lit mal sa propre sortie saine — §10
- [ ] CHORE: remplacer `kevin@example.com` dans `charts/platform-deployment/Chart.yaml` — publié sur GHCR à chaque release — §11
- [ ] CHORE: ajouter un updater (dependabot.yml ou renovate.json) pour les `uses:` maintenant épinglés sur SHA — sans lui les pins sont immuables donc silencieusement périmés
- [ ] DOCS: `docs/configuration.md:52` affirme que les versions sont gérées par Renovate « via le preset partagé dans `renovate.json` » — ce fichier n'existe pas dans ce repo
- [ ] CHORE: étape 2 du rollout `platform-security` — une fois les CRD Kyverno enregistrées, bumper le pin infra sur la première version publiée après le 2026-08-05 et passer `kyvernoPolicies.enabled` à `true`
- [ ] TEST: aucun test ne couvre le rendu de `platform-security` (policies Audit/Enforce, trivy-operator off) — un `helm template` en bats figerait le contrat

## ✅ Fait
- [x] 2026-08-06 — FIX: `k3s_installer_checksum` renseigné dans les rôles k3s_server et k3s_agent (sha256 de get.k3s.io vérifié stable sur deux téléchargements) — plus de script exécuté en root sans vérification
- [x] 2026-08-06 — FIX: `permissions: contents: read` au niveau workflow dans `ci.yml` — vérifié que les 2 jobs consommant `GITHUB_TOKEN` fonctionnent sans token du tout
- [x] 2026-08-06 — FIX: les 6 reusable workflows et les 4 actions tierces épinglés sur SHA 40 caractères — SHA résolus = exactement ce que `@main`/`@v5` pointaient déjà, donc aucun changement de comportement
- [x] 2026-08-05 — FIX(URGENT): 6 pins infra réalignés sur 0.18.3 (rendu revalidé chart par chart ; ArgoCD 0.9.2→0.18.3 ne change pas la version d'ArgoCD, argo-cd reste 9.5.17/v3.4.3) et `traefik-advisories` échoue désormais si `INFRA_READ_TOKEN` est absent
- [x] 2026-08-05 — FIX(URGENT): seuil CVE bloquant — alerte `TrivyUnacceptedCriticalCVEs` (severity critical) sur les 17 CRITICAL d'images non triées, invisibles des 2 règles existantes ; description de baseline périmée corrigée ; §2 de l'audit corrigé (chiffres non dédupliqués)
- [x] 2026-08-05 — FIX(URGENT): déployer `platform-security` — policies en `Audit` configurable, trivy-operator désactivé (doublon amont), entrée ajoutée à l'ApplicationSet infra en rollout 2 étapes
- [x] 2026-08-05 — FEAT: full audit of the repo, track security vulnerabilities, verify everything is working, make recommandations
