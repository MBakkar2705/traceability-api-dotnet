# traceability-api-dotnet

API ASP.NET Core et SQL Server de traçabilité (projet d'apprentissage).

Elle suit le parcours de lots de tomates, de la ferme à l'expédition : fermes, lots, stations et mouvements.

Ce projet est réalisé avec l'assistance de Claude (Anthropic), sous ma supervision.

## État

Les lots 1, 2a, 2b, 3a, 3b, 3c, 4a, 4b et 5 sont **terminés**. Lot 1 : la base de données (5 tables et leurs contraintes). Lot 2a : les 7 procédures stockées du schéma `trace` et leurs 38 tests, exécutés sur une base de test `TraceabilityTest`, avec un essai à la main du verrou posé par `AddMovement` (voir [docs/verification.md](docs/verification.md)). Lot 2b : un million de lots inventés et 3 250 000 mouvements générés dans `TraceabilityDev` et contrôlés, des mesures de recherche avant et après index (un index retenu, deux essais abandonnés ; voir [docs/mesures.md](docs/mesures.md)). Lot 3a : trois procédures de lecture (`ListFarms`, `ListStations`, `GetStation`) et leurs 16 tests, et un total ajouté à `ListBatches` (tests 32, 33 et 38 de `006` revus), exécutés sur `TraceabilityTest` (voir [docs/verification.md](docs/verification.md)) ; le coût du total a été mesuré (voir [docs/mesures.md](docs/mesures.md), section 4.3). Lot 3b : l'API ASP.NET Core pour les fermes et les stations (6 routes), avec un accès aux données en ADO.NET, 49 tests unitaires et 30 tests d'intégration exécutés et observés (voir [docs/verification.md](docs/verification.md), section 9). Lot 3c : l'API pour les lots (4 routes), la documentation Swagger des 10 routes, le refus par l'API des valeurs que les colonnes ne peuvent pas stocker (texte trop long, quantité trop précise ou trop grande : sans cela, elles étaient coupées, arrondies ou faisaient échouer SqlClient, observé), 74 tests unitaires et 80 tests d'intégration exécutés et observés, et une casse volontaire de 5 défauts (voir [docs/verification.md](docs/verification.md), section 10). Le lot 3 a été coupé deux fois : l'étude de l'API .NET a montré que le SQL manquait de ces trois procédures et d'un total pour les lots, ce qui forme le lot 3a ; puis l'API a été coupée par ressource, les fermes et les stations au lot 3b, les lots au lot 3c. Lot 4a : l'interface web de lecture (React, Vite, TypeScript, Tailwind CSS) avec 5 écrans (fermes, stations, détail d'une station, lots avec filtres, détail d'un lot), le CORS de l'API pour le serveur de développement de l'interface, 79 tests d'interface et 159 tests C# (dont 5 de CORS) exécutés et observés, un essai dans Edge sur les vraies données de `TraceabilityDev`, et une casse volontaire de 8 défauts (voir [docs/verification.md](docs/verification.md), section 11). Le lot 4 a été coupé en deux : lecture (4a) et écriture (4b). Lot 4b : l'interface web d'écriture (trois pages de création : fermes, stations, lots ; ajout d'une fonction à une station et d'un mouvement à un lot), les erreurs de l'API affichées en français, par champ pour les erreurs de forme, le CORS de l'API étendu à `POST`, 178 tests d'interface et 163 tests C# exécutés et observés, un essai dans Edge sur `TraceabilityTest`, un défaut trouvé à cet essai puis corrigé, et une casse volontaire de 6 défauts (voir [docs/verification.md](docs/verification.md), section 12). Lot 5 : l'optimisation de la liste des lots (script `017`, [ADR 0008](docs/adr/0008-listbatches-page-avant-jointure-total-recompile.md)) : la page est découpée avant la jointure (la dernière page passe de 7,9 à 146 s à 277 à 298 ms dans SSMS, sans tri, et répond en 0,45 à 1,59 s par l'API sur 10 appels) et le total est refait à chaque appel avec l'index `IX_Batch_FarmId` (de 10 574 à 1 737 lectures sans filtre, 47 pour une ferme de 25 000 lots), avec 163 tests C# et les 38 tests de `006` exécutés et observés, et des hypothèses écrites avant leur mesure, dont plusieurs contredites (voir [docs/mesures.md](docs/mesures.md), sections 6 à 9.6, et [docs/verification.md](docs/verification.md), section 13). Un point n'est pas prouvé : les échecs du bouton « Fin » du début de séance (3 sur 3 par l'API, après 30 s) n'ont pas pu être reproduits ; la correction n'est pas démontrée, et une attente de mémoire de SQL Server en est la piste (voir [docs/verification.md](docs/verification.md), section 13.3). Le reste est **Prévu** : l'intégration continue (lot 6). Dans ce README, « Prévu » veut dire « on a l'intention de le faire », pas « on sait que ça marchera » : pour le lot 6, on ne sait pas encore si GitHub peut faire tourner nos tests d'intégration (ils utilisent l'authentification Windows et une base locale). « Prouvé » n'est écrit que pour ce qui a été exécuté et observé.

| Lot | Contenu | État |
|---|---|---|
| 0 | Documentation | En cours |
| 1 | Base de données (scripts SQL) | Terminé |
| 2a | Procédures stockées et leurs tests | Terminé |
| 2b | Données volumineuses, index, mesures | Terminé |
| 3a | Évolutions SQL pour l'API (lister les fermes et les stations, lire une station, total des lots) | Terminé |
| 3b | API ASP.NET Core : fermes et stations (6 routes) | Terminé |
| 3c | API ASP.NET Core : lots (4 routes) | Terminé |
| 4a | Interface web (React) : lecture, 5 écrans, et CORS de l'API | Terminé |
| 4b | Interface web : écriture (formulaires, erreurs par champ) | Terminé |
| 5 | Optimisation de la liste des lots (total, dernière page, index, mesures) | Terminé |
| 6 | Intégration continue (GitHub Actions) ; faisabilité à étudier au début du lot | Prévu |

## Technologies

ASP.NET Core (.NET 10), ADO.NET (`Microsoft.Data.SqlClient`), Swagger UI, SQL Server 2025, procédures stockées T-SQL, xUnit, Git et GitHub. Interface web : React, TypeScript, Vite, Tailwind CSS, React Router, Vitest et React Testing Library, Oxlint (voir l'[ADR 0006](docs/adr/0006-interface-web-vite-react.md)). L'intégration continue (GitHub Actions) est **Prévue** (lot 6).

## Documentation

- [Documentation fonctionnelle](docs/fonctionnel.md) : ce qu'on trace et les règles métier.
- [Modèle de données](docs/modele-de-donnees.md) : tables, colonnes et contraintes.
- [Contrat des procédures](docs/procedures.md) : paramètres, contrôles et erreurs des 10 procédures.
- [Vérification des lots 1, 2a, 2b, 3a, 3b, 3c, 4a et 4b](docs/verification.md) : ce qui a été exécuté et observé, et ce qui ne l'est pas encore.
- [Mesures des lots 2b, 3a et 5](docs/mesures.md) : hypothèses écrites avant de mesurer, mesures avant et après chaque index, décisions.
- [Glossaire](docs/glossaire.md) : les termes techniques expliqués simplement.
- [ADR 0001](docs/adr/0001-procedures-stockees.md) : règles métier dans des procédures stockées.
- [ADR 0002](docs/adr/0002-tests-sur-base-reelle.md) : tests sur une vraie base SQL Server.
- [ADR 0003](docs/adr/0003-verrou-sur-le-lot.md) : verrou sur le lot pour deux mouvements simultanés.
- [ADR 0004](docs/adr/0004-index-simple-sur-mouvement-par-lot.md) : index simple sur les mouvements par lot.
- [ADR 0005](docs/adr/0005-ado-net-sans-dapper.md) : accès aux données en ADO.NET, sans Dapper.
- [ADR 0006](docs/adr/0006-interface-web-vite-react.md) : interface web en Vite, React et TypeScript.
- [ADR 0007](docs/adr/0007-cors-dans-l-api.md) : CORS dans l'API, plutôt qu'un proxy de développement.
- [ADR 0008](docs/adr/0008-listbatches-page-avant-jointure-total-recompile.md) : `ListBatches` : page découpée avant la jointure, total refait à chaque appel, index sur la ferme.

## Ce que ce projet ne prouve pas

- Il ne représente aucun système réel : le scénario est simplifié et inventé.
- Aux lots 1, 2a, 2b, 3a, 3b, 3c, 4a, 4b et 5, tout n'est pas prouvé : les listes sont dans [docs/verification.md](docs/verification.md), sections 4, 6.4, 7.3, 8.3, 9.3, 10.3, 11.3, 12.3 et 13.3.
- Le CORS n'est configuré que pour le serveur de développement de l'interface (`http://localhost:5173`, `GET` seulement), et l'interface n'écrit encore rien. L'interface n'a été vue que dans Edge. Le bouton « Fin » de la liste des lots a été accéléré au lot 5, mais la correction de ses échecs n'est pas prouvée (voir ci-dessus). Swagger UI décrit les 10 routes et leurs erreurs, mais son exemple d'erreur n'affiche pas les champs ajoutés par l'API (`errorCode`, `errors`).
- Les mesures des lots 2b et 5 portent sur un million de lots inventés et une seule machine : elles ne disent rien d'un autre volume ni d'une autre machine ; le coût en écriture n'est mesuré que pour `IX_Batch_FarmId` (voir [docs/mesures.md](docs/mesures.md), sections 5 et 9.4).
- Il donne une base de travail, pas une expérience de production.

## Hors périmètre et suite

### Hors périmètre

Ce sont des choses qui se font en entreprise, mais elles sont hors périmètre de ce projet d'apprentissage :

- l'interfaçage avec un ERP, un DataWarehouse et des outils BI ;
- la livraison et le déploiement continus (le « CD » de CI/CD) et la mise en production ;
- le support applicatif de niveau 2 ;
- la découpe ou la fusion de lots.

### À faire ou à prendre en compte

Ces points ne sont pas planifiés dans un lot : ce sont des intentions, pas des promesses.

- la gestion des utilisateurs et des droits (authentification) ;
- la correction des mouvements : aujourd'hui, une faute de saisie ne peut pas être corrigée (voir [docs/fonctionnel.md](docs/fonctionnel.md), section 9) ;
- les retours de marchandise ;
- l'archivage ou la purge des anciennes données ;
- des données et des écrans de contrôle qualité : le modèle n'a aucune donnée de ce genre, et le métier est à connaître avant de les concevoir ;
- essayer React Router 8.5.0 : elle demande Node 22.22.0 ou plus, ce que la version installée (22.23.4) permet ; non essayée (voir l'[ADR 0006](docs/adr/0006-interface-web-vite-react.md)) ;
- des tests d'interface qui pilotent un vrai navigateur, et un essai sur un vrai téléphone ;
- le journal de l'API écrit comme une erreur grave un appel que le navigateur a annulé (observé au lot 4a) ;
- un index sur le statut des lots : le total et la page de `RECEIVED` lisent encore 10 574 et 9 351 pages (voir [docs/mesures.md](docs/mesures.md), sections 9.5 et 9.6) ;
- une pagination par clé (reprendre après le dernier numéro de lot vu) plutôt que par numéro de page : la dernière page lit toujours toute la table (10 424 pages) ; cela changerait le contrat de l'API et de l'interface ;
- reproduire à volonté les échecs du bouton « Fin » (par exemple en limitant la mémoire de SQL Server) pour prouver la correction, et essayer « Fin » dans l'interface web, pas seulement par l'API ;
- un cahier de scénarios fonctionnels (une recette) : créer une ferme, créer un lot, le faire avancer jusqu'à l'expédition, avec un maximum de scénarios, y compris les refus. Il pourra être rejoué à la main, puis automatisé en partie une fois l'interface web faite.

## Démarrage

### Base de données (lots 1, 2a, 2b, 3a et 5)

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
   - `013_measure_lot5.sql` : mesure le total et la dernière page de `ListBatches` (lot 5), en lecture seule (sans SQLCMD) ; activer le plan d'exécution réel (Ctrl+M) pour les blocs A, le désactiver pour les blocs B.
   - `014_measure_lot5_trials.sql` : essais G1 et G2 du lot 5, en lecture seule (son seul `INSERT` écrit dans des variables de type table qui disparaissent à la fin du lot). Sans SQLCMD.
   - `015_measure_lot5_t2.sql` : mesures de l'essai d'index pour le total, en lecture seule (sans SQLCMD).
   - `016_measure_lot5_costs.sql` : coûts de l'index et du plan refait à chaque appel. **Son bloc W1 écrit dans la base** (appels de `CreateBatch`, chaque série annulée) ; les autres blocs sont en lecture seule. Sans SQLCMD.
   - `017_optimize_list_batches.sql` : crée `IX_Batch_FarmId` s'il n'existe pas et remplace `ListBatches` (lot 5, [ADR 0008](docs/adr/0008-listbatches-page-avant-jointure-total-recompile.md)). Même principe que `011` (`CREATE OR ALTER`, mode SQLCMD) : à lancer sur `TraceabilityDev` et sur `TraceabilityTest`, API arrêtée.
5. Pour repartir de zéro : `900_reset_dev_database.sql` supprime la base indiquée par `:setvar DbName`. Il est verrouillé : il ne fait rien tant que `@confirm` n'est pas changé en `YES` (ne pas enregistrer ce changement). Puis rejouer `001` à `005`, `011` et `017` (et `006` et `012` pour la base de test).

Si SSMS souligne en rouge des procédures « introuvables » alors qu'elles existent, actualiser le cache de l'IntelliSense (Ctrl+Maj+R) : c'est arrivé aux lots 2a et 3a, et le compteur d'erreurs est retombé à 0.

L'essai du verrou de l'ADR 0003 se fait à la main, avec deux fenêtres SSMS : le déroulé et le résultat sont dans [docs/verification.md](docs/verification.md), section 6.3.

### API (lots 3b et 3c)

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

Les 10 routes (6 au lot 3b, 4 au lot 3c) :

| Route | Procédure |
|---|---|
| `POST /farms` | `CreateFarm` |
| `GET /farms?pageNumber=1&pageSize=20` | `ListFarms` |
| `POST /stations` | `CreateStation` |
| `GET /stations?pageNumber=1&pageSize=20` | `ListStations` |
| `GET /stations/{stationCode}` | `GetStation` |
| `POST /stations/{stationCode}/capabilities` | `AddStationCapability` |
| `POST /batches` | `CreateBatch` |
| `GET /batches?status=...&farmCode=...&pageNumber=1&pageSize=20` | `ListBatches` |
| `GET /batches/{batchCode}` | `GetBatch` |
| `POST /batches/{batchCode}/movements` | `AddMovement` |

Les listes répondent `items`, `totalCount`, `pageNumber` et `pageSize` ; sans paramètre, la page est la 1 de 20. Les erreurs sont au format Problem Details, avec un champ `errorCode` qui reprend le numéro de la procédure (501xx → 404, 502xx → 409, 503xx → 422, 504xx → 400). Les routes `POST` répondent 201 sans corps, avec un en-tête `Location` vers la station ou le lot. `GET /batches/{batchCode}` renvoie un seul objet : le lot et la liste `movements`, dans l'ordre d'enregistrement.

Formats (observés au lot 3c) : les champs sont en camelCase ; la date de récolte s'écrit `2026-10-14` ; une quantité est un nombre, avec au plus 2 décimales et au plus 99 999 999,99 ; une heure est toujours en UTC : elle doit se terminer par `Z` ou porter un décalage, sinon l'API répond 400 sur `occurredAt`, et les heures renvoyées se terminent par `Z`. L'API refuse (400) un texte plus long que sa colonne (noms, région, variété, type de mouvement, statut) et une quantité que la colonne ne peut pas stocker. Swagger UI décrit les 10 routes, leurs réponses et leurs `errorCode`.

Attention : `GET /batches` calcule le total à chaque appel. Depuis le lot 5, il lit 1 737 pages sans filtre (47 pour une ferme de 25 000 lots) ; le filtre par statut lit encore 10 574 pages (voir [docs/mesures.md](docs/mesures.md), section 9.6). L'interface web appelle cette route à chaque page : la dernière page répond en 0,45 à 1,59 s par l'API (10 appels), mais la correction des échecs observés au lot 4a n'est pas prouvée (voir [docs/verification.md](docs/verification.md), sections 11.3 et 13.3). Les routes `POST` écrivent dans la base que l'API lit : pour des essais à la main, préférer une base de test.

### Interface web (lots 4a et 4b)

Prérequis : Node.js (v22.23.4 et npm 10.9.9 observés), l'API et ses deux bases (voir la section précédente). Les commandes sont à lancer dans PowerShell.

1. Dans un terminal, lancer l'API (étape 3 de la section précédente).
2. Dans un autre terminal, depuis le dossier `web/` : `npm install` (une seule fois), puis `npm run dev`. Vite écoute sur `http://localhost:5173/`. Le port est fixé (`strictPort`) : s'il est pris, le serveur s'arrête avec une erreur au lieu de changer de port, ce qui ferait échouer le CORS (voir l'[ADR 0007](docs/adr/0007-cors-dans-l-api.md)). L'API n'accepte l'interface qu'en développement (environnement `Development`, ce que donne le profil `https`).
3. Autres commandes, dans `web/` : `npm run lint`, `npm run build` (vérifie les types et écrit dans `dist/`, ignoré par git) et `npm test` (178 tests, sans API ni base).

L'interface appelle l'API sur `https://localhost:7080` ; la variable d'environnement `VITE_API_URL` remplace cette adresse. Aucun fichier `.env` n'est fourni.

Les 5 écrans de lecture (15 lignes par page) :

| Adresse | Écran |
|---|---|
| `/batches?status=…&farmCode=…&page=…` | liste des lots, avec filtres par statut et par ferme (l'accueil `/` y mène) |
| `/batches/{batchCode}` | un lot et son parcours, les heures en UTC |
| `/farms?page=…` | liste des fermes |
| `/stations?page=…` | liste des stations |
| `/stations/{stationCode}` | une station et ses fonctions |

Les filtres et la page sont dans l'adresse : recharger la page ou revenir en arrière garde l'écran. Les noms de fermes et de stations s'affichent tels qu'ils sont dans la base (en anglais pour les données inventées). Attention : sur le million de lots de `TraceabilityDev`, le bouton « Fin » de la liste des lots a répondu en 1,9 à 11,7 s à quatre essais et a échoué par dépassement de délai (30 s) à trois autres (voir [docs/verification.md](docs/verification.md), section 11.3).

Les écrans d'écriture (lot 4b) : chaque liste a un lien vers la page de création. Les erreurs de l'API s'affichent en français, un seul envoi part à la fois, et les heures se saisissent et s'envoient en UTC.

| Adresse | Écran |
|---|---|
| `/new-farm` | créer une ferme (code, nom, région) ; le message de succès reste sur la page et le formulaire est vidé |
| `/new-station` | créer une station (code, nom) ; ouvre la page de la station |
| `/new-batch` | créer un lot (code, ferme, variété, date de récolte, quantité, station et heure de réception en UTC) ; ouvre la page du lot |
| `/stations/{stationCode}` | en plus : ajouter une fonction (Réception, Tri, Emballage, Expédition) |
| `/batches/{batchCode}` | en plus : ajouter un mouvement (le formulaire propose l'étape suivante et la quantité actuelle) ; un lot expédié n'a plus de formulaire |

Ces écrans écrivent dans la base que l'API utilise. Pour les essayer sans toucher à `TraceabilityDev`, voir [docs/verification.md](docs/verification.md), section 12.4.
