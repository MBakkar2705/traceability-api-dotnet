# traceability-api-dotnet

API ASP.NET Core et SQL Server de traçabilité (projet d'apprentissage).

Elle suit le parcours de lots de tomates, de la ferme à l'expédition : fermes, lots, stations et mouvements.

Ce projet est réalisé avec l'assistance de Claude (Anthropic), sous ma supervision.

## État

Les lots 1, 2a, 2b, 3a et 3b sont **terminés**. Lot 1 : la base de données (5 tables et leurs contraintes). Lot 2a : les 7 procédures stockées du schéma `trace` et leurs 38 tests, exécutés sur une base de test `TraceabilityTest`, avec un essai à la main du verrou posé par `AddMovement` (voir [docs/verification.md](docs/verification.md)). Lot 2b : un million de lots inventés et 3 250 000 mouvements générés dans `TraceabilityDev` et contrôlés, des mesures de recherche avant et après index (un index retenu, deux essais abandonnés ; voir [docs/mesures.md](docs/mesures.md)). Lot 3a : trois procédures de lecture (`ListFarms`, `ListStations`, `GetStation`) et leurs 16 tests, et un total ajouté à `ListBatches` (tests 32, 33 et 38 de `006` revus), exécutés sur `TraceabilityTest` (voir [docs/verification.md](docs/verification.md)) ; le coût du total a été mesuré (voir [docs/mesures.md](docs/mesures.md), section 4.3). Lot 3b : l'API ASP.NET Core pour les fermes et les stations (6 routes), avec un accès aux données en ADO.NET, 49 tests unitaires et 30 tests d'intégration exécutés et observés (voir [docs/verification.md](docs/verification.md), section 9). Le lot 3 a été coupé deux fois : l'étude de l'API .NET a montré que le SQL manquait de ces trois procédures et d'un total pour les lots, ce qui forme le lot 3a ; puis l'API a été coupée par ressource, les fermes et les stations au lot 3b, les lots au lot 3c. Le reste est **Prévu** : les routes des lots. « Prouvé » n'est écrit que pour ce qui a été exécuté et observé.

| Lot | Contenu | État |
|---|---|---|
| 0 | Documentation | En cours |
| 1 | Base de données (scripts SQL) | Terminé |
| 2a | Procédures stockées et leurs tests | Terminé |
| 2b | Données volumineuses, index, mesures | Terminé |
| 3a | Évolutions SQL pour l'API (lister les fermes et les stations, lire une station, total des lots) | Terminé |
| 3b | API ASP.NET Core : fermes et stations (6 routes) | Terminé |
| 3c | API ASP.NET Core : lots (4 routes) | Prévu |
| | Optimisation des totaux des listes (index, mesures) | Prévu |
| | Tests, intégration continue (GitHub Actions) | Prévu |
| 7 | Interface web (optionnelle) | Prévu |

## Technologies

ASP.NET Core (.NET 10), ADO.NET (`Microsoft.Data.SqlClient`), Swagger UI, SQL Server 2025, procédures stockées T-SQL, xUnit, Git et GitHub. L'intégration continue (GitHub Actions) est **Prévue**.

## Documentation

- [Documentation fonctionnelle](docs/fonctionnel.md) : ce qu'on trace et les règles métier.
- [Modèle de données](docs/modele-de-donnees.md) : tables, colonnes et contraintes.
- [Contrat des procédures](docs/procedures.md) : paramètres, contrôles et erreurs des 10 procédures.
- [Vérification des lots 1, 2a, 2b, 3a et 3b](docs/verification.md) : ce qui a été exécuté et observé, et ce qui ne l'est pas encore.
- [Mesures des lots 2b et 3a](docs/mesures.md) : hypothèses écrites avant de mesurer, mesures avant et après chaque index, décisions.
- [Glossaire](docs/glossaire.md) : les termes techniques expliqués simplement.
- [ADR 0001](docs/adr/0001-procedures-stockees.md) : règles métier dans des procédures stockées.
- [ADR 0002](docs/adr/0002-tests-sur-base-reelle.md) : tests sur une vraie base SQL Server.
- [ADR 0003](docs/adr/0003-verrou-sur-le-lot.md) : verrou sur le lot pour deux mouvements simultanés.
- [ADR 0004](docs/adr/0004-index-simple-sur-mouvement-par-lot.md) : index simple sur les mouvements par lot.
- [ADR 0005](docs/adr/0005-ado-net-sans-dapper.md) : accès aux données en ADO.NET, sans Dapper.

## Ce que ce projet ne prouve pas

- Il ne représente aucun système réel : le scénario est simplifié et inventé.
- Il ne gère pas les retours de marchandise, ni la découpe ou la fusion de lots.
- Il ne se connecte à aucun ERP ni outil BI, et n'a pas de gestion d'utilisateurs.
- Aux lots 1, 2a, 2b, 3a et 3b, tout n'est pas prouvé : les listes sont dans [docs/verification.md](docs/verification.md), sections 4, 6.4, 7.3, 8.3 et 9.3.
- Le CORS n'est pas configuré et aucun frontend n'a été essayé. Swagger UI ne documente pas encore les erreurs possibles des routes (prévu au lot 3c).
- Les mesures du lot 2b portent sur un million de lots inventés et une seule machine : elles ne disent rien d'un autre volume, d'une autre machine, ni du coût des index en écriture (voir [docs/mesures.md](docs/mesures.md), section 5).
- Il donne une base de travail, pas une expérience de production.

## Démarrage

### Base de données (lots 1, 2a, 2b et 3a)

Prérequis : SQL Server 2025 et SQL Server Management Studio (SSMS).

1. Se connecter à l'instance locale (`localhost`) avec l'authentification Windows. Dans cette configuration locale, « Certificat de serveur de confiance » est coché : acceptable seulement en local, jamais pour un serveur distant.
2. Activer le **mode SQLCMD** dans chaque fenêtre de requête : menu Requête > Mode SQLCMD. C'est une bascule propre à chaque fenêtre : si le mode est déjà actif, ne pas cliquer (cela le désactiverait). Sans ce mode, le nom de la base n'est pas remplacé : le script affiche des erreurs ou est arrêté par sa garde, sans rien créer.
3. Choisir la base : en haut de chaque script, la ligne `:setvar DbName ...` donne le nom (`TraceabilityDev` par défaut). Pour la base de test, remplacer par `TraceabilityTest` sans enregistrer le changement. Le script de remise à zéro (`900`) n'accepte que ces deux noms.
4. Exécuter dans l'ordre les scripts du dossier `database/` :
   - `001_create_database.sql` : crée la base (rejouable).
   - `002_create_schema_and_tables.sql` : crée le schéma `trace` et les 5 tables (non rejouable : il échoue si elles existent déjà).
   - `003_check_schema.sql` : inspecte la structure et lance des tests de refus, annulés à la fin (rejouable sur une base vide).
   - `004_create_reference_procedures.sql` : crée `CreateFarm`, `CreateStation` et `AddStationCapability` (écrit avec `CREATE OR ALTER`, donc conçu pour être rejoué).
   - `005_create_batch_procedures.sql` : crée `CreateBatch`, `AddMovement`, `GetBatch` et `ListBatches` (même principe ; `ListBatches` renvoie aussi le total depuis le lot 3a).
   - `006_check_procedures.sql` : 38 tests des procédures (34 automatiques et 4 dont le contenu se vérifie à l'œil), uniquement sur `TraceabilityTest` (le mode SQLCMD n'est pas nécessaire). Rejouable, mais il laisse ses lignes dans la base : ne pas relancer `003` ensuite sans reconstruire.
   - `007_generate_volume_data.sql` : génère les lots et leurs mouvements inventés dans `TraceabilityDev` (réglage `@TargetLots` en haut du script : 10 000 pour un échantillon, 1 000 000 pour le jeu complet, sans enregistrer le changement). Reprenable. Le mode SQLCMD n'est pas nécessaire.
   - `008_check_volume_data.sql` : 28 contrôles des données générées, en lecture seule (sans SQLCMD).
   - `009_measure_searches.sql` : mesure les recherches de l'API, en lecture seule (sans SQLCMD). Il exige le million de lots et les procédures de `004` et `005` ; activer le plan d'exécution réel (Ctrl+M).
   - `010_create_indexes.sql` : crée l'index retenu, `IX_Movement_BatchId`. Rejouable (sans SQLCMD).
   - `011_create_list_procedures.sql` : crée `ListFarms`, `ListStations` et `GetStation` (lot 3a). Même principe que `004` et `005` (`CREATE OR ALTER`, mode SQLCMD) : à lancer sur `TraceabilityDev` et sur `TraceabilityTest`.
   - `012_check_list_procedures.sql` : 16 tests des trois procédures, uniquement sur `TraceabilityTest` (sans SQLCMD) : 10 automatiques et 6 dont le contenu se vérifie à l'œil (voir [docs/verification.md](docs/verification.md), section 8). Il supprime d'abord les lignes `ZY-…` d'un passage précédent.
5. Pour repartir de zéro : `900_reset_dev_database.sql` supprime la base indiquée par `:setvar DbName`. Il est verrouillé : il ne fait rien tant que `@confirm` n'est pas changé en `YES` (ne pas enregistrer ce changement). Puis rejouer `001` à `005` et `011` (et `006` et `012` pour la base de test).

Si SSMS souligne en rouge des procédures « introuvables » alors qu'elles existent, actualiser le cache de l'IntelliSense (Ctrl+Maj+R) : c'est arrivé aux lots 2a et 3a, et le compteur d'erreurs est retombé à 0.

L'essai du verrou de l'ADR 0003 se fait à la main, avec deux fenêtres SSMS : le déroulé et le résultat sont dans [docs/verification.md](docs/verification.md), section 6.3.

### API (lot 3b)

Prérequis : le SDK .NET 10 (10.0.402 observé), les deux bases du lot précédent (`TraceabilityDev` avec ses données, `TraceabilityTest` avec les procédures `004`, `005` et `011`), l'authentification Windows. Toutes les commandes sont à lancer dans PowerShell, depuis la racine du dépôt.

1. Certificat HTTPS de développement, une seule fois : `dotnet dev-certs https --trust`. Windows affiche une fenêtre de confirmation : elle concerne le certificat de développement créé par .NET pour `localhost`.
2. Variables d'environnement, une seule fois, au niveau du compte Windows (aucun mot de passe : authentification Windows) :

   ```powershell
   [Environment]::SetEnvironmentVariable("ConnectionStrings__Default", "Server=localhost;Database=TraceabilityDev;Integrated Security=True;TrustServerCertificate=True", "User")
   [Environment]::SetEnvironmentVariable("ConnectionStrings__Test", "Server=localhost;Database=TraceabilityTest;Integrated Security=True;TrustServerCertificate=True", "User")
   ```

   `TrustServerCertificate=True` est nécessaire en local : sans lui, la connexion depuis .NET a échoué avec une erreur de chaîne de certificats (« autorité qui n'est pas approuvée », observé le 2026-10-20). Comme dans SSMS, il est acceptable seulement en local, jamais pour un serveur distant. Un programme déjà ouvert ne voit pas une variable créée après son démarrage : rouvrir VS Code ou ouvrir une nouvelle fenêtre PowerShell.
3. Lancer l'API : `dotnet run --project src/Traceability.Api --launch-profile https`. Elle écoute sur `https://localhost:7080` et lit `ConnectionStrings__Default`. Ouvrir ensuite `https://localhost:7080/swagger` à la main : `dotnet run` n'ouvre pas le navigateur (c'est documenté, pas une panne). Arrêt : Ctrl+C.
4. Les tests : `dotnet test Traceability.slnx`, ou séparément `tests/Traceability.UnitTests` (sans base) et `tests/Traceability.IntegrationTests`. **Attention :** les tests d'intégration vident les 5 tables de `TraceabilityTest` au début de chaque exécution (`DELETE` sans `WHERE`, précédés d'un contrôle du nom de la base) ; ils lisent `ConnectionStrings__Test` et ne touchent jamais `TraceabilityDev`.

Les 6 routes du lot 3b :

| Route | Procédure |
|---|---|
| `POST /farms` | `CreateFarm` |
| `GET /farms?pageNumber=1&pageSize=20` | `ListFarms` |
| `POST /stations` | `CreateStation` |
| `GET /stations?pageNumber=1&pageSize=20` | `ListStations` |
| `GET /stations/{stationCode}` | `GetStation` |
| `POST /stations/{stationCode}/capabilities` | `AddStationCapability` |

Les listes répondent `items`, `totalCount`, `pageNumber` et `pageSize` ; sans paramètre, la page est la 1 de 20. Les erreurs sont au format Problem Details, avec un champ `errorCode` qui reprend le numéro de la procédure (501xx → 404, 502xx → 409, 503xx → 422, 504xx → 400). Les 4 routes des lots viendront au lot 3c.
