# TODO

## 🔴 En cours

## 🟡 À faire


## 🟡 À faire (manuellement, étapes détaillées pas à pas)
- [ ] TEST: le job CI `k3s-lab-pin` n'a jamais tourné (ajouté depuis un sandbox sans accès Actions) — surveiller la première exécution : si l'image du runner n'a pas `git`, `actions/checkout` bascule sur le tarball et l'assertion échouera volontairement. NB 2026-08-17 : le runner est l'image officielle `ghcr.io/actions/actions-runner:2.335.1`, et l'étape `Assert the submodule is really checked out` fait échouer le job avec un message explicite plutôt que de passer vert à vide — le mode de défaillance est donc bruyant. Reste à confirmer sur un run réel.
- [ ] TEST: aucun check ne relie un CronJob à la version d'app qui expose l'endpoint qu'il appelle — le purge tapait une route absente de l'image depuis sa création, et rien n'a rien dit pendant des semaines. ⚠ 2026-08-17 : **hors de ce dépôt** — `grep -rl "kind: CronJob" charts/ kubernetes/` ne renvoie rien, il n'y a aucun CronJob ici. Le CronJob `portfolio/purge` et le Deployment dont il faudrait comparer la version vivent tous les deux dans le dépôt infra ; le check doit y être écrit.
- [ ] CHORE: migrer `infra/platform/security/values.yaml:51` de `kyvernoPolicies.validationFailureAction` vers `failureAction`, puis retirer l'alias déprécié du helper — l'alias n'existe que pour ce consommateur, et le test « the deprecated validationFailureAction value key still overrides » est là pour rendre sa suppression délibérée. ⚠ 2026-08-17 : **bloqué par ordonnancement inter-dépôts, et c'est voulu** — `charts/platform-security/templates/_helpers.tpl:41` dit noir sur blanc « Remove the alias only once infra sets `failureAction` ». Il n'y a pas de `infra/` ici : la première moitié (migrer le values infra) doit être faite dans l'autre dépôt et déployée AVANT que l'alias puisse tomber ici. Retirer l'alias maintenant casserait le consommateur en production.


## 🟢 Idées / backlog

## 🤖 Claude — recommandations
- [ ] CHORE: infra épingle `platform-security` à `0.18.4` alors que `0.19.0` est publiée — 1 release de retard, sous le seuil de 3 donc non signalé, mais c'est le seul des 4 charts non aligné et l'écart contient le refactor `failureAction`
- [ ] TEST: rien n'empêche le retour du piège `[ … ] && cmd` en fin de corps de boucle dans un pipeline capturé — shellcheck ne l'attrape pas, et il a coûté une issue ouverte pour une fausse dérive ; un grep de forme dans les checks CI serait peu coûteux

## ✅ Fait
