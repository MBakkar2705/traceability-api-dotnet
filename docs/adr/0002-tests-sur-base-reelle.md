# ADR 0002 : tests d'intégration sur une vraie base SQL Server

Statut : **Accepté** (2026-10-18)

## Contexte

Les règles métier sont dans des procédures stockées (voir ADR 0001). Pour prouver qu'elles fonctionnent, il faut les exécuter pour de vrai, avec les contraintes de la base.

## Décision

- Les tests d'intégration s'exécutent sur une vraie base SQL Server de test, séparée de la base de développement.
- Cette base est créée à partir des scripts du dépôt (`database/`) et remise à zéro avant les tests.

## Alternatives écartées

- **Simulations (mocks)** : elles ne prouvent rien sur le SQL lui-même.
- **Base en mémoire ou SQLite** : ce n'est pas le même moteur. SQLite n'a pas de procédures stockées, et la base en mémoire d'EF Core n'applique pas les contraintes relationnelles.
- **SQL Server dans Docker (Testcontainers)** : possible, mais plus lourd en local. À reconsidérer au moment de la CI.

## Conséquences

Positives :

- Les tests prouvent que les procédures et les contraintes fonctionnent réellement.
- Les mêmes scripts servent au développement et aux tests.

Négatives :

- Les tests sont plus lents que des tests sans base.
- Ils demandent un SQL Server disponible. Dans la CI (les tests lancés automatiquement par GitHub, sur une machine vide), il faudra trouver comment fournir un SQL Server : décision plus tard.

## Notes

- 2026-10-18 : aucune base de test n'existe encore. Tout est « Prévu » tant que les tests n'ont pas été exécutés et observés.
