# TODO

## 🔴 En cours

## 🟡 À faire

## 🟡 À faire (manuellement, étapes détaillées pas à pas)
- [ ] TEST: le job CI `k3s-lab-pin` n'a jamais tourné (ajouté depuis un sandbox sans accès Actions) — surveiller la première exécution : si l'image du runner n'a pas `git`, `actions/checkout` bascule sur le tarball et l'assertion échouera volontairement. NB 2026-08-17 : le runner est l'image officielle `ghcr.io/actions/actions-runner:2.335.1`, et l'étape `Assert the submodule is really checked out` fait échouer le job avec un message explicite plutôt que de passer vert à vide — le mode de défaillance est donc bruyant. Reste à confirmer sur un run réel.
- [ ] TEST: aucun check ne relie un CronJob à la version d'app qui expose l'endpoint qu'il appelle — le purge tapait une route absente de l'image depuis sa création, et rien n'a rien dit pendant des semaines. ⚠ 2026-08-17 : **hors de ce dépôt** — `grep -rl "kind: CronJob" charts/ kubernetes/` ne renvoie rien, il n'y a aucun CronJob ici. Le CronJob `portfolio/purge` et le Deployment dont il faudrait comparer la version vivent tous les deux dans le dépôt infra ; le check doit y être écrit.


## 🟢 Idées / backlog

## 🤖 Claude — recommandations


## ✅ Fait
