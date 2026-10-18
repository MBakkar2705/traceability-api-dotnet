# traceability-api-dotnet

API ASP.NET Core et SQL Server de traçabilité (projet d'apprentissage).

Elle suit le parcours de lots de tomates, de la ferme à l'expédition : fermes, lots, stations et mouvements.

Ce projet est réalisé avec l'assistance de Claude (Anthropic), sous ma supervision.

## État

Tout est **Prévu** : à ce stade, seule la documentation existe. Rien n'est encore créé dans SQL Server ni développé. Une partie sera marquée « Prouvé » seulement après des tests exécutés et observés.

| Lot | Contenu | État |
|---|---|---|
| 0 | Documentation | En cours |
| 1 | Base de données (scripts SQL) | Prévu |
| 2 | Procédures stockées, données volumineuses, index | Prévu |
| 3 | API ASP.NET Core | Prévu |
| | Tests, intégration continue (GitHub Actions) | Prévu |
| 7 | Interface web (optionnelle) | Prévu |

## Technologies prévues

ASP.NET Core (.NET 10), SQL Server 2025, procédures stockées T-SQL, xUnit, Git et GitHub.

## Documentation

- [Documentation fonctionnelle](docs/fonctionnel.md) : ce qu'on trace et les règles métier.
- [Modèle de données](docs/modele-de-donnees.md) : tables, colonnes et contraintes.
- [Glossaire](docs/glossaire.md) : les termes techniques expliqués simplement.
- [ADR 0001](docs/adr/0001-procedures-stockees.md) : règles métier dans des procédures stockées.
- [ADR 0002](docs/adr/0002-tests-sur-base-reelle.md) : tests sur une vraie base SQL Server.

## Ce que ce projet ne prouve pas

- Il ne représente aucun système réel : le scénario est simplifié et inventé.
- Il ne gère pas les retours de marchandise, ni la découpe ou la fusion de lots.
- Il ne se connecte à aucun ERP ni outil BI, et n'a pas de gestion d'utilisateurs.
- Il donne une base de travail, pas une expérience de production.

## Démarrage

À venir, quand le projet existera.
