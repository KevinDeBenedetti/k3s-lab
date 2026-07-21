# TODO

## 🔴 En cours

- **Republier `platform-vault:0.13.1`** — seul chart manquant sur GHCR. La cause est
  corrigée dans `release-charts.yml` (voir ci-dessous) ; il suffit de merger le
  correctif, la publication est idempotente et ne reprendra que ce qui manque.
  Vérifier ensuite :
  `gh api /user/packages/container/charts%2Fplatform-vault/versions --jq '.[].metadata.container.tags[]?'`

## 🟡 À faire

- **Bumper les pins dans `infra/argocd/applicationsets/platform.yaml`** : `cert-manager`,
  `external-secrets` et `traefik` sont encore en `0.9.1` → passer à `0.13.0`
  (ou `0.13.1` une fois la publication réparée). **Urgent** : la purge GHCR du
  2026-07-21 (rétention alors à 5) a très probablement supprimé `platform-*:0.9.1`,
  que ces trois Applications ne peuvent donc plus résoudre.
- **Vérifier l'état de sync ArgoCD** après le bump : `argocd app list -o wide | grep platform-`.
- **Réaligner les pins de `charts/platform-deployment/Chart.yaml`** : le chart est en
  `0.13.1` mais ses 7 dépendances OCI pointent `0.13.0`. Release-please ne bumpe que
  le champ `version:`, jamais les dépendances — l'écart se recreusera à chaque release.
- **Retirer l'override `traefik.image.tag: v3.7.8`** de
  `charts/platform-traefik/values.yaml` dès qu'un chart Traefik embarquera `v3.7.8`
  ou plus (le dernier publié, `41.0.2`, en est à `v3.7.6`). Sinon il masquera
  silencieusement les futures montées d'appVersion.

## 🤖 Claude — recommandations

- **Automatiser l'alignement des pins de `platform-deployment`** sur la version du
  chart parent, dans `release-charts.yml` juste avant `helm dependency update`.
  C'est la cause racine du symptôme « pin qui n'avance jamais » rencontré trois fois
  aujourd'hui (traefik, ApplicationSet, umbrella).
- **Ne jamais supprimer une GitHub Release pour annuler une version.** C'est ce qui a
  cassé la baseline de release-please et provoqué la boucle sur 1.2.0 : il repart de
  la dernière Release, pas du manifest. Pour corriger une version, passer par un
  commit `Release-As:` ou un revert.
- **`appVersion: "0.1.0"` de `platform-vault-seeder`** n'a pas été touché (c'est la
  version applicative du job, pas celle du chart) — à confirmer ou corriger.
- **Auditer les autres ApplicationSets** (`platform-vendor.yaml`, apps) pour d'autres
  pins figées du même type.

## ✅ Fait

- **Traefik** — subchart `40.2.0` → `40.3.0` et pin `image.tag: v3.7.8`. Le CVE invoqué
  au départ (`CVE-2026-48020`, « StripPrefix auth bypass ») n'existe pas ; le vrai
  correctif est `v3.7.8`, qui couvre GHSA-8rxv-jg7p-wvg3 et GHSA-cxjq-mrr5-89rv.
- **Retour sur la ligne 0.x** — le repo était passé en 1.x via un commit
  `Release-As: 1.2.0` du 2026-06-30. Renuméroté en `0.13.0`, tagué et releasé.
- **Boucle release-please cassée** — elle re-proposait 1.2.0 indéfiniment faute de
  baseline. Vérifiée résolue : la release `v0.13.1` s'est créée et taguée seule.
- **Purge GHCR** — les 22 versions `1.2.0`/`1.3.0`/`1.4.0` supprimées ; elles étaient
  supérieures en semver à `0.13.0` tout en contenant du code plus ancien.
- **Rétention GHCR `5` → `30`** dans `cleanup-packages.yml`, avec le contexte de
  l'incident en commentaire.
- **Les 10 charts sont couverts par release-please** — `platform-deployment` et
  `platform-vault-seeder` ajoutés aux `extra-files` et alignés sur la version du repo.
- **Bug de publication des charts corrigé** — `release-charts.yml` déterminait
  l'archive à pousser via `ls /tmp/charts/${chart_name}-*.tgz`. Le motif
  `platform-vault-*` capturait aussi `platform-vault-seeder-*.tgz`, et le glob
  `charts/*/` trie le seeder en premier (avec le slash final, `-` passe avant `/`) :
  `helm push` recevait deux chemins et échouait. Latent depuis toujours, révélé par
  l'ajout de `platform-vault-seeder` à release-please, qui fait désormais bumper les
  deux charts dans la même passe. Remplacé par le nom exact `${chart_name}-${version}.tgz`.
