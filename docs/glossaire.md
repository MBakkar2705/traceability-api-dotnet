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

**Index** : comme l'index d'un livre, il aide SQL Server à retrouver des lignes plus vite. Les clés primaires et les contraintes `UNIQUE` en créent déjà. Dans ce projet : on en ajoute d'autres seulement après mesure.

**Plan d'exécution** : la façon dont SQL Server compte exécuter une requête (quels index, dans quel ordre). Dans ce projet : on le lit pour comprendre pourquoi une requête est lente.

**Authentification Windows** : se connecter à SQL Server avec son compte Windows, sans mot de passe. Utilisée en local.

## API et tests

**API REST** : un programme qui répond à des requêtes web (par exemple « donne-moi le lot X ») et renvoie des données. Dans ce projet : une API ASP.NET Core.

**ADO.NET** : la bibliothèque .NET de base pour parler à SQL Server et appeler une procédure stockée.

**Dapper** : une petite bibliothèque au-dessus d'ADO.NET qui simplifie la lecture des résultats.

**Entity Framework Core (EF Core)** : un outil qui génère le SQL à partir du code C#. Non retenu pour les règles métier de ce projet (voir ADR 0001).

**Test d'intégration** : un test qui vérifie plusieurs éléments ensemble, ici la procédure et une vraie base SQL Server (voir ADR 0002).

## Organisation

**ADR (Architecture Decision Record)** : un court document qui garde la trace d'une décision, de ses alternatives et de ses conséquences. Dans `docs/adr/`.

**CI/CD** : l'exécution automatique de la construction et des tests à chaque modification (dans ce projet : GitHub Actions).
