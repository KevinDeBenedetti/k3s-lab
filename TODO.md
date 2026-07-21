# TODO

## 🔴 En cours

- [ ] FIX(URGENT): publier `platform-traefik` 0.13.3 avec le correctif `versionOverride`, puis purger 0.13.0–0.13.2 — les trois versions publiées sont impossibles à rendre (`ERROR: This version of the Chart only supports Traefik Proxy up to v3.7.4.`). Le correctif est en place et vérifié dans le working tree, il reste à commiter, merger et laisser la CI publier.
- [ ] FIX(URGENT): passer les trois pins de `infra/argocd/applicationsets/platform.yaml` (`cert-manager`, `external-secrets`, `traefik`) de `0.9.1` à `0.13.3` — `0.9.1` a été purgée de GHCR le 2026-07-21 (rétention alors à 5), d'où `ComparisonError: ghcr.io/…/platform-traefik:0.9.1: not found`. Les workloads tournent mais la réconciliation ArgoCD est morte (`selfHeal`/`prune` inopérants). **Bloqué tant que 0.13.3 n'est pas publiée** — ne surtout pas pointer vers 0.13.0–0.13.2. Contrôle : `kubectl -n argocd get applications -o "custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.spec.sources[0].targetRevision"`

## 🟡 À faire

- [ ] FIX: réaligner les 7 pins de dépendances de `charts/platform-deployment/Chart.yaml` sur la version du chart — elles pointent `0.13.0` alors que le chart est en `0.13.2`. Release-please ne bumpe que le champ `version:`, jamais les dépendances, donc l'écart se recreusera à chaque release.
- [ ] CHORE: purger ou marquer les versions cassées `platform-traefik` 0.13.0–0.13.2 sur GHCR, pour qu'aucune pin ne puisse y retomber.
- [ ] CHORE: retirer `traefik.image.tag` **et** `versionOverride` de `charts/platform-traefik/values.yaml` dès qu'un chart Traefik embarquera le proxy v3.7.8 ou plus — le dernier publié, `41.0.2`, plafonne à `v3.7.6`. Les deux clés vont de pair : `versionOverride` neutralise le garde-fou de version du subchart, le laisser traîner masquerait de vraies incompatibilités.

## 🟢 Idées / backlog

## 🤖 Claude — recommandations

- [ ] FEAT: aligner automatiquement les pins de `platform-deployment` sur la version du chart parent dans `release-charts.yml`, avant `helm dependency update` — cause racine du « pin qui n'avance jamais », rencontré quatre fois (traefik, ApplicationSet, umbrella, subchart).
- [ ] CHORE: ne jamais supprimer une GitHub Release pour annuler une version — release-please repart de la dernière Release, pas du manifest ; c'est ce qui a provoqué la boucle sur 1.2.0. Passer par un commit `Release-As:` ou un revert.
- [ ] TEST: ajouter un test de rendu qui vérifie que l'image traefik effectivement produite correspond à la version voulue — `helm template` seul valide la syntaxe, pas que `versionOverride` n'a pas silencieusement gelé la version.
- [ ] CHORE: confirmer ou corriger `appVersion: "0.1.0"` de `platform-vault-seeder` — c'est la version applicative du job, pas celle du chart.
- [ ] CHORE: auditer les autres ApplicationSets (`platform-vendor.yaml`, apps) à la recherche de pins figées du même type.
- [ ] DOCS: documenter la contrainte `traefik.io/proxy-max-version` dans le README de `platform-traefik` — le plafond du subchart est invisible depuis le chart parent et a causé deux pannes (2026-07-20 et 2026-07-21).

## ✅ Fait

- [x] 2026-07-22 — FIX: ajouter `versionOverride: v3.7.4` à `charts/platform-traefik/values.yaml` pour que le subchart 40.3.0 accepte le proxy v3.7.8. Vérifié par rendu hors ligne (subchart reconstitué depuis le tarball GitHub) : sans la clé le rendu échoue sur le garde-fou `traefik.io/proxy-max-version`, avec elle il produit `docker.io/traefik:v3.7.8`.
- [x] 2026-07-22 — FIX: activer `run-template: true` dans `.github/workflows/ci.yml` — `helm lint` seul ne fait pas `helm dependency update`, donc les garde-fous des subcharts ne sont jamais rendus. C'est ce trou qui a laissé publier un `platform-traefik` non rendable en 0.13.0, 0.13.1 puis 0.13.2 sans aucune alerte.
- [x] 2026-07-21 — FIX: corriger la publication des charts dans `release-charts.yml` — l'archive était choisie via `ls /tmp/charts/${chart_name}-*.tgz` ; le motif `platform-vault-*` capturait aussi `platform-vault-seeder-*.tgz`, et le glob `charts/*/` trie le seeder en premier (le slash final fait passer `-` avant `/`). Remplacé par le nom exact `${chart_name}-${version}.tgz`.
- [x] 2026-07-21 — CHORE: couvrir les 10 charts par release-please — `platform-deployment` et `platform-vault-seeder` ajoutés aux `extra-files` et alignés sur la version du repo.
- [x] 2026-07-21 — FIX: porter la rétention GHCR de `5` à `30` dans `cleanup-packages.yml`, avec le contexte de l'incident en commentaire.
- [x] 2026-07-21 — CHORE: purger les 22 versions `1.2.0`/`1.3.0`/`1.4.0` de GHCR — supérieures en semver à `0.13.0` tout en contenant du code plus ancien.
- [x] 2026-07-21 — FIX: réparer la boucle release-please, qui re-proposait 1.2.0 indéfiniment faute de baseline. Vérifié : `v0.13.1` puis `v0.13.2` se sont créées et taguées seules.
- [x] 2026-07-21 — CHORE: ramener le repo sur la ligne 0.x — il était passé en 1.x via un commit `Release-As: 1.2.0` du 2026-06-30. Renuméroté en `0.13.0`, tagué et releasé.
- [x] 2026-07-21 — FIX: bumper le subchart traefik `40.2.0` → `40.3.0` et pinner le proxy `v3.7.8`. Le CVE invoqué au départ (`CVE-2026-48020`, « StripPrefix auth bypass ») n'existe pas ; le vrai correctif est `v3.7.8`, qui couvre GHSA-8rxv-jg7p-wvg3 et GHSA-cxjq-mrr5-89rv.
