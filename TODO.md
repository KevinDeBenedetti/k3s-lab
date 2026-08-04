# TODO

## 🔴 En cours

## 🟡 À faire


## 🟢 Idées / backlog

## 🤖 Claude — recommandations

## ✅ Fait

- [x] 2026-08-04 — FEAT: surveiller le retard des pins d'`infra` sur les versions publiées. Nouveau `scripts/check-deployed-pins.sh` : quatrième question, distincte des trois autres veilles — les sections 1 et 2 demandent si ce qui tourne est vulnérable *aujourd'hui*, celle-ci si la production décroche silencieusement. C'est l'état qui a laissé `0.9.1` épinglée deux semaines après sa purge du registre, proxy figé en v3.7.1, pendant que tout le reste était vert. **Sévérité : seuil en nombre de releases, `--max-behind` (défaut 3)** — pas la sévérité d'`umbrella-pins` (qui échoue au moindre écart, légitimement, car l'umbrella *doit* pointer la dernière publiée), parce qu'épingler délibérément une version antérieure est normal et qu'un rouge quotidien devient un signal qu'on ne lit plus. Défaut 3 justifié par les faits : le dépôt a sorti 0.16.0 → 0.18.2 en moins de deux jours (donc 1 serait rouge presque tous les matins), alors que l'incident à attraper était à **sept** releases de retard. **Précision maximale demandée, obtenue** : le rapport donne le nombre exact de releases de retard (comptées comme releases réelles, pas comme delta de numéro), la liste ordonnée des versions intermédiaires, la version qui a périmé le pin et **depuis combien de jours** — cette dernière via l'annotation `org.opencontainers.image.created` du manifeste OCI, que `helm push` renseigne (dégradation propre si absente : « pas de date » plutôt que « publiée à l'instant »). Nouvelle `lib/registry.sh` (`registry_tags` extraite de `check-umbrella-pins.sh`, qui la consomme désormais — refactor vérifié non régressif, + `registry_tag_created`) et `applicationset_charts` dans `lib/chart-deps.sh` (énumère tous les charts épinglés : un contrôle qui ne connaîtrait que des noms en dur deviendrait aveugle le jour où un composant est ajouté à l'ApplicationSet). Câblé en section 3 de `traefik-advisories.yml`, résumé + corps d'issue inclus, avec la consigne explicite que la section 3 seule en échec ne signale **aucune vulnérabilité** — seulement une dérive. Vérifié sur les 5 chemins : prod actuelle (2 de retard, seuil 3 → exit 0, avertissements détaillés), pin à `0.12.0` (7 de retard → exit 1, « superseded by 0.14.0 (10d ago) »), même pin avec `--max-behind 10` → 0, prod avec `--max-behind 0` → 1, seuil non numérique → 2. 133 tests bats (+5 sur `applicationset_charts`, dont le piège du voisin et l'élément sans version), `actionlint` et `shellcheck --severity=warning` propres.
