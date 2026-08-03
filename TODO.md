# TODO

## 🔴 En cours

## 🟡 À faire

- [ ] FIX(URGENT): pousser le bump des pins de `infra/argocd/applicationsets/platform.yaml` vers `0.16.0` — constaté le 2026-08-03 en interrogeant le cluster : **la production tourne sur `traefik v3.7.1`**, pas v3.7.9. Le bump du 2026-08-01 (0.9.1 → 0.15.0) n'a jamais été commité ni poussé ; `origin/main` d'infra pinne toujours `0.9.1`, purgé de GHCR, donc `platform-traefik` et `platform-external-secrets` sont gelés en `ComparisonError` (`Sync: Unknown`) — la panne silencieuse documentée dans le fichier lui-même. v3.7.1 est couverte par **10 plages d'advisories**, dont `GHSA-5r4w-85f3-pw66` (HIGH, bypass mTLS SNICheck, ≤ v3.7.1), `GHSA-x677-9fxg-v5c5` (HIGH, spoofing d'identité ForwardAuth, ≤ v3.7.5), `GHSA-cxjq-mrr5-89rv` et `GHSA-3ccp-42pg-hgv6`. Cible : `0.16.0` (publié le 2026-08-01, v3.7.9 natif via subchart 41.1.0, vérifié sur GHCR le 2026-08-03, les 3 charts répondent 200). L'app-of-apps `root` suit `infra` main → le push mettra à jour l'ApplicationSet, et `automated` + `selfHeal` fera le reste.
- [ ] CHORE: créer le secret `INFRA_READ_TOKEN` sur `k3s-lab` (PAT en lecture seule sur `KevinDeBenedetti/infra`) — sans lui, la veille quotidienne ne contrôle que la version que le repo déploierait, jamais celle qui tourne. Elle le signale par un `::warning::` à chaque run, mais un avertissement sur un run vert se lit mal : c'est précisément la moitié la plus importante du contrôle qui reste éteinte tant que le secret n'existe pas.
- [ ] TEST: étendre `check-deployed-traefik.sh` aux autres charts déployés — `platform-cert-manager` et `platform-external-secrets` sont épinglés dans le même ApplicationSet et personne ne confronte leurs versions amont à quoi que ce soit. La mécanique (pin → chart publié → contenu réel) est déjà écrite et générique ; il manque la source d'advisories par composant, qui n'est pas forcément un dépôt GitHub comme pour Traefik.
- [ ] REFACTOR: `scripts/check-deployed-traefik.sh` code en dur `kevindebenedetti/charts/platform-traefik` comme chemin de registre par défaut, alors que l'ApplicationSet porte déjà le `repoURL` — le lire de là éviterait une troisième copie de la même vérité. Sans effet aujourd'hui (les deux coïncident), mais c'est exactement la classe de duplication qui a produit les dérives de pins.

## 🟢 Idées / backlog

## 🤖 Claude — recommandations



## ✅ Fait

- [x] 2026-08-03 — CHORE: republier `platform-traefik` — résolu par la release **v0.16.0** (2026-08-01 22:55 UTC, commit `ea6246c`), qui a embarqué `7a24f7b`. Vérifié en direct sur GHCR le 2026-08-03, les deux artefacts côte à côte : le 0.16.0 publié porte bien le subchart **41.1.0** (`Chart.yaml` + `Chart.lock`), **aucun `image.tag`** dans ses values, et l'`appVersion` du subchart embarqué est **v3.7.9** — il atteint donc la version saine nativement, par le chemin robuste, là où le 0.15.0 n'y arrivait que par son pin au-dessus d'un subchart en v3.7.6. `check-deployed-traefik.sh --chart-version 0.16.0` passe : 77 plages évaluées, proxy propre. La divergence source/artefact est fermée. Reste le pin de l'ApplicationSet (0.15.0 → 0.16.0), ré-ouvert en tâche dédiée ci-dessus.
