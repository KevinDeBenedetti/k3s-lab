# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] CHORE: une fois le chart publié et le pin relevé côté infra, retirer `ci` de `infra/platform/security/manifests/policy-exceptions.yaml` — l'exemption est désormais portée par le chart (`require-ro-rootfs` + `restrict-capabilities`) ; garder les deux mécanismes signifie que retirer l'un ne changera rien d'observable, et fera passer la vérification pour concluante
- [ ] CHORE: infra épingle `platform-security` à `0.18.4` alors que `0.19.0` est publiée — 1 release de retard, sous le seuil de 3 donc non signalé, mais c'est le seul des 4 charts non aligné et l'écart contient le refactor `failureAction`
- [ ] TEST: rien n'empêche le retour du piège `[ … ] && cmd` en fin de corps de boucle dans un pipeline capturé — shellcheck ne l'attrape pas, et il a coûté une issue ouverte pour une fausse dérive ; un grep de forme dans les checks CI serait peu coûteux

## 🟡 À faire (manuellement, étapes détaillées pas à pas)
- [ ] TEST: le job CI `k3s-lab-pin` n'a jamais tourné (ajouté depuis un sandbox sans accès Actions) — surveiller la première exécution : si l'image du runner n'a pas `git`, `actions/checkout` bascule sur le tarball et l'assertion échouera volontairement. NB 2026-08-17 : le runner est l'image officielle `ghcr.io/actions/actions-runner:2.335.1`, et l'étape `Assert the submodule is really checked out` fait échouer le job avec un message explicite plutôt que de passer vert à vide — le mode de défaillance est donc bruyant. Reste à confirmer sur un run réel.
- [ ] TEST: aucun check ne relie un CronJob à la version d'app qui expose l'endpoint qu'il appelle — le purge tapait une route absente de l'image depuis sa création, et rien n'a rien dit pendant des semaines. ⚠ 2026-08-17 : **hors de ce dépôt** — `grep -rl "kind: CronJob" charts/ kubernetes/` ne renvoie rien, il n'y a aucun CronJob ici. Le CronJob `portfolio/purge` et le Deployment dont il faudrait comparer la version vivent tous les deux dans le dépôt infra ; le check doit y être écrit.


## 🟢 Idées / backlog

## 🤖 Claude — recommandations
- [ ] CHORE: planifier le retrait du garde-fou `fail` sur `kyvernoPolicies.validationFailureAction` (p. ex. quand le pin infra aura dépassé cette version de 2 releases) — sinon le helper garde indéfiniment une branche morte pour une clé que plus personne ne pose
- [ ] CHORE: ajouter un `values.schema.json` avec `additionalProperties: false` sur `kyvernoPolicies` — le `fail` ajouté n'attrape que cet alias-là, alors que la classe entière du problème reste ouverte : un `faliureAction` mal tapé retombe toujours sur `Audit` en silence
- [ ] TEST: rien ne vérifie côté cluster que les 6 ClusterPolicy portent bien l'action attendue après une sync — et le retrait de l'alias est précisément indétectable là où la valeur posée valait déjà `Audit`


## ✅ Fait
- [x] 2026-08-20 — CHORE: retirer l'alias déprécié `kyvernoPolicies.validationFailureAction` du chart `platform-security` — la moitié amont (infra passe `failureAction: Audit`) a été faite dans le dépôt infra le 2026-08-19, ce qui débloquait la condition posée par `_helpers.tpl`. L'alias n'est pas simplement supprimé mais **rejeté** par un `fail` : Helm ignore une clé inconnue en silence, donc une install restée sur l'ancienne clé serait retombée sur le défaut sans erreur. Couvre les deux entrées jumelles de ce TODO (retrait de l'alias + migration du values infra).
