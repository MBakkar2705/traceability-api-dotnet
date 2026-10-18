# ADR 0001 : règles métier dans des procédures stockées

Statut : **Accepté** (2026-10-18)

## Contexte

Le projet est un projet d'apprentissage ASP.NET Core + SQL Server. Les règles métier (ordre des statuts, quantité qui ne monte pas) doivent tenir quelle que soit l'application qui écrit dans la base. Un objectif du projet est d'apprendre à écrire, tester et optimiser des procédures stockées T-SQL.

## Décision

- Les règles métier sont écrites dans des procédures stockées T-SQL, appelées par l'API.
- Les règles simples restent des contraintes (`FOREIGN KEY`, `CHECK`, `UNIQUE`).
- L'API ne contient pas ces règles : elle appelle les procédures et traduit les erreurs.
- L'accès se fait par ADO.NET (`Microsoft.Data.SqlClient`) ou Dapper. Ce choix est reporté au lot 3.

## Alternatives écartées

**Règles en C# avec Entity Framework Core.** Les règles seraient dans l'application. Plus simple à déboguer et à versionner, mais elles ne protègent que ce qui passe par cette application, et on apprendrait moins de SQL.

## Conséquences

Positives :

- Les règles sont au plus près des données et s'appliquent à tous les accès.
- Un mouvement et la mise à jour du lot peuvent être faits dans une seule transaction.
- Les procédures se testent directement en SQL.

Négatives :

- La logique est en T-SQL, plus difficile à déboguer que du C#.
- Il faut des scripts SQL numérotés et versionnés (dossier `database/`).
- Il faut des tests sur une vraie base (voir ADR 0002).

## Notes

- 2026-10-18 : choix ADO.NET ou Dapper encore ouvert (lot 3).
