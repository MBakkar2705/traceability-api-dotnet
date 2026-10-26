# ADR 0010 : protection de `main` par un ruleset GitHub : pull request obligatoire, vérifications `backend` et `frontend` exigées

Statut : **Accepté** (2026-10-26)

## Contexte

Le lot 6 a mis en place la CI ([ADR 0009](0009-integration-continue-github-actions.md)). Une CI qui n'empêche rien reste une information : le 2026-10-26, avant ce réglage, la page d'accueil du dépôt affichait « Your main branch isn't protected » et la page Settings, Branches ne listait aucune règle. Rien n'empêchait donc de pousser directement sur `main`, de la supprimer, de réécrire son historique avec une poussée forcée, ni de fusionner une pull request dont la CI est rouge. Seules la discipline et le `CLAUDE.md` (« un lot = une branche = une PR ») s'y opposaient. Mohamed voulait se rapprocher d'une pratique d'entreprise, où la branche principale est protégée.

## Décision

Un ruleset GitHub nommé `protect-main`, **actif**, qui vise la branche par défaut (la page affiche « Applies to 1 target: `main` »), avec :

- **Suppression interdite** (« Restrict deletions ») et **poussées forcées interdites** (« Block force pushes ») ;
- **Pull request obligatoire avant fusion**, avec **0 approbation requise** ; les autres réglages de cette règle restent décochés, et les trois modes de fusion (Merge, Squash, Rebase) restent autorisés ;
- **Vérifications exigées** : `backend` et `frontend` (source : GitHub Actions). L'option « Require branches to be up to date before merging » n'est pas cochée ;
- **Bypass list vide** : aucun rôle, équipe ni utilisateur n'est exempté de la règle.

C'est un réglage du dépôt sur GitHub : il n'est pas dans les fichiers du dépôt. Le constat est dans [verification.md](../verification.md), section 14.10.

## Alternatives écartées

- **Ne pas protéger `main`** (la situation d'avant). Seule la discipline empêcherait de fusionner une CI rouge.
- **Une règle « classique » de protection de branche** au lieu d'un ruleset. La page de réglages de GitHub indique que les rulesets sont la méthode recommandée et que les règles classiques offrent moins de possibilités. Non essayée.
- **Exiger une ou plusieurs approbations de relecture.** Écarté : le projet est mené seul, et selon GitHub l'auteur d'une pull request ne peut pas approuver la sienne. La relecture reste celle que décrit le `CLAUDE.md` : Mohamed relit, commite et fusionne.
- **Exiger « branche à jour avant fusion ».** Écarté : la CI d'une pull request teste déjà la fusion avec `main` ([verification.md](../verification.md) 14.6) ; l'option ajouterait surtout des relances.
- **Exiger un historique linéaire ou limiter les modes de fusion.** Écarté : les onze pull requests précédentes ont été fusionnées avec un commit de fusion, et les hashes cités dans la documentation restent ainsi dans l'historique de `main`.
- **Exempter le propriétaire du dépôt** (bypass). Écarté : il pourrait alors contourner sa propre règle.

## Conséquences

Positives :

- Plus de poussée directe sur `main`, plus de suppression ni de poussée forcée : tout passe par une pull request.
- La règle exige que `backend` et `frontend` réussissent avant la fusion. Sur la pull request n° 12, les quatre vérifications (`backend` et `frontend`, pour les déclenchements `push` et `pull_request`) portent l'étiquette « Required » ([verification.md](../verification.md) 14.10).

Négatives :

- Le réglage n'est ni versionné ni rejouable depuis le code : il se vérifie seulement dans les réglages de GitHub.
- Les noms exigés sont ceux des tâches de `ci.yml`. Si on renomme une tâche sans changer la règle, la vérification exigée ne sera plus jamais rapportée et les fusions devraient être bloquées. Non essayé.
- La bypass list est vide : si la CI tombe en panne (par exemple un secret manquant), la fusion est bloquée tant que la règle n'est pas modifiée ou désactivée dans les réglages.
- Un changement, même d'une ligne de documentation, passe par une branche et une pull request.
- Une pull request venant d'un fork n'aurait pas le secret de la CI ([ADR 0009](0009-integration-continue-github-actions.md)) : sa tâche `backend` échouerait et la règle bloquerait sa fusion. Non essayé.
- Que la règle empêche réellement de fusionner une CI rouge n'est pas encore observé : l'essai est décrit dans [verification.md](../verification.md), section 14.11.

## Notes

- 2026-10-26 : règle créée entre 20:00 et 20:02 (heure locale = UTC). Constat sur la pull request n° 12 vers 20:04 : les quatre vérifications sont « Required » et réussies (`backend` 54 s et 1 min, `frontend` 30 s et 22 s).
