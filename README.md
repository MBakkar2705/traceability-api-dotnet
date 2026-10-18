# traceability-api-dotnet

API ASP.NET Core et SQL Server de traçabilité (projet d'apprentissage).

Elle suit le parcours de lots de tomates, de la ferme à l'expédition : fermes, lots, stations et mouvements.

Ce projet est réalisé avec l'assistance de Claude (Anthropic), sous ma supervision.

## État

Le lot 1 (base de données) est **terminé** : la base `TraceabilityDev`, ses 5 tables et leurs contraintes sont créées par les scripts du dossier `database/`, et vérifiées par des tests exécutés et observés (voir [docs/verification.md](docs/verification.md)). Le reste est **Prévu** : aucune procédure stockée ni API n'existe encore. « Prouvé » n'est écrit que pour ce qui a été exécuté et observé.

| Lot | Contenu | État |
|---|---|---|
| 0 | Documentation | En cours |
| 1 | Base de données (scripts SQL) | Terminé |
| 2 | Procédures stockées, données volumineuses, index | Prévu |
| 3 | API ASP.NET Core | Prévu |
| | Tests, intégration continue (GitHub Actions) | Prévu |
| 7 | Interface web (optionnelle) | Prévu |

## Technologies prévues

ASP.NET Core (.NET 10), SQL Server 2025, procédures stockées T-SQL, xUnit, Git et GitHub.

## Documentation

- [Documentation fonctionnelle](docs/fonctionnel.md) : ce qu'on trace et les règles métier.
- [Modèle de données](docs/modele-de-donnees.md) : tables, colonnes et contraintes.
- [Vérification du lot 1](docs/verification.md) : ce qui a été exécuté et observé, et ce qui ne l'est pas encore.
- [Glossaire](docs/glossaire.md) : les termes techniques expliqués simplement.
- [ADR 0001](docs/adr/0001-procedures-stockees.md) : règles métier dans des procédures stockées.
- [ADR 0002](docs/adr/0002-tests-sur-base-reelle.md) : tests sur une vraie base SQL Server.

## Ce que ce projet ne prouve pas

- Il ne représente aucun système réel : le scénario est simplifié et inventé.
- Il ne gère pas les retours de marchandise, ni la découpe ou la fusion de lots.
- Il ne se connecte à aucun ERP ni outil BI, et n'a pas de gestion d'utilisateurs.
- Au lot 1, tout n'est pas prouvé : la liste est dans [docs/verification.md](docs/verification.md), section 4.
- Il donne une base de travail, pas une expérience de production.

## Démarrage

### Base de données (lot 1)

Prérequis : SQL Server 2025 et SQL Server Management Studio (SSMS).

1. Se connecter à l'instance locale (`localhost`) avec l'authentification Windows. Dans cette configuration locale, « Certificat de serveur de confiance » est coché : acceptable seulement en local, jamais pour un serveur distant.
2. Exécuter dans l'ordre les scripts du dossier `database/` :
   - `001_create_database.sql` : crée la base `TraceabilityDev` (rejouable).
   - `002_create_schema_and_tables.sql` : crée le schéma `trace` et les 5 tables (non rejouable : il échoue si elles existent déjà).
   - `003_check_schema.sql` : inspecte la structure et lance des tests de refus, annulés à la fin (rejouable).
3. Pour repartir de zéro : `900_reset_dev_database.sql` supprime la base de développement. Il est verrouillé : il ne fait rien tant que `@confirm` n'est pas changé en `YES` (ne pas enregistrer ce changement). Puis rejouer `001`, `002` et `003`.

### API

À venir, quand le projet .NET existera.
