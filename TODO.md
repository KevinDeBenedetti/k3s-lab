# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] FIX: rendre l'umbrella installable avec `platform-security` activé — ses `ClusterPolicy` Kyverno sont validées par helm avant que les CRDs Kyverno de la même release n'existent (constaté le 2026-08-03 sur cluster vierge). Pistes : hook `post-install` sur les policies, ou CRDs Kyverno dans `crds/` du wrapper, ou sous-release séparée.
- [ ] FIX: rafraîchir le `NOTES.txt` de `platform-deployment` — il référence `--version 1.0.0` (ligne abandonnée le 2026-07-21) et `0.9.2`, et donne des instructions producteur (`helm dependency update charts/…`) inapplicables à un consommateur — même défaut que celui corrigé dans le README le 2026-08-01, resté dans les NOTES.

## 🟢 Idées / backlog

## 🤖 Claude — recommandations

## ✅ Fait
