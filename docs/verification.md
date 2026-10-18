# Vérification du lot 1

Ce document garde les preuves observées pour la base de données (lot 1). Le modèle est décrit dans [modele-de-donnees.md](modele-de-donnees.md) ; l'avancement du projet est dans le [README](../README.md).

Observé dans SQL Server (instance locale, base `TraceabilityDev`) le 2026-10-18, avec les scripts du dossier `database/`.

## 1. Les scripts

| Script | Rôle |
|---|---|
| `001_create_database.sql` | Crée la base de développement (rejouable). |
| `002_create_schema_and_tables.sql` | Crée le schéma `trace` et les 5 tables (non rejouable). |
| `003_check_schema.sql` | Inspecte la structure et lance 17 tests, annulés à la fin (rejouable). |
| `900_reset_dev_database.sql` | Supprime la base de développement. Verrouillé : il ne fait rien tant que `@confirm` n'est pas changé en `YES`. |

## 2. Ce qui est prouvé

- La base est créée avec le classement `French_CI_AS` et le mode de récupération `SIMPLE` (réglage de développement seulement). Un deuxième passage de `001` ne change rien.
- Un deuxième passage de `002` échoue (le schéma existe déjà) sans rien créer de plus.
- La structure correspond au modèle : 22 colonnes, types et longueurs conformes, toutes `NOT NULL`, seuls les 4 identifiants en `IDENTITY` ([modele-de-donnees.md](modele-de-donnees.md), section 2).
- Les contraintes existent : 8 clés primaires ou unicités, 8 `CHECK`, 4 clés étrangères (dont celle sur deux colonnes de `Movement` vers `StationCapability`). Il n'y a pas de clé étrangère simple `Movement` vers `Station`.
- 17 tests sur 17 conformes (section 3). Chaque refus est attribué à la bonne contrainte par le nom de la contrainte dans le message d'erreur. Après les tests, les 5 tables sont vides.
- La base se reconstruit de zéro : `900` (avec `@confirm` sur `YES`), puis `001`, `002` et `003` redonnent le même résultat (mêmes lignes d'inspection, 17 tests sur 17).
- Le verrou de `900` : sans changement du fichier, il affiche « Nothing done » et la base reste en place.

## 3. Les 17 tests

| # | Tentative | Résultat |
|---|---|---|
| 1 | Témoin : un mouvement valide | Accepté |
| 2 | Ferme : même code deux fois | Refusé par `UQ_Farm_Code` |
| 3 | Ferme : même code, autre casse (`zz-f01` après `ZZ-F01`) | Refusé par `UQ_Farm_Code` |
| 4 | Ferme : code vide | Refusé par `CK_Farm_Code_NotEmpty` |
| 5 | Station : même code deux fois | Refusé par `UQ_Station_Code` |
| 6 | Station : code vide | Refusé par `CK_Station_Code_NotEmpty` |
| 7 | Même fonction déclarée deux fois pour une station | Refusé par `PK_StationCapability` |
| 8 | Fonction inconnue (`LOST`) | Refusé par `CK_StationCapability_MovementType` |
| 9 | Fonction pour une station inexistante | Refusé par `FK_StationCapability_Station` |
| 10 | Lot : ferme inexistante | Refusé par `FK_Batch_Farm` |
| 11 | Lot : quantité 0 | Refusé par `CK_Batch_QuantityKg_Positive` |
| 12 | Lot : statut inconnu (`LOST`) | Refusé par `CK_Batch_Status` |
| 13 | Lot : même code deux fois | Refusé par `UQ_Batch_BatchCode` |
| 14 | Lot : code vide | Refusé par `CK_Batch_BatchCode_NotEmpty` |
| 15 | Mouvement : lot inexistant | Refusé par `FK_Movement_Batch` |
| 16 | Mouvement : quantité 0 | Refusé par `CK_Movement_QuantityKg_Positive` |
| 17 | Mouvement `PACKING` dans une station qui ne fait que `RECEPTION` | Refusé par `FK_Movement_StationCapability` |

## 4. Ce qui n'est pas prouvé

- `CK_Movement_MovementType` existe, mais aucun test ne le déclenche seul : la clé étrangère `FK_Movement_StationCapability` refuserait aussi la même valeur.
- Le « tout ou rien » de `002` : l'erreur observée est arrivée dès la première instruction, il n'y avait rien à défaire. Le garde-fou « Wrong database » a été testé seul (instructions isolées, connexion sur `master`), pas dans `002` lancé depuis une mauvaise base.
- L'ordre des colonnes de la clé primaire de `StationCapability` n'est pas affiché par `003` : le test 7 prouve seulement qu'un doublon est refusé.
- Le refus d'une valeur `NULL` : `NOT NULL` est vu dans le catalogue, mais aucun test n'insère de `NULL`.
- Les règles des procédures stockées (ordre des statuts, quantité qui ne monte pas, lot expédié, transaction unique) : lot 2, rien n'existe encore.
- Un seul environnement (SQL Server 2025 Developer sur le poste de développement) et aucun test de charge.

## 5. Rejouer la vérification

- Pour revérifier : exécuter `003_check_schema.sql` dans SSMS. Il est rejouable et ne garde aucune ligne.
- Pour tout reconstruire : dans `900_reset_dev_database.sql`, changer `@confirm` en `YES` (sans enregistrer le fichier) et l'exécuter, puis exécuter `001`, `002` et `003`.
