# Glossaire

Les termes techniques du projet, expliqués simplement, avec l'exemple de ce projet.

## Métier

**Traçabilité** : pouvoir reconstituer le parcours d'un produit, de son origine à sa destination. Ici : d'où vient un lot, par quelles stations il est passé, dans quel ordre.

**Journal (historique en ajout seul)** : une table où l'on ajoute des lignes mais où l'on ne modifie ni n'efface jamais rien. Ici : `trace.Movement`. Pour corriger, on ajoute une nouvelle ligne.

## Base de données

**Schéma SQL** : un « dossier » à l'intérieur de la base, qui regroupe des tables. Ici : `trace`.

**Clé primaire (PK)** : la colonne qui identifie une ligne de façon unique. Ici : `BatchId` dans `trace.Batch`.

**Clé composée** : une clé primaire faite de plusieurs colonnes. Ici : `StationId` + `MovementType` dans `trace.StationCapability`.

**`IDENTITY`** : un numéro que SQL Server génère tout seul (1, 2, 3…). Ici : tous les `...Id`.

**Clé étrangère (FK)** : une colonne qui pointe vers la clé d'une autre table. SQL Server refuse une valeur qui n'existe pas de l'autre côté. Ici : `Batch.FarmId` pointe vers `Farm.FarmId`.

**`UNIQUE` (UQ)** : interdit les doublons dans une colonne. Ici : `BatchCode`.

**`CHECK` (CK)** : une règle sur les valeurs acceptées. Ici : `QuantityKg > 0`, ou un statut qui doit être l'un des quatre connus.

**`NOT NULL`** : la colonne doit toujours avoir une valeur.

**`DECIMAL(10,2)`** : un nombre exact avec 2 chiffres après la virgule, sans erreur d'arrondi. Ici : les quantités en kg.

**`DATETIME2` et UTC** : une date et une heure précises. UTC est l'heure de référence mondiale, sans changement d'heure. Ici : `OccurredAt`.

**Transaction** : un groupe d'opérations « tout ou rien ». Si une étape échoue, tout est annulé. Dans ce projet : ajouter un mouvement et mettre à jour le lot dans la même transaction.

**Procédure stockée** : un petit programme enregistré dans la base, qu'on appelle par son nom. Dans ce projet : elle porte les règles métier (voir ADR 0001).

**Index** : comme l'index d'un livre, il aide SQL Server à retrouver des lignes plus vite. Les clés primaires et les contraintes `UNIQUE` en créent déjà. Dans ce projet : on en ajoute d'autres seulement après mesure (un seul retenu au lot 2b : `IX_Movement_BatchId`).

**Plan d'exécution** : la façon dont SQL Server compte exécuter une requête (quels index, dans quel ordre). Dans ce projet : on le lit pour comprendre pourquoi une requête est lente.

**Page** : l'unité de lecture de SQL Server, un bloc de 8 Ko. Une table ou un index est un ensemble de pages. Ici : la table `Batch` fait environ 10 400 pages pour un million de lots.

**Lecture logique** : une page lue en mémoire pour répondre à une requête. C'est la mesure principale du lot 2b : elle ne change pas d'une exécution à l'autre, contrairement au temps. Ici : `GetBatch` lisait 25 412 pages de `Movement` sans index.

**Scan et Seek** : un *Scan* parcourt une grande partie d'une table ou d'un index ; un *Seek* descend directement aux lignes cherchées. Dans SSMS en français : « Analyse » pour *Scan*, « Recherche » pour *Seek*. Ici : le parcours d'un lot passe d'un *Scan* de `Movement` à un *Seek* sur `IX_Movement_BatchId`.

**Index cluster et non cluster** : l'index cluster est la table elle-même, rangée dans l'ordre de la clé primaire (un seul par table). Un index non cluster est une structure séparée, à côté, qui renvoie vers les lignes par leur clé. Ici : `PK_Movement` est cluster, `IX_Movement_BatchId` est non cluster.

**Key Lookup** : pour chaque ligne trouvée par un index non cluster, SQL Server retourne lire la ligne dans la table pour récupérer les colonnes que l'index ne contient pas. Ici : 4 *Key Lookup* pour les 4 mouvements d'un lot.

**Index couvrant (colonnes incluses)** : un index qui contient aussi les colonnes demandées (`INCLUDE`), donc sans *Key Lookup*, mais plus gros. Ici : essayé sur `Movement` (3 lectures au lieu de 15, mais 184,88 Mo au lieu de 56,72 Mo) et écarté (voir ADR 0004).

**Index forcé (`WITH (INDEX (...))`)** : on impose un index précis à SQL Server au lieu de le laisser choisir. Ici : utilisé seulement pour comprendre une mesure, jamais dans les procédures.

**Authentification Windows** : se connecter à SQL Server avec son compte Windows, sans mot de passe. Utilisée en local.

**`THROW`** : lève une erreur avec un numéro et un message choisis, et arrête la procédure. Ici : `THROW 50301, ...` quand un mouvement saute une étape.

**Session** : une connexion ouverte à SQL Server, identifiée par un numéro (`@@SPID`). Ici : deux fenêtres SSMS sont deux sessions (56 et 55 dans l'essai du verrou).

**Verrou** : une réservation posée sur des lignes pendant qu'une transaction s'en sert. Les autres sessions qui veulent les mêmes lignes attendent. Ici : `AddMovement` réserve la ligne du lot.

**`UPDLOCK`** : un verrou « je lis cette ligne pour la modifier ». Une autre session qui veut faire pareil attend ; une simple lecture n'attend pas (observé). Ici : posé par `AddMovement` (voir ADR 0003).

**Blocage mutuel (deadlock)** : deux sessions qui s'attendent l'une l'autre sans fin ; SQL Server en arrête une avec l'erreur 1205. Ici : pas observé, à surveiller (voir ADR 0003).

**Mode SQLCMD et `:setvar`** : un mode de SSMS (menu Requête > Mode SQLCMD, réglé fenêtre par fenêtre) où `:setvar DbName TraceabilityTest` définit une variable, remplacée dans le script par `$(DbName)`. Ici : choisir la base de développement ou de test.

**Garde `NOEXEC`** : `SET NOEXEC ON` fait ignorer le reste du script. Ici : utilisé quand la base n'est pas la bonne, pour que rien ne soit exécuté.

**Pagination (`OFFSET` / `FETCH`)** : renvoyer les lignes par pages (la page 2 de 50 lignes, par exemple). Ici : `ListBatches`, `ListFarms` et `ListStations`, qui renvoient aussi le total ; l'API répond avec `items`, `totalCount`, `pageNumber` et `pageSize`.

## .NET et C#

**C#** : le langage de programmation principal de .NET. Il ressemble à TypeScript : typé, avec des classes et `async` / `await`. Ici : les fichiers `.cs` (`Program.cs`, `TraceabilityDb.cs`).

**`.csproj` et `.dll`** : un fichier `.csproj` décrit un projet en XML (version de .NET, paquets utilisés). La compilation le transforme en un fichier `.dll`, le code compilé. Ici : `Traceability.Data.csproj` donne `Traceability.Data.dll`.

**Projet et solution** : un projet est une unité de code qui se compile seule. Une solution est un fichier qui liste des projets pour les traiter ensemble ; elle ne contient pas de code. Ici : `Traceability.slnx` (l'extension donnée par le SDK 10.0.402) liste 4 projets : `Data`, `Api`, `UnitTests` et `IntegrationTests`.

**Référence entre projets** : être dans la même solution ne suffit pas, un projet doit déclarer qu'il utilise un autre. Ici : `Api` utilise `Data`, les deux projets de tests utilisent `Api`, et `IntegrationTests` utilise aussi `Data`.

**Paquet NuGet et restauration** : NuGet est le registre de paquets de .NET, l'équivalent de npm. `dotnet add package` ajoute un paquet à un projet ; la restauration télécharge les paquets dont un projet a besoin (comme `npm install`). Ici : `Microsoft.Data.SqlClient` 7.1.1.

**Dépendance transitive** : un paquet que ton paquet tire avec lui, sans que tu l'aies demandé. Ici : `Microsoft.Data.SqlClient` tire `System.Security.Cryptography.Pkcs` 9.0.18, qui avait deux avis de sécurité (avertissements NU1902 et NU1903). Imposer la version 10.0.13 dans `Traceability.Data` les a fait disparaître.

**Variable d'environnement** : une valeur que Windows donne à chaque programme qui démarre, comme `process.env` en Node. Un programme ne voit que celles qui existaient quand il a démarré. Ici : `ConnectionStrings__Default` et `ConnectionStrings__Test`.

**Chaîne de connexion** : le texte qui dit à un programme comment joindre une base. Ici : serveur `localhost`, base `TraceabilityDev` ou `TraceabilityTest`, authentification Windows. ASP.NET Core lit `ConnectionStrings__Default` comme la clé `ConnectionStrings:Default` (le double tiret bas remplace les deux-points).

**Certificat HTTPS de développement** : un fichier qui prouve l'identité d'un serveur HTTPS. Celui de .NET est signé par lui-même, donc Windows ne lui fait pas confiance tant qu'on ne l'a pas approuvé, une fois. Ici : `dotnet dev-certs https --trust`, puis l'API répond en HTTPS sur le port 7080 sans avertissement.

**`TrustServerCertificate`** : un réglage de la chaîne de connexion qui accepte le certificat d'un serveur SQL même s'il n'est pas vérifiable. Acceptable seulement en local. Ici : sans lui, la connexion depuis .NET échoue (« autorité qui n'est pas approuvée ») ; avec lui, elle réussit.

**`async` / `await`** : écrire du code qui attend une réponse (base, réseau) sans bloquer le programme. Ici : toutes les méthodes de `TraceabilityDb` finissent par `Async`.

**Injection de dépendances** : ASP.NET Core construit lui-même les objets dont une classe a besoin et les lui donne par son constructeur, comme dans NestJS. Ici : `FarmsController(TraceabilityDb db)` reçoit la classe d'accès aux données enregistrée dans `Program.cs`.

**Contrôleur** : une classe qui reçoit les requêtes HTTP d'une ressource, avec des attributs (`[Route]`, `[HttpGet]`, `[HttpPost]`). Ici : `FarmsController` (2 routes) et `StationsController` (4 routes).

## API et tests

**API REST** : un programme qui répond à des requêtes web (par exemple « donne-moi le lot X ») et renvoie des données. Dans ce projet : une API ASP.NET Core.

**ADO.NET** : la bibliothèque .NET de base pour parler à SQL Server et appeler une procédure stockée. Ici : retenue (voir ADR 0005), dans la classe `TraceabilityDb`.

**Dapper** : une petite bibliothèque au-dessus d'ADO.NET qui simplifie la lecture des résultats. Ici : non retenue (voir ADR 0005).

**Entity Framework Core (EF Core)** : un outil qui génère le SQL à partir du code C#. Non retenu pour les règles métier de ce projet (voir ADR 0001).

**Test d'intégration** : un test qui vérifie plusieurs éléments ensemble, ici la procédure et une vraie base SQL Server (voir ADR 0002).

**Test de refus et test témoin** : un test de refus vérifie qu'un appel interdit est refusé (bon numéro d'erreur) sans rien changer. Un test témoin vérifie qu'un appel valide passe et produit l'effet attendu. Ici : `006_check_procedures.sql`.

**Codes HTTP d'erreur utilisés** : 400 requête invalide, 404 introuvable, 409 existe déjà, 422 règle métier violée, 500 erreur imprévue du serveur. Ici : les erreurs des procédures sont traduites par famille de numéro (501xx en 404, 502xx en 409, 503xx en 422, 504xx en 400).

**Problem Details** : le format standard d'une réponse d'erreur HTTP en JSON (`type`, `title`, `status`, `detail`). Ici : un champ `errorCode` y est ajouté pour les erreurs des procédures, par exemple `errorCode` 50102 dans un 404.

**OpenAPI et Swagger UI** : OpenAPI est la description d'une API dans un fichier JSON ; Swagger UI est la page web qui l'affiche et laisse essayer les routes. Ici : `https://localhost:7080/swagger`, activée en développement seulement.

**Test unitaire** : un test d'un petit morceau de code, seul, sans base ni réseau. Ici : 49 cas pour la traduction des erreurs, la forme des codes et la page par défaut.

**Test par HTTP (`WebApplicationFactory`)** : un test qui lance la vraie API dans le programme de test et lui envoie de vraies requêtes. Ici : 25 cas sur `TraceabilityTest`.

**xUnit : `[Fact]`, `[Theory]` et `[InlineData]`** : `[Fact]` est un test ; `[Theory]` avec des lignes `[InlineData]` est le même test répété avec plusieurs valeurs, et chaque ligne compte comme un cas. Ici : les 8 tests unitaires du plan font 49 cas.

**Fixture de test** : un objet construit une seule fois avant les tests d'un groupe et partagé par eux. Ici : `ApiFixture` vérifie la base, vide les 5 tables de `TraceabilityTest` et lance l'API.

**CORS** : une règle appliquée par le navigateur : une page web ne peut appeler une API située à une autre adresse que si l'API l'autorise. Ici : non configuré, aucun frontend n'a été essayé.

**Casse volontaire d'un test** : on change une ligne du code pour vérifier que les tests la voient, puis on la rétablit. Ici : la famille 502xx de 409 à 400 donne 4 échecs unitaires et 3 d'intégration ; le fichier rétabli a la même empreinte que l'original.

## Organisation

**ADR (Architecture Decision Record)** : un court document qui garde la trace d'une décision, de ses alternatives et de ses conséquences. Dans `docs/adr/`.

**CI/CD** : l'exécution automatique de la construction et des tests à chaque modification (dans ce projet : GitHub Actions).
