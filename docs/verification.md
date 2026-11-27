# Vérification

Ce document garde les preuves observées : la base de données (lot 1, sections 1 à 5), les procédures stockées (lot 2a, section 6) et les données volumineuses, les index et les mesures (lot 2b, section 7), puis les procédures de lecture pour l'API (lot 3a, section 8), l'API des fermes et des stations (lot 3b, section 9), l'API des lots (lot 3c, section 10), l'interface web de lecture (lot 4a, section 11), l'interface web d'écriture (lot 4b, section 12), l'optimisation de la liste des lots (lot 5, section 13), l'intégration continue (lot 6, section 14), SQL Server en conteneur (lot 7, section 15), l'API en conteneur (lot 8, section 16), la CI complétée (lot 9, section 17), l'authentification (lots 10a à 10c, sections 18 à 20) et l'auteur de chaque mouvement (lot 11, section 21). Le modèle est décrit dans [modele-de-donnees.md](modele-de-donnees.md) ; l'avancement du projet est dans le [README](../README.md).

Chaque section « Ce qui n'est pas prouvé » date de son lot. Un point peut avoir été réglé depuis : la preuve est alors dans la section « Ce qui est prouvé » du lot concerné. Le texte d'origine n'est pas modifié : pour les points réglés repérés le 2026-10-27, une note datée renvoie à la preuve.

Lot 1 : observé dans SQL Server (instance locale, base `TraceabilityDev`) le 2026-10-18, avec les scripts du dossier `database/`.

## 1. Les scripts

| Script | Rôle |
|---|---|
| `001_create_database.sql` | Crée la base de développement (rejouable). |
| `002_create_schema_and_tables.sql` | Crée le schéma `trace` et les 5 tables (non rejouable). |
| `003_check_schema.sql` | Inspecte la structure et lance 17 tests, annulés à la fin (rejouable). |
| `900_reset_dev_database.sql` | Supprime la base de développement. Verrouillé : il ne fait rien tant que `@confirm` n'est pas changé en `YES`. |
| `004_create_reference_procedures.sql` (lot 2a) | Crée `CreateFarm`, `CreateStation`, `AddStationCapability`. |
| `005_create_batch_procedures.sql` (lot 2a) | Crée `CreateBatch`, `AddMovement`, `GetBatch`, `ListBatches`. |
| `006_check_procedures.sql` (lot 2a) | 38 tests des procédures, uniquement sur `TraceabilityTest`. |

Depuis le lot 2a, `001` à `005` et `900` lisent le nom de la base dans `:setvar DbName` (mode SQLCMD de SSMS) ; `006` est écrit pour `TraceabilityTest` seulement.

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
- Les règles des procédures stockées (ordre des statuts, quantité qui ne monte pas, lot expédié, transaction unique) étaient hors du lot 1 : elles sont vérifiées à la section 6.
- Un seul environnement (SQL Server 2025 Developer sur le poste de développement) et aucun test de charge.

## 5. Rejouer la vérification

- Pour revérifier : exécuter `003_check_schema.sql` dans SSMS. Il est rejouable et ne garde aucune ligne.
- Pour tout reconstruire : dans `900_reset_dev_database.sql`, changer `@confirm` en `YES` (sans enregistrer le fichier) et l'exécuter, puis exécuter `001`, `002` et `003`.

## 6. Lot 2a : procédures stockées

Observé dans SQL Server (instance locale 17.0) le 2026-10-19, sur la base `TraceabilityTest` sauf mention contraire. Le contrat des procédures est dans [procedures.md](procedures.md), la décision sur le verrou dans l'[ADR 0003](adr/0003-verrou-sur-le-lot.md). Les heures sont en UTC.

### 6.1 Ce qui est prouvé

- Les scripts `001` à `003` et `900` prennent le nom de la base dans `:setvar DbName` : reconstruction de zéro puis `003` sur `TraceabilityDev` (avec `900`), et création puis `003` sur `TraceabilityTest`, 17 tests sur 17 pour chacune.
- `900` refuse un nom de base hors liste (seules `TraceabilityDev` et `TraceabilityTest` sont acceptées) et reste verrouillé tant que `@confirm` est sur `NO`.
- La garde « mauvaise base » de `002` : lors d'un essai accidentel avec le mode SQLCMD désactivé, elle a arrêté le script (erreur 50001) sans rien créer ; un `002` correct a ensuite réussi sur `TraceabilityTest`.
- La garde de `004` a été observée à l'échec : sur une mauvaise base, rien n'est exécuté.
- `004` et `005` s'exécutent sans erreur sur `TraceabilityTest` : les 7 procédures du schéma `trace` sont listées.
- `006` : 38 tests, dont 37 automatiques conformes et 1 vérifié à l'œil (test 30, contenu des deux tableaux de `GetBatch`). Un test de refus n'est conforme que si le numéro d'erreur est le bon, si les données sont inchangées (empreinte des 5 tables avant et après) et si aucune transaction n'est restée ouverte. Un test témoin n'est conforme que si l'effet attendu est bien là.
- `006` est rejouable : trois passages (10:58, 10:59 et 11:23) ont donné le même verdict, `38 / 37 / 1`. Au premier passage, les 5 `DELETE` de nettoyage n'ont supprimé aucune ligne ; à celui de 11:23, ils ont supprimé 6, 12, 6, 5 et 4 lignes, soit celles laissées par les passages précédents.

### 6.2 Les 38 tests de `006`

| Procédure | Tests | Ce qui est vérifié |
|---|---|---|
| `CreateFarm` | 1 à 4 | Témoin (ferme créée et renvoyée) ; code vide (50400) ; code déjà pris (50200), aussi avec une autre casse |
| `CreateStation` | 5 à 7 | Témoin ; code vide (50400) ; code déjà pris (50201) |
| `AddStationCapability` | 8 à 11 | Témoin (`reception` donné, `RECEPTION` enregistré) ; type inconnu (50402) ; station inconnue (50102) ; fonction déjà déclarée (50203) |
| `CreateBatch` | 12 à 18 | Témoin (lot `RECEIVED` et un mouvement `RECEPTION`) ; code vide (50400) ; quantité 0 (50401) ; ferme inconnue (50101) ; station inconnue (50102) ; code déjà pris (50202) ; station sans `RECEPTION` (50303) |
| `AddMovement` | 19 à 29 | Témoins (`RECEIVED` vers `SORTED` ; chemin complet jusqu'à `SHIPPED`, quantité égale acceptée) ; quantité 0 (50401) ; type inconnu (50402) ; lot inconnu (50100) ; station inconnue (50102) ; lot déjà expédié (50300) ; étape sautée et étape répétée (50301) ; station sans la fonction (50303) ; quantité qui monte (50302) |
| `GetBatch` | 30 et 31 | Témoin (contenu vérifié à l'œil) ; lot inconnu (50100) |
| `ListBatches` | 32 à 38 | Filtre par statut ; filtre par ferme ; statut inconnu (50403) ; ferme inconnue (50101) ; page 0 et taille 1 001 (50404) ; pages successives sans trou ni doublon |

Au lot 3a, `ListBatches` a reçu un second tableau (le total) : les tests 32, 33 et 38 ne capturent plus le résultat et sont passés à l'œil, et le résumé attendu de `006` est devenu `38 / 34 / 4` (voir la section 8). Les chiffres `38 / 37 / 1` de la section 6.1 ont été observés avec l'ancienne `ListBatches`.

### 6.3 Le verrou : essai à la main

Deux fenêtres SSMS sur `TraceabilityTest` : la session A (numéro 56) et la session B (numéro 55). Le lot `ZZ-B-RECV` est laissé `RECEIVED` à 500.00 kg par `006`.

**Partie 1 : le verrou seul** (11:18 à 11:22).

1. A ouvre une transaction et lit le lot avec `UPDLOCK`, sans rien modifier.
2. B lit le lot avec un `SELECT` simple : la ligne s'affiche tout de suite.
3. B appelle `AddMovement` (`SORTING`, 400.00 kg) : l'appel ne se termine pas.
4. Vu depuis A dans `sys.dm_exec_requests` : la session 55 est bloquée par la session 56, `wait_type` = `LCK_M_U` (attente d'un verrou de mise à jour), `wait_ms` = 59 461.
5. A fait `ROLLBACK` : l'appel de B se termine environ 30 ms plus tard, sans erreur. Le lot est `SORTED` à 400.00 kg.

Ce que cela montre : B attend alors que A n'a rien modifié. `AddMovement` demande donc bien un verrou de mise à jour sur le lot, ce que la simple lecture de l'étape 2 ne fait pas.

**Partie 2 : deux mouvements contradictoires** (11:24 à 11:27), après remise du lot à `RECEIVED` / 500.00 kg en relançant `006`.

1. A ouvre une transaction et appelle `AddMovement` (`SORTING`, 400.00 kg) sans valider : A voit le lot `SORTED` à 400.00 kg et une transaction ouverte.
2. B appelle `AddMovement` (`SORTING`, 450.00 kg) : l'appel ne se termine pas.
3. A valide (`COMMIT`) à 11:25:53.158. B reçoit environ 44 ms plus tard l'erreur 50301 : « Batch 'ZZ-B-RECV' is SORTED: the next movement must be PACKING, not SORTING. » Elle avait attendu 42 secondes.
4. Contrôle final : aucune transaction ouverte dans A ni dans B (`@@TRANCOUNT` = 0). `ZZ-B-RECV` n'a qu'un mouvement : `SORTING`, 400.00 kg, 09:15. Rien du mouvement de B (450.00 kg, 09:20).

Ce que cela montre : le second appel attend, relit le lot après la validation du premier, et est refusé avec la bonne règle, sans mouvement en double.

### 6.4 Ce qui n'est pas prouvé

- Le comportement **sans** `UPDLOCK` n'a pas été essayé : on ne sait pas ce que le verrou apporte en plus de la modification faite par le premier appel. La partie 1 montre que la procédure demande le verrou ; la partie 2 montre le résultat voulu ; aucune des deux ne montre le défaut que le verrou évite.
- Deux appels sur deux lots différents ne s'attendent pas : c'est voulu (ADR 0003), mais non observé.
- Dans la partie 2, le premier appel était lancé dans une transaction ouverte par l'appelant. Deux appels indépendants lancés en même temps n'ont pas été essayés. L'effet du `ROLLBACK` de la procédure sur la transaction de l'appelant, en cas d'erreur, n'a pas été essayé non plus.
- Les blocages mutuels (deadlock), la charge et le délai d'attente : non essayés.
- Deux créations simultanées avec le même code (`CreateFarm`, `CreateStation`, `CreateBatch`) : l'erreur d'unicité attendue de SQL Server n'a pas été observée.
- L'atomicité en cours de procédure : les tests de refus montrent que rien ne change quand un contrôle échoue, mais aucune panne n'a été provoquée entre deux écritures de `CreateBatch` ou `AddMovement`.
- Les codes `NULL` (traités comme vides, 50400) : les tests utilisent des espaces, pas `NULL`.
- Les types en minuscules : seul `AddStationCapability` est testé (test 8), pas `AddMovement`.
- `ListBatches` : les deux filtres combinés et l'appel sans filtre ne sont pas testés. La lenteur sur un grand volume a été mesurée au lot 2b (section 7 et [mesures.md](mesures.md)).
  - Note du 2026-10-27, ajoutée après coup : au lot 5, l'ancienne et la nouvelle requête de la page ont rendu les mêmes lignes sur 6 cas, dont « statut et ferme » et la page sans filtre (section 13.2). Ce ne sont pas des tests de `006`.
- `GetBatch` : le contenu n'est vérifié qu'à l'œil (test 30).
- La suppression de `TraceabilityTest` par `900` n'a pas été essayée (seulement sur `TraceabilityDev`).
- Un seul environnement (SQL Server 2025 Developer sur le poste de développement).

### 6.5 Rejouer la vérification

- Procédures : dans SSMS, ouvrir `006_check_procedures.sql` (il vise `TraceabilityTest`, le mode SQLCMD n'est pas nécessaire) et l'exécuter, de préférence avec les résultats en texte. Attendu : `tests_total` 38, `tests_ok` 37, `tests_by_eye` 1, et le test 30 vérifié à l'œil avec les valeurs écrites dans les messages au-dessus des deux tableaux.
- `006` laisse ses lignes dans `TraceabilityTest`. Ne pas relancer `003` sur cette base sans la reconstruire : `003` attend des tables vides et utilise les mêmes codes `ZZ-F01` et `ZZ-S01` (non essayé).
- Reconstruire la base de test : dans `900`, mettre `:setvar DbName TraceabilityTest` et `@confirm` sur `YES` (sans enregistrer), l'exécuter, puis exécuter `001` à `006` (la suppression de `TraceabilityTest` par `900` n'a pas encore été essayée).
- Verrou : essai à la main avec deux fenêtres, voir la section 6.3. Les requêtes exactes de cet essai ne sont pas gardées dans le dépôt.

## 7. Lot 2b : données volumineuses, index et mesures

Observé le 2026-10-19 dans SQL Server 2025 Developer (17.0.1145.4), base `TraceabilityDev`, SSMS 22, environ 8 Go de mémoire, disque `C:` de 237,60 Go. Les données sont inventées. Les mesures et leur analyse sont dans [mesures.md](mesures.md), la décision sur l'index dans l'[ADR 0004](adr/0004-index-simple-sur-mouvement-par-lot.md).

### 7.1 Les scripts

| Script | Rôle |
|---|---|
| `007_generate_volume_data.sql` | Génère les lots et leurs mouvements par formules fixes (pas de hasard), par lots de 100 000. Reprenable. Vise `TraceabilityDev`. |
| `008_check_volume_data.sql` | Contrôle les données générées : 28 contrôles, plus les tailles. Lecture seule. |
| `009_measure_searches.sql` | Mesure les recherches de l'API (lectures logiques, temps, plans). Lecture seule. Exige le million de lots et les procédures de `004` et `005`. |
| `010_create_indexes.sql` | Crée l'index retenu, `IX_Movement_BatchId`. Rejouable. |

`003` a été modifié pour montrer que les nombres de lignes ne changent pas. `900` a seulement vu son texte corrigé (voir 7.3).

### 7.2 Ce qui est prouvé

- **Échantillon de 10 000 lots** : `007` a produit 200 fermes, 30 stations, 40 fonctions, 10 000 lots et 40 000 mouvements, et `008` a donné 28 contrôles sur 28.
- **Un million de lots** : `007`, relancé avec 1 000 000, a repris au lot 10 001 (les 10 000 déjà présents ont été gardés) et est arrivé jusqu'au lot 1 000 000 par lots de 100 000, avec le message « Done ». `008` a donné 28 contrôles sur 28 : 600 000 `SHIPPED`, 150 000 `PACKED`, 150 000 `SORTED`, 100 000 `RECEIVED`, 3 250 000 mouvements, aucune quantité qui monte, aucune perte de plus de 10 %, aucun mouvement hors ordre ou à une station sans la fonction.
- **`008` relancé** après la création des procédures `004` et `005` et de l'index `IX_Movement_BatchId` : toujours 28 contrôles sur 28.
- **`003` sur la base remplie** : 17 tests sur 17, et les cinq tables ont le même nombre de lignes avant et après (« unchanged »).
- **Tailles observées par `008`** : table `Batch` 81,44 Mo, `UQ_Batch_BatchCode` 58,51 Mo, table `Movement` 194,92 Mo ; avec `IX_Movement_BatchId` (56,72 Mo), environ 391,70 Mo utilisés au total.
- **Mesures** (détail dans [mesures.md](mesures.md)) : le parcours d'un lot (`GetBatch`) lisait 25 412 pages de `Movement` sans index et en lit 15 avec `IX_Movement_BatchId` (*Seek*, pas de tri). `Batch (Status)` et `Batch (FarmId)` ont été essayés et abandonnés : SQL Server ne s'en servait pas, et `Batch (FarmId)` forcé faisait pire.
- **`010`** : l'index a été créé, et un deuxième lancement a affiché « Index IX_Movement_BatchId already exists. Nothing done. » sans erreur.
- **`009`** : lancé avant la création des procédures dans `TraceabilityDev`, il a échoué avec l'erreur SQL Server « Procédure stockée introuvable » pour chaque appel. Les procédures ont alors été créées avec `004` et `005`. Après l'ajout de la garde 50006, `009` a été relancé avec les procédures présentes, sans erreur.

### 7.3 Ce qui n'est pas prouvé

- **Un échec en cours de génération** : aucune panne n'a été provoquée au milieu d'un lot de 100 000 (annulation du lot, puis reprise). La reprise n'a été observée qu'après un arrêt normal.
- **Les gardes de `007`** : 50002 (valeur de `@TargetLots`), 50003 (contenu inattendu), 50004 (fermes ou stations différentes) et 50005 (espace disque sous 40 Go) n'ont jamais été déclenchées. Le disque est resté au-dessus de 49 Go. Les gardes 50001 (mauvaise base) des scripts `007` à `010` n'ont pas été déclenchées non plus.
- **La garde 50006 de `009`** : seul le cas normal (procédures présentes) a été observé, pas le refus.
- **`900`** : son texte a été corrigé (« rejouer `001`, `002`, `004`, `005` »), mais le script n'a pas été relancé depuis.
- **L'espace disque** : l'espace libre sur `C:` est passé d'environ 50,5 Go à environ 49,5 Go, un peu plus que la taille des fichiers de la base (392 Mo de données et 264 Mo de journal). La différence n'a pas été expliquée ; `tempdb` et le pic du journal n'ont pas été mesurés.
- **Taille de `UQ_Batch_BatchCode`** : 58,51 Mo observés, au-dessus de l'extrapolation faite depuis l'échantillon (environ 38 Mo). La cause n'a pas été examinée (la fragmentation n'a pas été regardée).
- **Les mesures** : la mesure « avant » est une première exécution (temps gonflés par les lectures sur disque). Les plans de R3 `F001`, de R4 `SHIPPED` et des requêtes forcées n'ont pas été examinés. R6 (plan réutilisé) est restée non conclue. Le coût des index sur les écritures (`CreateBatch`, `AddMovement`) n'est pas mesuré.
- **Les causes** : pourquoi SQL Server n'utilise pas `IX_Batch_Status` (probablement une estimation fondée sur des lots `RECEIVED` répartis au hasard) et pourquoi `IX_Batch_FarmId` forcé est plus coûteux (probablement les allers-retours dans la table) sont des explications probables, non prouvées.
- **Les données** : inventées, régulières, générées par des formules fixes. Un seul environnement, une seule machine, aucun test de charge.
- **Les requêtes jetables** de l'analyse (`sp_recompile`, requêtes avec index forcé, `DROP INDEX`) ne sont pas gardées dans le dépôt, sauf celle de la variante couvrante, écrite dans [mesures.md](mesures.md).

### 7.4 Rejouer la vérification

- Prérequis : `TraceabilityDev` reconstruite avec `001`, `002`, `004` et `005` (mode SQLCMD actif pour ces scripts).
- Données : ouvrir `007_generate_volume_data.sql`, régler `@TargetLots` (10 000 pour un échantillon, 1 000 000 pour le jeu complet, sans enregistrer le changement) et l'exécuter. Puis `008_check_volume_data.sql` : `checks_ok` doit être égal à `checks_total`.
- Index : `010_create_indexes.sql`.
- Mesures : `009_measure_searches.sql` avec le plan d'exécution réel actif (Ctrl+M). Les lectures logiques sont stables d'une exécution à l'autre, les temps non.
- `007`, `008`, `009` et `010` n'ont pas besoin du mode SQLCMD.

## 8. Lot 3a : procédures de lecture pour l'API

Observé dans SQL Server (instance locale 17.0) le 2026-10-20, sur la base `TraceabilityTest` sauf mention contraire, avec SSMS 22. Le contrat des procédures est dans [procedures.md](procedures.md), sections 2.7 à 2.10. Les données de test sont inventées.

Pourquoi un lot 3a : l'étude de l'API .NET a montré que le SQL manquait de trois procédures de lecture (`ListFarms`, `ListStations` et `GetStation`) et d'un total pour la liste des lots (`ListBatches`). Elles forment le lot 3a, avant l'API.

### 8.1 Les scripts

| Script | Rôle |
|---|---|
| `011_create_list_procedures.sql` | Crée `ListFarms`, `ListStations` et `GetStation`. `CREATE OR ALTER`, mode SQLCMD. À lancer sur `TraceabilityDev` et sur `TraceabilityTest`. |
| `012_check_list_procedures.sql` | 16 tests des trois procédures, uniquement sur `TraceabilityTest` (sans SQLCMD). Ses données de test commencent par `ZY-`, pour ne pas toucher à celles de `006` (`ZZ-`). |
| `005_create_batch_procedures.sql` (modifié) | `ListBatches` renvoie un second tableau, `TotalCount`, avec les mêmes filtres que la page. |
| `006_check_procedures.sql` (modifié) | Les tests 32, 33 et 38 passent à l'œil (`WITH RESULT SETS`, attendu affiché dans la grille). Résumé attendu : `38 / 34 / 4`. |
| `009_measure_searches.sql` (non modifié) | Relancé pour mesurer le coût du total (voir [mesures.md](mesures.md), section 4.3). |

### 8.2 Ce qui est prouvé

- `011` exécuté sur `TraceabilityDev` : la liste des procédures du schéma `trace` affiche 10 lignes, dont `GetStation`, `ListFarms` et `ListStations`.
- Sur `TraceabilityTest`, les 3 procédures existent : la garde de `012` l'exige, et `012` s'est exécuté jusqu'au bout.
- `012`, premier passage : résumé `16 / 10 / 6` (`tests_total`, `tests_ok`, `tests_by_eye`). Les 10 tests automatiques sont tous conformes : bon numéro d'erreur, données inchangées (empreinte des 5 tables avant et après), aucune transaction restée ouverte.
- Les 6 tests de contenu de `012` ont été vérifiés un par un sur les tableaux affichés par SSMS (le script en contrôle seulement le nombre et la forme, avec `WITH RESULT SETS`) :
  - `ListFarms`, page 1 de taille 1 000 : 9 fermes, les 5 dernières sont `ZY-F01` à `ZY-F05` dans cet ordre, `TotalCount` vaut 9. `ZZ-F10`, créée plus tard par `006`, vient après `ZZ-F03` : le tri suit l'ordre de création.
  - `ListFarms`, page au-delà de la fin (taille 1) : premier tableau vide, `TotalCount` toujours 9.
  - `ListStations`, page 1 de taille 1 000 : 10 stations, les 5 dernières sont `ZY-S01` à `ZY-S05` dans cet ordre, `TotalCount` vaut 10.
  - `ListStations`, page au-delà de la fin : premier tableau vide, `TotalCount` toujours 10.
  - `GetStation` `ZY-S01` : la station `Test station Y1` et 2 fonctions, `RECEPTION` puis `SORTING`, alors qu'elles ont été insérées dans l'ordre inverse : la procédure les trie elle-même.
  - `GetStation` `ZY-S02` : la station `Test station Y2` et un tableau de fonctions vide.
- Une taille de page de 1 et de 1 000 est acceptée ; la page 0, la taille 0, la taille 1 001 et un numéro de page `NULL` sont refusés (50404) pour les deux listes. Une station inconnue et un code `NULL` sont refusés (50102) par `GetStation`.
- `005` modifié, puis relancé sur `TraceabilityDev` et sur `TraceabilityTest`, où les procédures existaient déjà : le rejeu a fonctionné. Sur `TraceabilityDev`, `ListBatches` sans filtre, page 1 de taille 3, renvoie `LOT-0000001`, `LOT-0000002`, `LOT-0000003`, puis `TotalCount = 1000000`.
- `006` rejoué sur `TraceabilityTest` avec la nouvelle `ListBatches` : résumé `38 / 34 / 4` et 0 erreur dans la Liste d'erreurs. Les 34 tests automatiques sont conformes, dont les refus 34 à 37 de `ListBatches`.
- Les 3 tests modifiés de `006` ont été vérifiés à l'œil :
  - test 32 (statut `SORTED`) : 2 lignes, `ZZ-B-SORT` et `ZZ-B-W1`, toutes `SORTED`, `ZZ-B-RECV` absente, `TotalCount` vaut 2 ;
  - test 33 (ferme `ZZ-F02`) : exactement `ZZ-B-F2A` (`RECEIVED`) et `ZZ-B-F2B` (`SHIPPED`), `TotalCount` vaut 2 ;
  - test 38 (ferme `ZZ-F03`, pages de 2) : page 1 = `ZZ-P1`, `ZZ-P2` ; page 2 = `ZZ-P3`, `ZZ-P4` ; page 3 = `ZZ-P5` ; `TotalCount` vaut 5 sur chacune des trois pages, sans trou ni doublon.
- `009` relancé sur `TraceabilityDev` avec la nouvelle `ListBatches` : les lectures de la page sont celles du lot 2b, et le total lit 10 574 pages de `Batch` dans les 5 cas (détail dans [mesures.md](mesures.md), section 4.3).

### 8.3 Ce qui n'est pas prouvé

- **Le rejeu de `012`** : un seul passage a été fait. Le nettoyage des lignes `ZY-` au deuxième passage n'a pas été observé.
- **Le rejeu de `011`** : `CREATE OR ALTER` est conçu pour être rejoué, mais un deuxième passage de `011` sur une même base n'a pas été observé.
- **Les gardes** de `011` (mauvaise base, mode SQLCMD désactivé) et de `012` (mauvaise base, procédures absentes) n'ont jamais été déclenchées.
- **`TraceabilityDev`** : seule la présence des 3 procédures de `011` y a été vue. Aucun test n'y a été lancé, et aucune mesure n'a été faite avec un grand nombre de fermes ou de stations (200 et 30 dans cette base).
- **Cas non testés** : une taille de page `NULL` ; un numéro de page très grand (le `CAST` en `BIGINT` n'est pas éprouvé pour ces deux listes) ; des pages successives d'une taille intermédiaire sans trou ni doublon pour `ListFarms` et `ListStations` ; une station avec les 4 fonctions ; `GetStation` avec un code d'une autre casse ; `ListBatches` avec les deux filtres combinés, avec un statut ou une ferme sans aucun lot, ou avec une page au-delà de la fin (avec le total).
- **La lecture en deux requêtes sans verrou** : le cas où une ligne est ajoutée entre la page et le total, ou entre la station et ses fonctions, n'a pas été essayé.
- **Le contenu des tests à l'œil** (6 dans `012`, 4 dans `006`) n'est pas contrôlé par le script, seulement le nombre et la forme des tableaux. Le test 30 de `006` (`GetBatch`) n'a pas été revu à l'œil lors du passage du 2026-10-20 : la procédure n'a pas changé.
- **Le coût du total de `ListBatches`** : une seule mesure, plan non examiné, aucune optimisation essayée (voir [mesures.md](mesures.md), sections 4.3 et 5).
  - Note du 2026-10-27, ajoutée après coup : traité au lot 5 : preuves en section 13, mesures dans [mesures.md](mesures.md) (sections 6 à 9.6), décision dans l'[ADR 0008](adr/0008-listbatches-page-avant-jointure-total-recompile.md).

### 8.4 Rejouer la vérification

- Prérequis : `TraceabilityTest` avec `001`, `002`, `004` et `005` (voir le README), puis `011` (mode SQLCMD actif, nom de la base réglé par `:setvar DbName`).
- Exécuter `006_check_procedures.sql` (résumé attendu `38 / 34 / 4`), puis `012_check_list_procedures.sql` (résumé attendu `16 / 10 / 6`), chacun dans une nouvelle fenêtre SSMS.
- Les tests à l'œil : avant chacun des tests 32, 33 et 38 de `006` et des tests de contenu de `012`, le script affiche dans la grille une ligne « Test N » qui dit ce qu'il faut voir, puis les tableaux de la procédure. Les tableaux s'empilent dans l'onglet Résultats : agrandir le volet et faire défiler.
- Pour la mesure : `009_measure_searches.sql` sur `TraceabilityDev` (1 000 000 de lots), plan d'exécution réel actif (Ctrl+M), puis copier le contenu de l'onglet Messages.
- Si SSMS affiche des erreurs rouges « Impossible de trouver la procédure stockée » alors que les procédures existent, actualiser le cache de l'IntelliSense (Ctrl+Maj+R) : le compteur d'erreurs est retombé à 0, observé aux lots 2a et 3a.

## 9. Lot 3b : API pour les fermes et les stations

Observé le 2026-10-20 sous Windows 11, avec le SDK .NET 10.0.402 (exécution 10.0.13), SQL Server 2025 (instance locale 17.0) et xUnit 2.9.3. Les tests d'intégration tournent sur la base `TraceabilityTest`. Les essais à la main (section 9.2), en lecture seule, ont été faits sur `TraceabilityDev`. Les routes sont décrites dans le [README](../README.md), les erreurs des procédures dans [procedures.md](procedures.md). Les données de test sont inventées.

Découpage de l'API : le lot 3 a été coupé une seconde fois, par ressource. Les fermes et les stations forment le lot 3b (cette section), les lots forment le lot 3c (section 10).

### 9.1 Ce qui a été construit

| Projet | Rôle |
|---|---|
| `src/Traceability.Data` | `TraceabilityDb` : appelle les 6 procédures des fermes et des stations en ADO.NET (voir [ADR 0005](adr/0005-ado-net-sans-dapper.md)). |
| `src/Traceability.Api` | 2 contrôleurs (6 routes), forme des codes, traduction des erreurs SQL en réponses HTTP, Swagger UI en développement. |
| `tests/Traceability.UnitTests` | 49 cas sans base (U1 à U8). |
| `tests/Traceability.IntegrationTests` | 30 cas sur `TraceabilityTest` : 25 par HTTP sur l'API lancée dans le test, 3 de garde-fous et de nettoyage (I1 à I3) et 2 sur `Data`. |

Les 30 cas d'intégration regroupent les 19 tests prévus au plan, 2 tests ajoutés (code de station mal formé, type de mouvement absent) et les lignes de données des tests à plusieurs cas (page invalide).

Paquets principaux : `Microsoft.Data.SqlClient` 7.1.1, `System.Security.Cryptography.Pkcs` 10.0.13 (version imposée, voir 9.2), `Swashbuckle.AspNetCore.SwaggerUI` 10.3.1, `Microsoft.AspNetCore.OpenApi` 10.0.13, `Microsoft.AspNetCore.Mvc.Testing` 10.0.13.

### 9.2 Ce qui est prouvé

- **Compilation** : `dotnet build Traceability.slnx` réussit pour les 4 projets, sans avertissement.
- **Avertissements de sécurité** : l'installation de `Microsoft.Data.SqlClient` 7.1.1 a affiché NU1902 (gravité moyenne) et NU1903 (gravité élevée). Ils visent `System.Security.Cryptography.Pkcs` 9.0.18, tiré par SqlClient : deux avis Microsoft du 2026-10-13, de type déni de service, corrigés en 9.0.21 et en 10.0.13. Avec la version 10.0.13 imposée dans `Traceability.Data`, les avertissements ont disparu (observé). On ne sait pas si SqlClient appelle les fonctions concernées.
- **HTTPS** : le certificat de développement a été approuvé (`dotnet dev-certs https --trust`, fenêtre de confirmation acceptée). L'API, lancée avec `dotnet run --project src/Traceability.Api --launch-profile https`, répond sur `https://localhost:7080` sans avertissement de certificat dans le navigateur.
- **Navigateur** : `dotnet run` n'a pas ouvert le navigateur, malgré `launchBrowser: true` dans le profil. La documentation de `dotnet run` indique qu'il garde cette valeur sans ouvrir de navigateur : c'est `dotnet watch` ou Visual Studio qui l'utilisent.
- **Connexion depuis .NET** (fichier jetable hors dépôt, lisant `ConnectionStrings__Default`) : sans `TrustServerCertificate`, `SqlException` numéro -2146893019, « la chaîne de certificats a été fournie par une autorité qui n'est pas approuvée » (ce numéro vient de Windows, pas de SQL Server) ; avec `TrustServerCertificate=True`, « Connexion OK, base : TraceabilityDev ».
- **Essais à la main sur `TraceabilityDev`, en lecture seule** :
  - `GET /farms` : 200, 20 fermes de `F001` à `F020`, `totalCount` 200, `pageNumber` 1, `pageSize` 20 (navigateur, puis « Try it out » de Swagger UI).
  - `GET /stations/ZZ-UNKNOWN` : 404, `application/problem+json`, `errorCode` 50102, `detail` « Station 'ZZ-UNKNOWN' was not found. » (`curl`).
  - `GET /farms?pageNumber=abc` : 400 par ASP.NET Core, avec `errors.pageNumber`.
  - `GET /stations/AB%20CD` : 400 par l'API. Au premier essai, le corps n'avait ni `type` ni `traceId`, contrairement aux autres erreurs ; après correction (les erreurs de forme passent par le `ModelState` du contrôleur), le corps a `type`, `title`, `status`, `errors` et `traceId`.
  - `GET /stations/SITE-01` (Swagger UI) : 200, `name` « Reception and sorting site 01 », `capabilities` `["RECEPTION", "SORTING"]` : les deux tableaux de `GetStation` forment un seul objet, les fonctions sont en majuscules et dans l'ordre du cycle de vie.
  - Swagger UI liste les 6 routes et 8 schémas.
- **Tests unitaires** : 49 cas réussis, 0 échec. U1 : les 16 numéros d'erreur des procédures, par famille (404, 409, 422, 400). U2 : un numéro inconnu donne 500 sans le texte SQL. U3 et U4 : l'unicité (2627) selon le nom de la contrainte, et une contrainte inconnue donne 500. U5 : `NOT NULL` (515) donne 400. U6 : la forme des codes. U7 : les champs absents. U8 : la page par défaut, lue par réflexion sur les contrôleurs.
- **Tests d'intégration** : 30 cas réussis, 0 échec.
  - Garde-fous : l'API de test se connecte à `TraceabilityTest` alors que `ConnectionStrings__Default` pointait vers `TraceabilityDev` (I1) ; le contrôle refuse la base `master` (I2, par un `SELECT`, aucun `DELETE` envoyé) ; le nettoyage vide les 5 tables, y compris des lignes insérées exprès (I3).
  - Numéros d'erreur lus dans `SqlException.Number` et arrivés jusqu'au client par HTTP : 50102, 50200, 50201, 50203, 50400, 50402 et 50404.
  - Les deux erreurs SQL que l'API et les procédures évitent d'habitude, provoquées exprès : un `INSERT` direct en double donne l'erreur 2627 avec `UQ_Farm_Code` dans le message, et la traduction du vrai message donne 409 et 50200 ; `CreateFarm` appelée avec un nom `NULL` donne l'erreur 515, traduite en 400.
  - Fermes : création 201 sans identifiant technique ni `Location` ; liste dans l'ordre de création avec `totalCount` et page 1 de 20 par défaut ; page invalide (0, -1, taille 0, taille 1001) : 400 et 50404 ; page au-delà de la fin : 200, aucune ligne, même `totalCount`.
  - Stations : création 201 avec `Location` finissant par `/stations/{code}` ; fonction ajoutée : 201, corps vide, `Location` ; type de mouvement en minuscules accepté et relu en majuscules ; fonctions relues en `RECEPTION`, `SORTING`, `PACKING` quel que soit l'ordre d'ajout ; station neuve : liste vide ; liste et pages invalides (page 0, taille 1001).
  - Erreurs de forme (400, sans `errorCode`) : champs obligatoires absents, nombre illisible dans l'adresse, code de station mal formé, `movementType` absent.
- **Un test peut échouer** : la ligne de `SqlErrorTranslator.cs` qui traduit la famille 502xx a été changée de 409 à 400 (modification non commitée). Résultat : 4 échecs unitaires (U1, numéros 50200 à 50203) et 3 échecs d'intégration (F2, S2 et S4, « Expected: Conflict, Actual: BadRequest »), 45 et 27 cas réussis. La ligne a été rétablie : l'empreinte SHA-256 du fichier est identique à l'originale, puis les 79 cas (49 + 30) réussissent.

### 9.3 Ce qui n'est pas prouvé

- **Les routes des lots** (lot 3c) : les erreurs 50100, 50101, 50300 à 50303, 50401 et 50403 n'ont jamais traversé l'API. La règle « 503xx donne 422 » n'est testée qu'en unitaire.
  - Note du 2026-10-27, ajoutée après coup : traité au lot 3c, section 10.2.
- **Deux requêtes qui créent le même code au même moment** : l'erreur 2627 n'est prouvée que par un `INSERT` direct, car les procédures vérifient le code avant d'insérer.
- **L'erreur 500** : elle n'est testée qu'en unitaire (U2). Aucune panne SQL n'a traversé l'API, et l'écriture de la vraie erreur dans le journal du serveur n'a pas été observée.
- **Longueurs** : un code trop long est refusé par l'API (testé en unitaire), mais pas par un test HTTP. La longueur du nom et de la région (100) n'est contrôlée ni par l'API ni par un test : le comportement avec un texte plus long n'est pas observé.
- **Cas non testés par HTTP** : une page au-delà de la fin pour les stations ; les tailles de page 1 et 1 000 ; la casse des codes.
- **Swagger UI** : il ne documente ni les erreurs possibles ni des descriptions des routes (prévu au lot 3c), et affiche « integer | string ($int32) » comme type de `pageNumber` et `pageSize`, sans que la cause ait été cherchée.
  - Note du 2026-10-27, ajoutée après coup : documenté au lot 3c (section 10.2) ; ce qui reste ouvert est en 10.3.
- **CORS** : non configuré, aucun frontend n'a été essayé.
  - Note du 2026-10-27, ajoutée après coup : réglé au lot 4a (politique CORS en 11.1, tests en 11.2, interface essayée dans Edge) ; `POST` ajouté au lot 4b (section 12). Voir l'[ADR 0007](adr/0007-cors-dans-l-api.md).
- **En-tête `Location`** : seul son suffixe `/stations/{code}` est testé, pas sa forme complète (absolue ou relative).
- **Configuration** : la chaîne de connexion est lue à la première utilisation. Si `ConnectionStrings__Default` manque, l'erreur n'apparaît qu'à la première requête qui touche la base : non essayé.
- **Vitesse et charge** : rien n'est mesuré côté API, ni pour `ListFarms` et `ListStations` sur un grand volume.
- **Système** : .NET 10 sur Windows 11 22H2, version qui n'est pas dans la liste officielle de .NET 10 ; seul ce qui a été observé ce jour est prouvé.
- **Les tests** : ils n'ont été vus échouer que pour un seul défaut (la famille 502xx). Un test peut ne pas détecter un autre défaut.
- **Deux garde-fous n'ont jamais été déclenchés** : celui que le lot SQL de nettoyage répète lui-même (erreur 50099, avant tout `DELETE`), et le refus de démarrer de la fixture quand l'API de test ne pointe pas vers `TraceabilityTest`. Seul le contrôle `SELECT DB_NAME()` du code C# est testé contre une autre base (I2, sur `master`).
- **`TraceabilityTest` a été vidée** par le nettoyage des tests d'intégration : les lignes de `006` (`ZZ-…`) et de `012` (`ZY-…`) n'y sont plus. Il faut relancer `006` et `012` pour les retrouver (non fait).

### 9.4 Rejouer la vérification

- Prérequis : le README, section « API (lot 3b) » (certificat, variables d'environnement, deux bases).
- `dotnet build Traceability.slnx`, puis `dotnet test Traceability.slnx` : résumé attendu `total : 79; échec : 0; réussi : 79`. **Attention** : les tests d'intégration exécutent 5 `DELETE` sans `WHERE` sur `TraceabilityTest` (jamais sur `TraceabilityDev`).
- Essais à la main, avec l'API lancée (`dotnet run --project src/Traceability.Api --launch-profile https`), dans une autre fenêtre PowerShell :

  ```powershell
  curl.exe -i --ssl-no-revoke https://localhost:7080/stations/ZZ-UNKNOWN
  curl.exe -i --ssl-no-revoke "https://localhost:7080/farms?pageNumber=abc"
  curl.exe -i --ssl-no-revoke "https://localhost:7080/stations/AB%20CD"
  ```

  Résultats observés : 404 avec `errorCode` 50102, puis deux 400 avec un champ `errors` et sans `errorCode`.
- Pour voir un test échouer : dans `src/Traceability.Api/Errors/SqlErrorTranslator.cs`, passer le 409 de la famille 502xx à 400, lancer `dotnet test Traceability.slnx` (au lot 3b : 4 échecs unitaires et 3 d'intégration ; au 2026-10-26 : 4 et 5, voir 14.12), puis rétablir la ligne.

## 10. Lot 3c : API pour les lots

Observé le 2026-10-21 sous Windows 11, avec le SDK .NET 10.0.402 (exécution 10.0.13), SQL Server 2025 (instance locale 17.0) et xUnit 2.9.3. Les tests d'intégration tournent sur la base `TraceabilityTest`. Les routes sont décrites dans le [README](../README.md), les erreurs des procédures dans [procedures.md](procedures.md). Les données de test sont inventées. La machine est réglée sur UTC.

### 10.1 Ce qui a été construit

| Projet | Ce qui a changé |
|---|---|
| `src/Traceability.Data` | 4 méthodes ajoutées à `TraceabilityDb` (`CreateBatchAsync`, `AddMovementAsync`, `GetBatchAsync`, `ListBatchesAsync`) et 3 types de résultat. La classe appelle maintenant les 10 procédures (309 lignes). |
| `src/Traceability.Api` | `BatchesController` (4 routes) ; vérifications de forme dans `FieldErrors` (`RequireValue<T>`, `RequireUtcTime`, `RequireText`, `RequireQuantity`) ; `FieldLimits` (tailles des colonnes) ; `[ProducesResponseType]` et commentaires XML sur les 10 routes. |
| `tests/Traceability.UnitTests` | 74 cas sans base : les 49 du lot 3b et 25 sur `FieldErrors`. |
| `tests/Traceability.IntegrationTests` | 80 cas sur `TraceabilityTest` : 75 par HTTP, 3 de garde-fous (I1 à I3) et 2 sur `Data`. 50 sont nouveaux : `BatchesTests` (30), `BodyFormatTests` (13), `FarmsTests` (2) et `StationsTests` (5). |

Décisions et écarts par rapport au plan :

- **Formats JSON** : la date de récolte s'écrit `"2026-10-14"` (`DateOnly`) ; la quantité est un nombre (`decimal`, précision 10 et échelle 2 fixées sur le paramètre SqlClient) ; l'heure est toujours explicitement en UTC (`Z` ou décalage), sinon 400.
- **Date envoyée comme `DateTime`** : `TraceabilityDb` envoie la date à SqlClient comme un `DateTime` à minuit avec le type `Date`. L'envoi direct d'un `DateOnly` n'a pas été vérifié.
- **Heure marquée UTC à la lecture, dans `Data`** (`ReadMovement`), et non dans l'API comme le plan le disait : un seul endroit pour tous les appelants.
- **Tailles des colonnes (non prévu)** : `FieldLimits`, `RequireText` et `RequireQuantity` ont été ajoutés après que des tests d'observation ont montré des valeurs coupées, arrondies ou refusées par SqlClient (voir 10.2). Décidé : on corrige dans ce lot. Le type de mouvement et le filtre de statut (20 caractères) sont protégés de la même façon.
- **Swagger** : `[ProducesResponseType]` plus commentaires XML. `GenerateDocumentationFile` est activé et l'avertissement `CS1591` (membre public sans commentaire) est silencié dans `Traceability.Api.csproj` : les routes et les corps de requête sont documentés, pas chaque classe interne. Les 9 avertissements `CS1573` du premier build ont été corrigés par des balises `<param>`.
- **Tests ajoutés au plan** : tests sur `RequireValue<T>`, `RequireUtcTime`, `RequireText` et `RequireQuantity`, les limites, les corps vides, le type de mouvement et le statut trop longs, la casse des codes, et 4 erreurs de procédures (50102 à la création et à l'ajout, 50400, 50402) qui n'étaient pas dans la liste B1 à B11.

### 10.2 Ce qui est prouvé

- **Compilation** : `dotnet build Traceability.slnx` réussit pour les 4 projets, avec 0 avertissement.
- **Tests** : 154 cas réussis, 0 échec (74 unitaires et 80 d'intégration), à la dernière exécution, après le rétablissement de tous les défauts posés pour la casse volontaire.
- **Cycle de vie par HTTP** : un lot est créé (201, corps vide, `Location` finissant par `/batches/{code}`), reçoit trois mouvements, puis la lecture donne le statut `SHIPPED`, la quantité 470, quatre mouvements dans l'ordre `RECEPTION`, `SORTING`, `PACKING`, `SHIPMENT`, avec des `movementId` croissants et distincts, et aucun identifiant technique de lot.
- **Erreurs des procédures arrivées jusqu'au client par les routes des lots** : 50100 (404, lecture et ajout d'un mouvement), 50101 (404, création et filtre de la liste), 50102 (404, création et ajout), 50202 (409), 50300, 50301, 50302 (422), 50303 (422, création et ajout), 50400 (400), 50401 (400, création et ajout), 50402 (400, ajout), 50403 (400) et 50404 (400). Chaque test déclenche une seule erreur, d'après l'ordre des contrôles de [procedures.md](procedures.md).
- **Listes** : filtre par statut, par ferme et par les deux (comptes exacts sur une ferme créée par le test), statut seul (vérification relative), page 1 de 20 par défaut, page au-delà de la fin (200, aucun élément, le vrai total, la page et la taille rappelées).
- **Formats observés** :
  - `quantityKg` : `500.55` revient inchangé ; `500.5` revient avec deux décimales (`500.50`, lu dans le texte JSON) ; une quantité écrite comme texte (`"500"`) est acceptée (201).
  - `occurredAt` : une heure avec `Z` revient avec `Z` ; une heure avec décalage (`08:00:00+02:00`) revient `06:00:00Z` sur cette machine ; une heure sans `Z` ni décalage donne 400 sur `occurredAt`.
  - Une valeur illisible dans le corps (quantité `"abc"`, date `"not-a-date"`, date avec une heure, heure `"yesterday"`) donne 400 en `application/problem+json`, sans `errorCode`.
  - Un corps vide `{}` donne 400 et nomme les 7 champs (création d'un lot) ou les 4 champs (mouvement).
- **Défauts trouvés par les tests d'observation, puis corrigés** :

  | Valeur envoyée | Avant la correction (observé) |
  |---|---|
  | quantité `500.555` | 201, enregistrée `500.56` : arrondie en silence |
  | quantité `100000000` (9 chiffres avant la virgule) | 500 : SqlClient lève une `ArgumentException` (« Valeur du paramètre '100000000.00' hors limites ») avant d'envoyer la requête, ce n'est pas une `SqlException`. La réponse est un 500 générique sans texte interne, et l'erreur est écrite dans la console. |
  | variété de 51 caractères | 201, longueur enregistrée 50 : coupée en silence |
  | nom de ferme, région ou nom de station de 101 caractères | 201 : accepté (la longueur enregistrée n'a pas été relue) |

  Après la correction (`FieldLimits`, `RequireText`, `RequireQuantity`), ces 6 tests passent : 400 sur le champ concerné. Un type de mouvement et un statut de 21 caractères donnent aussi 400 ; leur comportement avant la correction n'a pas été observé.
- **Casse des codes** : une station et un lot sont lus avec leur code en minuscules (200, le code renvoyé reste celui stocké) ; un code de station qui ne diffère que par la casse est refusé (409, 50201).
- **Stations** : une page au-delà de la fin donne 200, aucun élément et le même `totalCount`.
- **Swagger UI** (regardé dans Edge, avec l'API lancée sur `TraceabilityDev`, sans cliquer sur « Execute ») : les 10 routes s'affichent avec leur résumé, sous 3 titres (Batches 4, Farms 2, Stations 4) ; `POST /batches` montre ses 5 réponses (201, 400, 404, 409, 422) avec nos descriptions et les `errorCode`, et le schéma `CreateBatchRequest` affiche la description de chaque champ ; `GET /batches` montre le texte `remarks`, les 4 paramètres avec leur description et les valeurs par défaut 1 et 20.
- **Casse volontaire** (un défaut posé, `dotnet test`, puis ligne rétablie ; l'empreinte SHA-256 du fichier est ensuite identique à l'originale) :

  | Défaut posé | Échecs attendus | Échecs observés |
  |---|---|---|
  | `RequireQuantity` : décimales arrondies à 7 au lieu de 2 | 3 (1 unitaire, 2 d'intégration) | 3, ceux annoncés |
  | heure lue en base non marquée UTC | 2 | 2 |
  | filtres de statut et de ferme échangés dans `GET /batches` | 4 | 4 |
  | heure sans indication non refusée | 2 | 2 |
  | heure avec décalage non convertie en UTC | 1 si le fuseau de la machine n'est pas UTC | 0 : non détecté |

### 10.3 Ce qui n'est pas prouvé

- **Swagger UI** : pour 8 routes sur 10, seul le résumé a été vu, pas leurs réponses. L'exemple d'erreur n'affiche ni `errorCode` ni `errors` (champs ajoutés par l'API), et le type affiché est `application/json` alors que les vraies réponses sont en `application/problem+json`. Les champs obligatoires s'affichent aussi avec « null » comme type possible. `pageNumber` et `pageSize` s'affichent « integer | string ($int32) » : l'hypothèse est la même cause que pour `quantityKg` (un nombre écrit comme texte est accepté), non vérifiée.
- **Heure avec décalage** : sur cette machine (UTC), le test réussit même sans la conversion en UTC. Elle n'est donc pas prouvée, et son effet sur un serveur dans un autre fuseau n'est pas observé.
- **Casse volontaire** : seulement 5 défauts. Un test peut ne pas détecter un autre défaut.
- **Requêtes simultanées par HTTP** : deux créations du même code de lot, ou deux mouvements sur le même lot (verrou de l'ADR 0003, observé seulement au lot 2a).
- **Valeurs aux limites** : un texte de 100, 50 ou 20 caractères et la quantité `99999999.99` ne sont vérifiés qu'en unitaire, pas par HTTP et base. Les accents et les caractères hors du plan de base ne sont pas essayés : la longueur compte des unités UTF-16, comme SQL Server pour `NVARCHAR`, mais ce n'est pas observé ici.
- **Autres formats** : une quantité négative par HTTP, une heure avec des fractions de seconde, un champ `null` explicite.
- **En-tête `Location`** : seul son suffixe est testé, pas sa forme complète.
- **Vitesse** : `GET /batches` n'a pas été essayée sur `TraceabilityDev` (1 000 000 de lots) et le coût du total n'a pas été remesuré par l'API (voir [mesures.md](mesures.md), section 4.3).
  - Note du 2026-10-27, ajoutée après coup : au lot 5, la dernière page a été appelée 10 fois par l'API, de 0,45 à 1,59 s (section 13.2) ; le coût du total a été mesuré dans SSMS ([mesures.md](mesures.md), sections 9.4 et 9.6).
- **Données** : `TraceabilityDev` a été relue au début de la session (200 fermes, 30 stations, 40 fonctions, 1 000 000 de lots, 3 250 000 mouvements) et n'a pas été recomptée à la fin ; rien n'y a été écrit volontairement. `TraceabilityTest` était vide au début de la session et est vidée par les tests.
- **Reportés de la section 9.3** : CORS non configuré et aucun frontend ; chaîne de connexion lue à la première utilisation ; .NET 10 sur Windows 11 22H2 ; les deux garde-fous des tests jamais déclenchés (50099 et refus de démarrer de la fixture) ; aucune mesure de charge côté API.
  - Note du 2026-10-27, ajoutée après coup : CORS et interface : réglés au lot 4a (section 11).

### 10.4 Rejouer la vérification

- Prérequis : le README, section « API (lots 3b et 3c) ».
- `dotnet build Traceability.slnx`, puis `dotnet test Traceability.slnx` : résumé attendu `total : 154; échec : 0; réussi : 154`. **Attention** : les tests d'intégration exécutent 5 `DELETE` sans `WHERE` sur `TraceabilityTest` (jamais sur `TraceabilityDev`).
- Swagger UI : `dotnet run --project src/Traceability.Api --launch-profile https`, puis `https://localhost:7080/swagger`. L'API lit `TraceabilityDev` : ne pas cliquer sur « Execute » pour les routes `POST` (elles écriraient dans la base) ni pour `GET /batches` (le total est lent sur un million de lots).
- Pour voir un test échouer : dans `src/Traceability.Api/Validation/FieldErrors.cs`, remplacer `FieldLimits.QuantityDecimals))` par `FieldLimits.QuantityDecimals + 5))` dans `RequireQuantity`, lancer `dotnet test Traceability.slnx` (3 échecs : 1 unitaire et 2 d'intégration), puis rétablir la ligne.

## 11. Lot 4a : interface web de lecture (React)

Observé le 2026-10-21 sous Windows 11, dans Edge, avec Node v22.16.0 et npm 10.9.2, le SDK .NET 10 et SQL Server 2025 (instance locale). Pour les observations dans Edge, l'API tournait sur `TraceabilityDev` ; les tests d'intégration C# tournent sur `TraceabilityTest`. Les choix d'outils sont dans l'[ADR 0006](adr/0006-interface-web-vite-react.md), le CORS dans l'[ADR 0007](adr/0007-cors-dans-l-api.md).

### 11.1 Ce qui a été construit

| Où | Ce qui a changé |
|---|---|
| `src/Traceability.Api` | `Program.cs` : une politique CORS `WebUi`, en développement seulement (origine `http://localhost:5173`, méthode `GET`). |
| `tests/Traceability.IntegrationTests` | `CorsTests` : 5 tests par HTTP. Les tests C# passent à 159 : 74 unitaires et 85 d'intégration. |
| `web/src/api` | `types.ts` (types des réponses), `errors.ts` (`ApiError`, `NetworkError`), `client.ts` (une fonction par route de lecture : 5 `GET`). |
| `web/src/lib` | `format.ts` (heure en UTC, date, quantité, calculées sur le texte, sans objet `Date`), `labels.ts` (statuts et types de mouvement en français), `messages.ts` (erreur de l'API en message français, selon `errorCode`), `page.ts` (page lue dans l'adresse), `useApi.ts` (états chargement, erreur, réussite ; annulation d'un appel remplacé). |
| `web/src/components` | mise en page et navigation, liste générique avec sa pagination (Début, Précédent, Suivant, Fin), tableau, fiche de détail, pastille de statut, messages de chargement, d'erreur et de liste vide, fond d'écran. |
| `web/src/pages` | 5 écrans (fermes, stations, détail d'une station, lots avec filtres, détail d'un lot) et la page « introuvable ». |
| `web/` | 13 fichiers de test, 79 tests. |

Décisions et écarts par rapport au plan :

- **Lot 4 coupé en deux** : le 4a lit, le 4b écrira.
- **Taille de page** : le plan disait 20 lignes. Après avoir vu l'écran, elle est passée à 10 (pour tenir sur un écran sans défiler), puis à 15 avec des lignes moins hautes. C'est une constante de `web/src/config.ts` ; l'API garde 20 par défaut.
- **Heures** : affichées en UTC avec la mention « UTC », jamais converties en heure locale.
- **Petits écrans** : sous 640 pixels de large, les colonnes Ferme et Variété de la liste des lots sont cachées pour éviter le défilement de côté.
- **Non prévus au plan, décidés pendant le lot, après avoir vu la page** : les boutons « Début » et « Fin », un thème de couleurs chaudes défini à un seul endroit (`web/src/index.css`), et un fond d'écran de dessins (fruits, légumes, caisses, cartons) tracés en SVG.
- **Filtres** : le statut et la ferme de la liste des lots sont dans l'adresse (`?status=…&farmCode=…&page=…`) ; appliquer un filtre revient à la page 1.
- **ADR 0007 ajouté** : le CORS n'était pas prévu comme décision à part.

### 11.2 Ce qui est prouvé

- **Qualité du code** (dernière exécution, après le rétablissement de tous les défauts de la casse volontaire) : `npm run lint` donne 0 avertissement et 0 erreur (116 règles, 49 fichiers) ; `npm run build` réussit (JavaScript 280,81 ko, CSS 14,15 ko). Les noms des fichiers construits sont les mêmes qu'avant la casse : le code compilé est identique.
- **Tests de l'interface** : 79 réussis, 0 échec, 13 fichiers (`client` 11, `format` 7, `messages` 10, `page` 10, `labels` 4, `useApi` 5, `Pagination` 2, `FarmsPage` 8, `StationsPage` 2, `StationPage` 4, `BatchesPage` 8, `BatchPage` 5, `App` 3). `fetch` y est remplacé par un faux : ces tests ne prouvent rien de l'API réelle.
- **Tests C#** : 159 réussis, 0 échec (74 unitaires et 85 d'intégration).
- **CORS, par HTTP** : l'origine `http://localhost:5173` reçoit `Access-Control-Allow-Origin` ; une autre origine non ; une requête sans origine non ; une erreur 404 écrite par le gestionnaire d'exceptions garde l'en-tête ; une pré-vérification pour `POST` reçoit `Access-Control-Allow-Methods: GET`. Observé aussi : cette réponse contient l'origine alors que la méthode demandée n'est pas permise, ce que la page de Microsoft lue pendant le lot disait ne pas arriver. Deux hypothèses de Claude fondées sur cette page ont été corrigées par l'observation avant d'arriver au test final.
- **Observé dans Edge, sur les vraies données de `TraceabilityDev`** :
  - Fermes : 200 fermes, 15 par page, « Page 1 sur 14 · 200 au total ». À 10 lignes par page (avant le changement), « Fin » arrivait à la page 20 sur 20, `F191` à `F200`.
  - Stations : 30 stations, 2 pages. Page 1 : `SITE-01` à `SITE-10` puis `PCK-01` à `PCK-05`. Page 2 (`?page=2`) : `PCK-06` à `PCK-10` puis `SHP-01` à `SHP-10`, avec « Suivant » et « Fin » grisés.
  - Lots : « Page 1 sur 66 667 · 1 000 000 au total », 15 lignes, 6 colonnes sur un grand écran, une pastille de statut. « Fin » : la page 66 667 affiche 10 lots, de `LOT-0999991` à `LOT-1000000`, au statut « Reçu ».
  - Détail du lot `LOT-0000001` : ferme `F001`, variété `roma`, 20/10/2024, 176,66 kg, « Expédié » ; le parcours a 4 étapes (Réception à `SITE-02` 06:13:00, Tri à `SITE-02` 08:30:00, Emballage à `PCK-01` 10:49:00, Expédition à `SHP-01` 13:12:00, toutes « UTC »), avec des quantités qui diminuent (179,19 ; 178,64 ; 177,79 ; 176,66 kg).
  - Détail de la station `SITE-02` : son nom (`Reception and sorting site 02`, en anglais : c'est la donnée de la base) et deux fonctions, Réception et Tri.
  - Navigation : les liens vont de la liste au détail et du parcours d'un lot à une station ; le lien de retour revient à la liste. La page est dans l'adresse (`?page=3`) : F5 reste sur la même page, et la flèche « retour » du navigateur revient à la page précédente.
  - Erreurs à l'écran : un lot inexistant donne « Lot introuvable. » sans ligne « Référence » ; `?farmCode=F999` donne « Ferme introuvable. » (le champ garde `F999`, « Effacer les filtres » apparaît) ; l'API arrêtée donne « Impossible de joindre l'API. Est-elle lancée ? », et la console dit `net::ERR_CONNECTION_REFUSED` (pas de blocage CORS) ; une erreur 500 de l'API donne « Erreur inattendue du serveur. » avec sa « Référence ».
  - Mode « mobile » des outils de développement (468 pixels) : la liste des lots garde 4 colonnes (Code, Récolte, Quantité, Statut), les codes tiennent sur une ligne, sans défilement de côté ; le détail d'un lot tient, dates comprises ; la pagination se range sur trois lignes.
  - Durées lues dans l'onglet « Réseau » : la page 1000 des lots (14 985 lots sautés) a pris 371 ms puis 388 ms ; le premier appel après le redémarrage de l'API, 2,70 s ; « Fin » des lots (999 990 lots sautés) : 8,88 s, 11,73 s, 9,72 s et 1,90 s selon l'essai (statut 200), et trois échecs (statut 500), dont un mesuré à 30,15 s (voir 11.3).
  - Appel annulé : l'onglet « Réseau » montre, avant la vraie requête, une ligne rouge sans réponse (0 octet, 6 à 9 ms). C'est l'effet du mode strict de React en développement (`<StrictMode>` dans `main.tsx`) et de l'annulation par `useApi`.
- **Durée de `trace.ListBatches` dans SSMS** (lecture seule, pages de 15, une exécution par ligne, durée écoulée de la procédure entière, page et total ensemble) : page 1000, 335 ms ; page 10 000, 662 ms ; page 30 000, 1 274 ms ; page 66 667, 2 744 ms. La durée croît avec le nombre de lignes sautées.
- **Journal de l'API** (deux erreurs lues dans le terminal) : un dépassement de délai SQL (`Unexpected SQL error (number -2)`, « Le délai d'exécution a expiré ») dans `ListBatchesAsync`, au moment de « Fin » (deux erreurs de ce type lues dans le terminal, avec deux identifiants de connexion différents) ; et un appel annulé (`Unexpected SQL error (number 0)`, « Opération annulée par l'utilisateur ») dans `ListFarmsAsync`.
- **Casse volontaire** (défauts posés, tests lancés, fichiers rétablis ; l'empreinte SHA-256 de chaque fichier est ensuite identique à l'originale) :

  | Défaut posé | Échecs annoncés | Échecs observés |
  |---|---|---|
  | D1 : `formatUtc` n'écrit plus « UTC » | `format` 2, `BatchPage` 1 | `format` **3**, `BatchPage` 1 (le test des fractions de seconde écrit aussi « UTC » : compte faux) |
  | D2 : messages des erreurs 50100 et 50102 échangés | `messages` 2 | 2 (les deux tests de pages sur ces cas échouaient aussi, mais masqués par D3) |
  | D3 : le client ne lève plus d'erreur pour un statut d'erreur | `client` 4, plusieurs tests de pages | `client` **3**, plus 5 tests de pages en échec et 5 plantages `Cannot read properties of undefined (reading 'length')`. Voir plus bas. |
  | D4 : « Précédent » au-delà de la fin va à la page n-1 | `FarmsPage` 1 | 1 (« Page 8 sur 3 ») |
  | D5 : `useApi` n'ignore plus la réponse lente d'un appel remplacé | `useApi` 1 | 1 |
  | D6 : `readPageNumber` accepte 0 | `page` 1 cas | 1 |
  | D7 : les filtres vides ne sont plus omis de l'adresse | `client` 2, `BatchesPage` 2, `App` 1 | 5, ceux annoncés |
  | D8 (API) : origine CORS `http://localhost:5174` | 4 tests CORS sur 5 | 4 sur 5 : le test « sans origine » réussit même sans CORS |

  Avec D1 à D7 posés : 22 tests en échec sur 79, dans 10 des 13 fichiers (les 3 autres, par déduction : `labels`, `StationsPage` et `Pagination`).
  - **Un test trop faible trouvé** : avec D3, le test « erreur inattendue (500) » réussissait à tort, parce que le corps de la réponse simulée contenait déjà `status` et `traceId`, les deux champs vérifiés. Il vérifie maintenant aussi `toBeInstanceOf(ApiError)`, comme le test de l'erreur de forme. Rejoué avec D3 seul : 4 échecs et 7 réussis dans `client.test`.
  - **Un programme compilé périmé** : après D8 rétabli par copie, 4 tests CORS échouaient encore (« Actual: http://localhost:5174 »), alors que `Program.cs` avait l'empreinte d'origine. La construction de l'API avait duré 12,1 s avec le défaut, puis 1,6 s sans rien recompiler : la copie avait gardé l'ancienne date du fichier, et `dotnet` ne recompile que si une source est plus récente que le programme. Après mise à jour de la date : construction de 3,8 s et 159 tests réussis. Le contenu des fichiers n'avait pas changé.

### 11.3 Ce qui n'est pas prouvé

- **« Fin » de la liste des lots.** Sur 7 essais le même soir : 3 échecs (500, dépassement de délai SQL, numéro -2 dans le journal de l'API ; un mesuré à 30,15 s) et 4 réussites (8,88 s, 11,73 s, 9,72 s, 1,90 s). Dans SSMS, la même page prend 2,2 à 2,7 s. Pendant la réussite de 9,72 s, une lecture de `sys.dm_exec_requests` toutes les 2 secondes a montré la requête de l'API sans blocage ni attente (`wait_type` vide), avec sa mémoire accordée aussitôt (95 296 Ko), un plan parallèle à 4 fils et `cpu_ms` passant de 3 044 à 12 631 en 8 s, soit environ 14 fois les 0,9 s de processeur mesurés dans SSMS pour la même page. **La cause n'est pas trouvée.** Les pistes (plan d'exécution gardé en mémoire, données pas en mémoire, processeur pris par autre chose) ne sont ni confirmées ni écartées ; une lecture de `sys.dm_exec_procedure_stats` n'a renvoyé aucune ligne. Notre code ne fixe aucun délai d'attente (`CommandTimeout`) et la chaîne de connexion du README n'en contient pas : c'est donc la valeur par défaut du pilote, 30 secondes selon la [documentation de Microsoft](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlcommand.commandtimeout) (page lue le 2026-10-21, qui précise que seules les anciennes méthodes asynchrones comme `BeginExecuteReader` l'ignorent) ; l'échec mesuré à 30,15 s est cohérent avec elle. Le cas R5 de [mesures.md](mesures.md) avait annoncé la limite de la pagination par `OFFSET`. À traiter au lot 5, avec des mesures répétées plutôt qu'un seul essai.
- **Appels annulés** : l'API écrit un appel annulé par le navigateur comme une erreur grave dans son journal. Le lien avec l'annulation faite par l'interface (et le mode strict de React) est déduit du message et de l'onglet « Réseau », pas prouvé ; rien n'a été changé.
- **Filtres de la liste des lots sur les vraies données** (statut, ferme, sur le million de lots) : non essayés dans Edge, durée inconnue. Ils ne sont testés qu'avec un faux serveur.
- **Autres navigateurs, vrai téléphone** : seul Edge a été utilisé, et le mode « mobile » de ses outils (468 pixels). Les fermes, les stations et le détail d'une station n'ont pas été regardés à cette largeur.
- **Accessibilité** : lecteur d'écran et contrastes non vérifiés. **Apparence** : couleurs et dessins ne sont pas testés automatiquement ; ils ont été regardés dans Edge.
- **Écriture** : aucune dans ce lot. Le CORS n'accepte que `GET` ; une pré-vérification pour `POST` n'a été testée que par C#, pas par un navigateur. Les en-têtes que la page peut lire (par exemple `Location`, renvoyé par les routes `POST`) ne sont pas vérifiés.
- **Fuseau** : les heures sont affichées en UTC, jamais en heure locale (volontaire) ; l'effet d'un autre fuseau n'est pas observé.
- **Casse volontaire** : 8 défauts seulement. Un test peut ne pas voir un autre défaut.
- **Rechargement de Vite** : pendant un remaniement de `BatchesPage.tsx` écrit en deux fois, la console d'Edge a montré « Failed to reload » et une erreur 500 de Vite ; la cause supposée est la lecture d'un état intermédiaire du fichier, non prouvée. Le lint, le build et les 79 tests passent sur le fichier final.
- **Données** : `TraceabilityDev` a été relue au début de la session (200 fermes, 30 stations, 40 fonctions, 1 000 000 de lots, 3 250 000 mouvements) et n'a pas été recomptée à la fin ; l'interface ne fait que lire. `TraceabilityTest` contenait des restes de tests au début (26 fermes, 27 stations, 36 fonctions, 20 lots, 28 mouvements) ; les tests d'intégration la vident.
- **React Router 8.5.0** : non essayée (elle demande Node 22.22.0 ou plus).
- **Reportés de la section 10.3**, toujours ouverts : l'exemple d'erreur de Swagger UI, les requêtes simultanées par HTTP, les valeurs aux limites par HTTP et base, l'en-tête `Location`, et la chaîne de connexion lue à la première utilisation.

### 11.4 Rejouer la vérification

- Prérequis : le README, sections « API (lots 3b et 3c) » et « Interface web (lot 4a) ».
- Qualité et tests de l'interface, dans `web/` : `npm install` (une fois), puis `npm run lint`, `npm run build` et `npm test` : attendu 0 avertissement, build réussi, `Tests  79 passed (79)`.
- Tests C#, à la racine, **API arrêtée** : `dotnet test Traceability.slnx` : attendu `total : 159; échec : 0; réussi : 159`. **Attention** : les tests d'intégration exécutent 5 `DELETE` sans `WHERE` sur `TraceabilityTest` (jamais sur `TraceabilityDev`).
- Voir l'interface : dans un terminal, `dotnet run --project src/Traceability.Api --launch-profile https` ; dans un autre, `cd web` puis `npm run dev` ; ouvrir `http://localhost:5173/`. L'interface du lot 4a ne fait que lire, mais la liste des lots calcule le total à chaque page : « Fin » a duré de 1,9 s à plus de 30 s (échec) selon l'essai (voir 11.3).
- Pour voir un test échouer : dans `web/src/lib/format.ts`, retirer ` UTC` de la chaîne renvoyée par `formatUtc`, lancer `npm test` (3 échecs dans `format.test` et 1 dans `BatchPage.test`), puis rétablir la ligne. **Après avoir remis un fichier par copie**, mettre à jour sa date (`(Get-Item chemin).LastWriteTime = Get-Date` dans PowerShell), sinon `dotnet` peut ne pas recompiler (voir 11.2) ; un fichier remis par l'éditeur est déjà à la bonne date.

## 12. Lot 4b : interface web d'écriture (formulaires)

Observé le 2026-10-22 sous Windows 11, dans Edge, avec Node v22.23.4 et npm 10.9.9, le SDK .NET 10 et SQL Server 2025 (instance locale). Pour les observations dans Edge, l'API tournait sur `TraceabilityTest` (la variable `ConnectionStrings__Default` était changée dans le terminal de l'API), jamais sur `TraceabilityDev`. Les tests d'intégration C# vident `TraceabilityTest` : les données de l'essai (codes `ZV-…`) n'y sont plus. Le CORS est dans l'[ADR 0007](adr/0007-cors-dans-l-api.md).

### 12.1 Ce qui a été construit

| Où | Ce qui a changé |
|---|---|
| `src/Traceability.Api` | `Program.cs` : la politique CORS `WebUi` accepte `GET` et `POST` et l'en-tête `Content-Type` (origine `http://localhost:5173`, développement seulement). |
| `tests/` | `CorsTests` passe de 5 à 8 tests (pré-vérification de `POST`, `PUT` et `DELETE` non listés, `POST` en 201, `POST` refusé en 400 avec l'en-tête). `FieldErrorsTests` : un test fige les textes anglais des erreurs de forme que l'interface traduit. Tests C# : 163 (75 unitaires, 88 d'intégration). |
| `web/src/api` | `client.ts` : les appels d'écriture (`POST` sur fermes, stations, lots, fonctions et mouvements) ; `types.ts` : `MOVEMENT_TYPES`. |
| `web/src/lib` | `messages.ts` (erreurs d'écriture en français, selon `errorCode` ou le champ de l'erreur de forme), `useSubmit.ts` (état « envoi », garde contre le double envoi), `utc.ts` (heure du formulaire et texte UTC), `nextStep.ts` (étape proposée selon le statut), `useApi.ts` (paramètre `refresh` : relire après une écriture sans écran de chargement). |
| `web/src/components` | `Field`, `FormAlert`, `SuccessMessage`, `AddCapabilityForm`, `AddMovementForm`. |
| `web/src/pages` | `NewFarmPage`, `NewStationPage`, `NewBatchPage` (adresses `/new-farm`, `/new-station`, `/new-batch`) ; formulaire d'ajout de fonction sur la page d'une station et d'ajout de mouvement sur la page d'un lot. |
| `web/` | 22 fichiers de test, 178 tests. |

Décisions et écarts par rapport au plan :

- **Formulaires non contrôlés** : les valeurs sont lues avec `FormData` au moment de l'envoi, sans état par champ.
- **Un seul envoi à la fois** : pendant un envoi, le bouton est désactivé et un second envoi est ignoré (garde dans `useSubmit`).
- **Pas de nouvel essai automatique** : si l'API ne répond pas, l'écriture a peut-être eu lieu ; le message le dit et demande de vérifier dans la liste.
- **Heures en UTC** : le champ date et heure est prérempli avec l'heure UTC du moment et envoyé avec un « Z » ; la réception d'un lot et chaque mouvement l'utilisent.
- **Le formulaire de mouvement redémarre après chaque ajout** (sa clé est le statut du lot : étape suivante, nouvelle quantité, nouvelle heure) ; son message de succès est donc gardé par la page du lot, pas par le formulaire.
- **Un défaut trouvé à l'essai dans Edge** : le message vert « Mouvement … ajouté. » restait affiché à côté du cadre rouge d'un envoi suivant refusé. Corrigé par un appel `onStart` du formulaire, qui efface le message dès qu'un nouvel envoi démarre (test écrit avant la correction). Rejoué dans Edge ensuite : plus de bandeau vert.

### 12.2 Ce qui est prouvé

- **Qualité du code** : `npm run lint` donne 0 avertissement et 0 erreur (116 règles, 69 fichiers) ; `npm run build` réussit (61 modules, JavaScript 293,21 ko, CSS 14,55 ko).
- **Tests de l'interface** : 178 réussis, 0 échec, 22 fichiers (`client` 21, `format` 7, `messages` 37, `page` 10, `labels` 4, `useApi` 8, `useSubmit` 5, `nextStep` 4, `utc` 6, `Pagination` 2, `FormAlert` 3, `SuccessMessage` 1, `Field` 2, `FarmsPage` 8, `StationsPage` 2, `StationPage` 10, `BatchesPage` 8, `BatchPage` 15, `App` 3, `NewFarmPage` 7, `NewStationPage` 7, `NewBatchPage` 8). `fetch` y est remplacé par un faux : ces tests ne prouvent rien de l'API réelle.
- **Tests C#** : 163 réussis, 0 échec (75 unitaires, 88 d'intégration).
- **Observé dans Edge, API sur `TraceabilityTest`** (onglet « Réseau » en filtre « All » : les pré-vérifications, de type `preflight`, sont cachées par le filtre « Fetch/XHR ») :
  - Création d'une ferme : `OPTIONS` 204, puis `POST` 201 ; message « Ferme ZV-FARM créée. » avec un lien, formulaire vidé.
  - Même code redonné : `POST` 409 ; cadre rouge « Une ferme porte déjà ce code. » ; les valeurs restent dans le formulaire.
  - Code avec une espace : `POST` 400 ; cadre « Certains champs sont invalides. » ; sous Code, « Lettres A-Z sans accent, chiffres, « - » et « _ » seulement, 20 caractères au plus. » ; rien sous Nom et Région.
  - Station : `POST` 201, puis la page de la station s'ouvre (« Aucune fonction déclarée. »). Ajout d'une fonction : `POST` 201, message vert, la fonction apparaît dans la fiche après une relecture, sans écran de chargement. Même fonction une seconde fois : `POST` 409, « Cette station a déjà cette fonction. », pas de relecture.
  - Lot `ZV-S5-LOT` : `POST` 201, la page du lot s'ouvre : statut « Reçu », 100,00 kg, un mouvement de réception. Le formulaire propose « Tri » et la quantité actuelle.
  - Mouvements, règles de la procédure (réponses **422**, erreurs 5030x) : Tri sur une station sans la fonction, « Cette station n'a pas la fonction de ce mouvement. » ; Expédition alors que l'étape suivante est l'emballage, « Ce mouvement n'est pas l'étape suivante du lot. » ; quantité 101 pour un lot de 100 kg, « La quantité dépasse la quantité actuelle du lot. ». Dans ces trois cas : pas de relecture, saisie gardée, statut inchangé.
  - Mouvements réussis (**201**, puis une relecture du lot) : Tri 100 kg, « Trié », le formulaire propose « Emballage » et 100 ; Emballage 95 kg, « Emballé », 95,00 kg, le formulaire propose « Expédition » ; Expédition 95 kg, « Expédié », parcours de 4 lignes, le formulaire est remplacé par « Ce lot est expédié : aucun mouvement n'est plus possible. » (le message vert reste affiché).
  - Touche Entrée dans un champ : le formulaire est envoyé, une seule requête part.
  - API arrêtée : cadre rouge « Pas de réponse de l'API : l'enregistrement a peut-être eu lieu. Vérifiez dans la liste avant de recommencer. » ; la saisie reste ; l'onglet « Réseau » montre la pré-vérification et la requête en rouge, sans statut ; la console dit `POST https://localhost:7080/farms net::ERR_CONNECTION_REFUSED`, sans message CORS. Après le redémarrage de l'API, la ferme n'est pas dans la liste (28 fermes).
  - Double clic : avec la limitation « 3G » des outils de développement, le bouton affiche « Envoi… » et reste désactivé ; un seul `POST` (201, 2,08 s) ; la liste passe à 29 fermes. Un clic fait après la création, sur le formulaire vidé, est arrêté par le navigateur (« Veuillez remplir ce champ. », champ obligatoire) sans aucune requête.
  - Requêtes annulées : chaque ouverture de page montre, avant la vraie lecture, une ligne rouge sans statut (0 octet, quelques millisecondes) : l'effet du mode strict de React en développement et de l'annulation par `useApi`, comme au lot 4a.
  - Rejeu après la correction du défaut, sur un nouveau lot : Tri valide (message vert), puis Expédition refusée en 422 : le cadre rouge est seul, le bandeau vert a disparu, le statut reste « Trié ».
- **Casse volontaire** (défauts posés, tests lancés, fichiers rétablis par copie ; l'empreinte SHA-256 de chaque fichier est ensuite identique à l'originale et `git status` indique « working tree clean ») :

  | Défaut posé | Échecs observés |
  |---|---|
  | D1 : `onStart()` retiré (`AddMovementForm.tsx`) | 1 : le test du message de succès qui doit disparaître (`BatchPage`) ; 14 autres réussis dans le fichier |
  | D2 : garde du double envoi retirée (`useSubmit.ts`) | 1 : « ignores a second send while the first one is running » (`useSubmit`) ; 177 réussis. Les 5 tests de pages « clicked twice » réussissent : le bouton désactivé suffit à les satisfaire, et seul le test de `useSubmit` voit la garde |
  | D3 : l'étape suivante d'un lot reçu est l'emballage au lieu du tri (`nextStep.ts`) | 5 dans 2 fichiers : `nextStep` 1, `BatchPage` 4 ; 173 réussis |
  | D4 : `refresh` retiré des dépendances de l'effet (`useApi.ts`) | 6 dans 3 fichiers : `useApi` 3, `BatchPage` 2, `StationPage` 1 ; 172 réussis ; plus une « Unhandled Rejection » (une promesse rejetée que le code cassé n'attend jamais) |
  | D5 (API) : « characters. » changé en « chars. » dans le texte de l'erreur de code (`FieldErrors.cs`) | 1 test unitaire : celui qui fige les textes lus par l'interface ; 74 réussis sur 75 |
  | D6 (API) : `POST` retiré de la politique CORS (`Program.cs`) | 1 test d'intégration : la pré-vérification pour `POST` (`Allow-Methods` ne contient que `GET`) ; 7 réussis sur 8, dont le `POST` réel : l'API ne contrôle pas la méthode d'une vraie requête, c'est le navigateur qui bloque |

### 12.3 Ce qui n'est pas prouvé

- **La garde `useRef` de `useSubmit`** : non observée seule dans Edge, parce que le bouton désactivé bloque déjà le second clic ; elle n'est vue que par son test unitaire.
- **Erreurs de liaison JSON** (par exemple une date invalide) : l'interface ne permet pas de les produire ; elles ne sont vues que par les tests C#.
- **Build de production** : non essayé dans le navigateur ; l'absence de requêtes annulées sans le mode strict de React est déduite, pas observée.
- **Autres navigateurs, vrai téléphone, lecteur d'écran** : seul Edge a été utilisé. Les formulaires ont été essayés dans le mode adaptatif des outils de développement (largeurs de 345 à 433 pixels), pas sur un vrai téléphone.
- **Écriture simultanée** : deux utilisateurs qui ajoutent un mouvement au même lot en même temps ne sont pas essayés (le verrou est prouvé en SQL, section 6).
- **En-tête `Location`** : l'interface ne le lit pas ; elle ouvre la page du lot ou de la station avec le code saisi. Il n'est pas vérifié dans un navigateur.
- **« Fin » de la liste des lots** : lent, parfois en erreur (section 11.3) ; non revu, c'est l'objet du lot 5.
  - Note du 2026-10-27, ajoutée après coup : traité au lot 5, section 13.2 ; ce qui reste non prouvé est en 13.3.
- **Durée des tests de l'interface** : la suite a pris de 28 s à 143 s selon les exécutions, sans cause identifiée ; un test de `StationsPage` a dépassé une fois 5 s pendant une exécution lente, cause non prouvée.
- **Journal de l'API** : il écrit toujours un appel annulé comme une erreur grave (observé au lot 4a) ; rien n'a été changé.
- **Casse volontaire** : 6 défauts seulement. Un test peut ne pas voir un autre défaut.
- **React Router 8.5.0** : désormais permise par la version de Node (22.23.4, la version demandée est 22.22.0 ou plus), mais non essayée.
- **Données** : `TraceabilityDev` n'a pas été touchée ni recomptée ; `TraceabilityTest` a été vidée par les tests d'intégration après l'essai.

### 12.4 Rejouer la vérification

- Prérequis : le README, sections « API (lots 3b et 3c) » et « Interface web ».
- Qualité et tests de l'interface, dans `web/` : `npm install` (une fois), puis `npm run lint`, `npm run build` et `npm test` : attendu 0 avertissement, build réussi (61 modules), `Test Files  22 passed (22)` et `Tests  178 passed (178)`.
- Tests C#, à la racine, **API arrêtée** : `dotnet test Traceability.slnx` : attendu `total : 163; échec : 0; réussi : 163`. **Attention** : les tests d'intégration vident `TraceabilityTest` (jamais `TraceabilityDev`).
- Essayer l'écriture sans toucher à `TraceabilityDev` : dans le terminal de l'API, mettre `$env:ConnectionStrings__Default` sur la chaîne de `TraceabilityTest`, puis `dotnet run --project src/Traceability.Api --launch-profile https` ; dans un autre terminal, `cd web` puis `npm run dev` ; ouvrir `http://localhost:5173/`. La variable ne vit que dans cette fenêtre de terminal.
- Pour voir un test échouer : dans `web/src/lib/nextStep.ts`, remplacer `RECEIVED: 'SORTING'` par `RECEIVED: 'PACKING'`, lancer `npm test` (5 échecs : 1 dans `nextStep`, 4 dans `BatchPage`), puis rétablir la ligne. **Après avoir remis un fichier par copie**, mettre à jour sa date (`(Get-Item chemin).LastWriteTime = Get-Date` dans PowerShell), sinon `dotnet` peut ne pas recompiler (voir 11.2).

## 13. Lot 5 : optimisation de la liste des lots

Observé le 2026-10-23 sous Windows 11, avec le SDK .NET 10, SQL Server 2025 (instance locale) et SSMS, sur une machine d'environ 8 Go de mémoire. Les mesures sont faites sur `TraceabilityDev` (1 000 000 de lots inventés), les tests sur `TraceabilityTest`. Les mesures, leurs hypothèses écrites avant et leurs résultats sont dans [mesures.md](mesures.md) (sections 6 à 9.6) ; la décision est dans l'[ADR 0008](adr/0008-listbatches-page-avant-jointure-total-recompile.md).

### 13.1 Ce qui a été construit

| Script | Rôle |
|---|---|
| `013_measure_lot5.sql` | Mesure le total et la dernière page de `ListBatches` (lectures logiques, plans, 5 exécutions). Lecture seule. Vise `TraceabilityDev`. |
| `014_measure_lot5_trials.sql` | Essais G1 (sans parallélisme) et G2 (page découpée avant la jointure). Lecture seule : son seul `INSERT` écrit dans des variables de type table. |
| `015_measure_lot5_t2.sql` | Mesures de l'essai d'index pour le total : 4 totaux, 5 exécutions, taille des index. Lecture seule. |
| `016_measure_lot5_costs.sql` | Coûts de l'index et du plan refait à chaque appel. **Le bloc W1 écrit dans la base** : 5 séries de 500 appels de `CreateBatch`, chacune annulée ; les autres blocs sont en lecture seule. |
| `017_optimize_list_batches.sql` | Crée `IX_Batch_FarmId` s'il n'existe pas et remplace `ListBatches` : page découpée avant la jointure, total avec `OPTION (RECOMPILE)`. Rejouable ; mode SQLCMD ; à lancer sur `TraceabilityDev` et sur `TraceabilityTest`. |

Décisions et écarts par rapport au plan :

- **Hypothèses écrites avant leur mesure** : chacune a son commit, avant celui des mesures. Quelques-unes ont été ajoutées après des résultats (G1, M1, les coûts C1 à C3, D1, G2, T3) : le document le dit en toutes lettres pour chacune.
- **L'ordre prévu** (G1, puis F1, puis T2) a changé : M1 a été ajoutée après F1, G2 après G1, et la mesure C2 a été refaite (C2b) après le diagnostic D1.
- **Le contrat de `ListBatches` n'a pas changé** : mêmes paramètres, mêmes erreurs (50403, 50101, 50404), deux résultats dans le même ordre (la page, puis le total). L'API C# et l'interface web ne sont pas modifiées.

### 13.2 Ce qui est prouvé

- **Tests C#** : 163 réussis, 0 échec (75 unitaires, 88 d'intégration), sur `TraceabilityTest` avec la nouvelle `ListBatches` (`017` lancé à 18:24).
- **`006`** sur `TraceabilityTest` : `38 / 34 / 4` comme avant. Les tests 32, 33 et 38 de `ListBatches`, vérifiés à l'œil, sont conformes : statut `SORTED` (4 lignes, total 4), ferme `ZZ-F02` (2 lignes, total 2), pages de `ZZ-F03` (`ZZ-P1` et `ZZ-P2`, puis `ZZ-P3` et `ZZ-P4`, puis `ZZ-P5`, total de 5 après chaque page).
- **Mêmes lignes, même ordre** : l'ancienne requête de la page et la nouvelle renvoient les mêmes 70 lignes sur 6 cas (page 1, dernière page, statut, ferme, statut et ferme, page vide).
- **Les deux bases ont la même structure** : `017` lancé sur `TraceabilityTest` (18:24:50) et sur `TraceabilityDev` (18:40:13), trois index sur `Batch` dans les deux, `ListBatches` modifiée.
- **Mesures dans SSMS sur `TraceabilityDev`** (lectures logiques de `Batch` ; page de 15 lignes) :

  | Mesure | Avant | Après |
  |---|---|---|
  | Total sans filtre | 10 574 | 1 737 |
  | Total, ferme `F001` (25 000 lots) | 10 574 | 47 |
  | Total, ferme `F021` (2 777 lots) | 10 574 | 8 |
  | Total, statut `RECEIVED` | 10 574 | 10 574 (inchangé) |
  | Dernière page (66 667) : `Batch` / `Farm` / zone de travail | 10 574 / 2 / environ 10 530 | 10 424 / 20 / aucune |
  | Dernière page : plan | parallèle, tri d'un million de lignes | lecture de `PK_Batch` dans l'ordre, aucun tri |
  | Dernière page : 5 exécutions de l'appel entier | de 7,9 s à 146 s | de 277 à 298 ms |
  | Page 1 : `Batch` / `Farm` | 3 / 30 | 3 à 4 / 30 |

- **Par l'API** : 10 appels de suite de la dernière page, tous réussis, de 0,45 à 1,59 s (moyenne 0,65 s), avec un budget de mémoire des requêtes de 5 Mo avant et après la série. Avant le lot 5 : de 1,9 à 11,7 s quand l'appel réussissait (section 11.3), et 3 échecs sur 3 après environ 30 s au début de la séance du 2026-10-23 (erreur SQL -2, délai).
- **Coûts mesurés** : `IX_Batch_FarmId` pèse 1 737 pages (13,57 Mo) ; `CreateBatch` passe de 0,16 à 0,28 ms par appel et de 632 à 750 octets de journal (500 appels par série, 5 séries, dans SSMS) ; refaire le plan du total coûte environ 4 ms par appel (mesure C2b, 100 appels par tour, 5 tours, deux lancements).
- **Observations sur la mémoire** : pendant un échec de « Fin » par l'API, la requête attendait sa mémoire (`RESOURCE_SEMAPHORE`, 0 Ko accordé, depuis 9,7 s). Dans SSMS, une requête a attendu environ 15 minutes quand le budget de mémoire des requêtes était de 5 Mo, puis a repris une minute après l'arrêt d'Edge (budget de 5 à 1 017 Mo).
- **Observation hors protocole du soir du 2026-10-23** (une seule, sans essai témoin ; [mesures.md](mesures.md), section 9.7) : avec un budget de mémoire des requêtes de 5 Mo, l'ancienne requête de la dernière page a attendu sa mémoire pendant 118 s (0 Ko accordé), alors que la nouvelle procédure répondait à l'interface en 443 ms (« Début ») et 684 ms (« Fin »). Dans l'interface, « Fin » affiche la dernière page (66 667 sur 66 667, `LOT-1000000` en dernier) en 717, 769 et 684 ms.
- **Hypothèses contredites ou non confirmées** (elles sont écrites telles quelles dans [mesures.md](mesures.md)) :

  | Hypothèse | Verdict |
  |---|---|
  | T2 : un index sur `Batch (FarmId)` accélère le total (essai sur `F001`) | contredite : le plan commun de la procédure ne l'utilisait pas (10 574 lectures) |
  | F1 : l'ordre des appels explique les échecs de l'API | contredite (4 appels sur la dernière page : 3 échecs, 1 réussite à 10,6 s) |
  | F2 : lectures de `Farm` de l'ordre de 2 000 000 | en partie contredite (2 lectures) ; le tri d'un million de lignes et le déversement sont conformes |
  | G1 : sans parallélisme, plus de tri | fausse (le tri reste ; la page est 4,7 à 5,9 fois plus rapide) |
  | M1 : à 25 s d'un échec, la requête attend encore sa mémoire | ni confirmée ni infirmée (aucun échec en 6 appels) |
  | C1 : l'index coûte moins de 25 % à l'écriture | fausse pour la durée (+74 %), conforme pour le journal (+19 %) |
  | C2 : le plan refait coûte moins de 10 ms | mesure initiale non valable (mauvais plan, voir D1) ; confirmée par C2b |
  | D1 : les deux écritures du total lisent 47 pages | fausse telle qu'énoncée (la forme avec une variable lisait toute la table) |

### 13.3 Ce qui n'est pas prouvé

- **La correction des échecs de « Fin » par l'API** : ils ne se reproduisaient pas à volonté (3 échecs sur 3 au début de la séance, puis 7 réussites avant tout changement). Les 10 appels réussis après `017` sont cohérents avec une correction mais ne la prouvent pas, et l'ancienne version n'a pas été remesurée dans le même état de mémoire.
  - Note du 2026-10-27, ajoutée après coup : l'ancienne version a été remesurée le 2026-10-23 au soir avec un budget de mémoire de 5 Mo : elle a attendu sa mémoire pendant 118 s, pendant que la nouvelle répondait en moins d'une seconde (une seule observation, sans essai témoin ; [mesures.md](mesures.md), section 9.7). La correction des échecs d'origine reste non prouvée.
- **La cause des échecs** : une attente de mémoire est plausible (vue pendant un échec, à 9,7 s ; pas lue jusqu'à la coupure à 30 s), et la mémoire de la machine l'est aussi (une seule observation, sans essai témoin : l'arrêt d'Edge a coïncidé avec un budget qui passe de 5 à 1 017 Mo).
- **La demande de mémoire du nouveau plan** : non lue. On suppose qu'elle est petite faute de tri.
- **Le coût en écriture** : mesuré seulement par `CreateBatch` dans SSMS, deux mesures séparées de 27 minutes et non alternées ; pas dans l'application, pas sous charge.
- **Le filtre par statut** : pas amélioré (10 574 lectures pour le total, 9 351 pour la page 1 de `RECEIVED`) ; aucun index sur `Status` n'a été essayé.
- **La dernière page lit toujours toute la table** (10 424 pages) : la pagination par `OFFSET` reste linéaire ; la pagination par clé n'est pas essayée.
- **Autres écritures du total et de la page** : les variantes par branches `IF` et le SQL dynamique ne sont pas mesurés ; les coûts avec filtre ne sont mesurés que pour la page 1 (les lignes des pages avec filtre ont été comparées, pas leur coût).
- **L'interface web** n'a pas été essayée dans le navigateur avec la nouvelle procédure (le bouton « Fin » n'a été exercé que par l'API).
  - Note du 2026-10-27, ajoutée après coup : essayée dans Edge le 2026-10-23 au soir, hors protocole : « Fin » affiche la dernière page en 717, 769 et 684 ms (statut 200) ; voir [mesures.md](mesures.md), section 9.7.
- **Une seule machine** (environ 8 Go, plus de 90 % de mémoire utilisée pendant la séance), des données inventées, et des durées qui varient selon l'état de la machine : les lectures de pages sont la mesure de référence.

### 13.4 Rejouer la vérification

- Prérequis : le README, section « Base de données » ; les scripts `001` à `005`, `011` et `017` lancés sur les deux bases, et le million de lots sur `TraceabilityDev`.
- Appliquer `017` (mode SQLCMD, `:setvar DbName` sur `TraceabilityTest` puis sur `TraceabilityDev`, API arrêtée) : attendu `Index IX_Batch_FarmId created.` (ou `already exists`), trois index sur `Batch`, `ListBatches` avec la date du jour.
- `006` sur `TraceabilityTest` : attendu `38 / 34 / 4` ; vérifier à l'œil les tests 32, 33 et 38 à partir de leur « attendu ».
- Tests C#, à la racine, **API arrêtée** : `dotnet test Traceability.slnx` : attendu `total : 163; échec : 0; réussi : 163`. **Attention** : les tests d'intégration vident `TraceabilityTest` (jamais `TraceabilityDev`).
- Mesures sur `TraceabilityDev` : dans `013`, lancer d'abord le bloc de contrôles du début, puis les blocs A1, A2 et A3 (plan réel actif) et B1 et B2 (plan désactivé) : attendu un total sans filtre à 1 737 lectures, 47 pour `F001`, 8 pour `F021`, 10 574 pour `RECEIVED`, et la dernière page à 10 424 lectures de `Batch`, sans zone de travail.
- Par l'API (lancée sur `TraceabilityDev`) : la boucle de 10 appels de [mesures.md](mesures.md), section 9.6 : attendu 10 réponses `OK`, de l'ordre de 0,5 s.
- Revenir en arrière : relancer la partie `ListBatches` de `005`, puis supprimer l'index `IX_Batch_FarmId` de `trace.Batch`.

## 14. Lot 6 : intégration continue

Statut : **Terminé** (2026-10-26). Seul ce que liste 14.7 est prouvé ; ce qui ne l'est pas est en 14.8. Les hypothèses sont en 14.1 et 14.11, écrites avant les lancements ; les résultats sont en 14.2 à 14.6, 14.10 et 14.12 ; pour rejouer, voir 14.9.

### 14.1 Hypothèses écrites avant le premier lancement

Écrites le 2026-10-26, avant tout lancement de la CI. Aucune n'a été essayée.

La CI prévue est un fichier de workflow GitHub Actions avec deux tâches :

- `backend` (Linux) : un conteneur SQL Server 2025 en authentification SQL, la base `TraceabilityTest` construite par les scripts `001`, `002`, `004`, `005`, `011` et `017` (sur des copies temporaires où la ligne `:setvar DbName` est remplacée), puis `dotnet build` et `dotnet test Traceability.slnx` ;
- `frontend` : Node 22, `npm ci`, puis lint, build et tests dans `web/`.

| N° | Prédiction | Fausse si… |
|---|---|---|
| C1 | Le conteneur SQL Server 2025 démarre et accepte une connexion en authentification SQL avec le secret, en moins de 60 s. | La tâche expire sans première connexion réussie. |
| C2 | `sqlcmd` est disponible sur le runner sans installation. | « command not found » à la première utilisation. |
| C3 | Les scripts `001`, `002`, `004`, `005`, `011` et `017` s'exécutent sans erreur sur une base vierge, avec la ligne `:setvar` remplacée dans une copie temporaire. | Un script renvoie une erreur, ou la base créée n'est pas `TraceabilityTest`. |
| C4 | `dotnet test Traceability.slnx` donne `total : 163; échec : 0; réussi : 163` (75 unitaires, 88 d'intégration). | Le total diffère de 163, ou un test échoue. |
| C5 | Côté interface : lint à 0 avertissement, build réussi, 178 tests réussis. | Un de ces trois résultats diffère. |
| C6 | La tâche `backend` dure moins de 10 minutes. | Elle dépasse 10 minutes. |

Remarques écrites avant le lancement :

- Les chiffres 163 (tests C#) et 178 (tests de l'interface) ont été observés le 2026-10-23 pour le premier et au lot 4b pour le second. Ils n'ont pas été remesurés aujourd'hui.
- L'image `mssql/server:2025-latest` n'est confirmée que par un listing tiers (releasealert.dev, étiquette datée du 2026-10-20), pas par le registre de Microsoft. Elle sera constatée au premier téléchargement : ce n'est pas une hypothèse.
- Une hypothèse fausse reste écrite telle quelle. Les résultats s'ajoutent à la suite, et une hypothèse ajoutée après un lancement le dit en toutes lettres.

### 14.2 Premier lancement

Exécution n° 1 de la CI, le 2026-10-26 vers 09:33 (heure locale = UTC), sur le commit `6cf5573`. Elle s'est déclenchée sur un push de la branche, avant la création de la pull request : le workflow se déclenche à chaque push et à chaque pull request. Runner : `ubuntu-24.04`, image `20261012.334.1`, Ubuntu 24.04.5 LTS.

Observé :

- Tâche `backend` : échec en 30 s à l'étape « Check that sqlcmd is available » : la commande `command -v sqlcmd` s'est terminée avec le code 1. Les étapes d'avant ont réussi : « Initialize containers » (16 s : l'image `mssql/server:2025-latest` a été téléchargée et le conteneur démarré), « Check out the repository » (1 s) et « Set up .NET » (8 s). Les étapes suivantes n'ont pas été exécutées. Aucune connexion au conteneur n'a été essayée.
- Tâche `frontend` : réussie en 22 s, toutes les étapes en vert (Install dependencies 3 s, Lint 0 s, Build 3 s, Test 8 s). Chiffres relevés ensuite dans le journal : lint (`oxlint`) « Found 0 warnings and 0 errors » sur 69 fichiers ; build réussi, 61 modules, JS 293,21 ko et CSS 14,55 ko (mêmes chiffres qu'au lot 4b) ; Vitest 5.0.5 : 22 fichiers réussis sur 22, 178 tests réussis sur 178. L'annotation (1 notice) n'a pas été lue.

Résultat des hypothèses de 14.1 :

| N° | Résultat | Observation |
|---|---|---|
| C1 | Non testée | Aucune connexion au conteneur n'a été essayée. |
| C2 | **Fausse** | `sqlcmd` est absent du runner : `command -v sqlcmd` a renvoyé le code 1. |
| C3 | Non testée | La tâche s'est arrêtée avant la construction de la base. |
| C4 | Non testée | La tâche s'est arrêtée avant `dotnet test`. |
| C5 | **Vraie** | Lint : 0 avertissement et 0 erreur ; build réussi ; 22 fichiers et 178 tests réussis sur 178. |
| C6 | Non mesurable | La tâche `backend` s'est arrêtée au bout de 30 s. |

Hypothèses **ajoutées après le premier lancement**, donc après avoir su que `sqlcmd` manque sur le runner. Elles portent sur des faits qu'aucun lancement n'a encore montrés :

| N° | Prédiction | Fausse si… |
|---|---|---|
| C7 | Le conteneur `mssql/server:2025-latest` ne contient pas `sqlcmd` dans `/opt/mssql-tools18/bin`. | Un exécutable `sqlcmd` y est listé. |
| C8 | Un paquet `sqlcmd` ou `mssql-tools18` est installable par `apt` sur le runner sans configurer de dépôt supplémentaire. | `apt-cache policy` n'en trouve aucun. |
| C9 | La dernière version de `go-sqlcmd` sur GitHub propose une archive Linux amd64 téléchargeable depuis le runner. | Aucun fichier de ce type n'est listé, ou la liste est inaccessible depuis le runner. |

La prochaine étape est une étape de diagnostic dans `ci.yml` qui affiche ces trois sources, sans rien installer.

### 14.3 Deuxième lancement : diagnostic de `sqlcmd`

Deuxième exécution de la CI, sur le commit `9da02bb`, lancée par le push de 09:59 (heure locale = UTC). Elle contenait une étape de diagnostic en lecture seule à la place de la vérification de `sqlcmd`.

Observé dans le journal du diagnostic :

1. Runner : `sqlcmd` est absent du `PATH`, et les dossiers `/opt/mssql-tools18/bin` et `/opt/mssql-tools/bin` n'existent pas.
2. Conteneur `mssql/server:2025-latest` (identifiant `4f7821024f64`) : `/opt/mssql-tools18/bin` contient `bcp` et `sqlcmd` (491 792 octets, daté du 27 août) ; `/opt/mssql-tools/bin` n'existe pas ; `command -v sqlcmd` n'a rien affiché, donc `sqlcmd` n'est pas dans le `PATH` du conteneur.
3. `apt` sur le runner : `mssql-tools18` a un candidat `18.7.1.1-1` (versions `18.6.2.1-1`, `18.6.1.1-1` et `18.4.1.1-1` aussi listées), dans `packages.microsoft.com/ubuntu/24.04/prod noble/main amd64` ; `mssql-tools` a un candidat `17.11.1.1-1` ; aucune ligne pour un paquet nommé `sqlcmd`. Aucun des deux n'est installé. Le fichier `/etc/apt/sources.list.d/microsoft-prod.list` mentionne `packages.microsoft.com`.
4. GitHub : la dernière version de `go-sqlcmd` est `v1.10.0`, avec une archive `sqlcmd-linux-amd64.tar.bz2` (et des fichiers pour Windows, macOS et d'autres architectures Linux). L'API GitHub est accessible depuis le runner.

L'étape suivante, « Wait for SQL Server (60 s at most) », a échoué après 1 min 0 s avec « SQL Server did not answer within 60 s ». Ce n'est pas un résultat sur C1 : `sqlcmd` étant absent du `PATH`, chaque tentative a échoué faute de commande, et l'étape redirige les messages d'erreur vers `/dev/null`, donc la cause n'apparaissait pas dans le journal. Cette étape devra afficher la dernière erreur quand elle échoue.

Résultat des hypothèses de 14.2 :

| N° | Résultat | Observation |
|---|---|---|
| C7 | **Fausse** | `/opt/mssql-tools18/bin/sqlcmd` existe dans le conteneur. |
| C8 | Non fausse | Un candidat `mssql-tools18` existe dans un dépôt déjà configuré sur le runner. L'installation elle-même n'a pas été essayée. |
| C9 | Non fausse | Une archive Linux amd64 est listée et la liste est accessible depuis le runner. Le téléchargement n'a pas été essayé. |

Toujours non testées : C1 (aucune connexion possible sans `sqlcmd`), C3, C4 et C6. C2 reste fausse.

Hypothèse **ajoutée après le deuxième lancement**, donc après avoir vu le diagnostic :

| N° | Prédiction | Fausse si… |
|---|---|---|
| C10 | `sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18` réussit sur le runner en moins de 90 s, et `/opt/mssql-tools18/bin/sqlcmd` existe ensuite. | `apt-get` renvoie une erreur, dépasse 90 s, ou le fichier est absent après l'installation. |

Le conteneur contient aussi `sqlcmd`, donc lancer les scripts depuis le conteneur reste possible. La prochaine étape prévue est l'installation de `mssql-tools18` sur le runner (C10), avec `/opt/mssql-tools18/bin` ajouté au `PATH` des étapes suivantes.

### 14.4 Troisième lancement : la CI complète

Exécution n° 3 de la CI, sur le commit `92da86f`, lancée par un push vers 10:09 le 2026-10-26 (heure locale = UTC). Statut : réussie, 1 min 6 s au total (`backend` 1 min 3 s, `frontend` 19 s). Runner : `ubuntu-24.04`, image `20261012.334.1`, Ubuntu 24.04.5 LTS, agent 2.338.0, comme pour la première exécution.

Observé, tâche `backend` :

- « Install sqlcmd (mssql-tools18) » : 15 s. `apt-get install` a installé 6 paquets (`libodbcinst2`, `msodbcsql18`, `mssql-tools18` 18.7.1.1-1, `odbcinst`, `unixodbc`, `unixodbc-common`), sans `apt-get update` préalable. `ls -l` montre `/opt/mssql-tools18/bin/sqlcmd` (491 792 octets).
- « Wait for SQL Server » : 0 s. Le message « SQL Server answered after about 2 s » correspond à la première tentative de la boucle (le calcul `i * 2` donne 2 pour `i = 1`) : le serveur a répondu dès le premier essai.
- « Build TraceabilityTest from the SQL scripts » : 1 s, sans erreur. `001` : `Database TraceabilityTest created.` (classement `SQL_Latin1_General_CP1_CI_AS`, récupération `SIMPLE`). `002` : schéma `trace` et 5 tables. `004` : 3 procédures. `005` : 7 procédures. `011` : 10 procédures. `017` : `Index IX_Batch_FarmId created.`, et `ListBatches` modifiée le 2026-10-26 à 10:09:35.
- « List what was created (read only) » : 10 procédures du schéma `trace` ; 3 index sur `trace.Batch` (`IX_Batch_FarmId`, `PK_Batch`, `UQ_Batch_BatchCode`).
- « Build » : 11 s, `Build succeeded`, 0 avertissement, 0 erreur (`Time Elapsed 00:00:11.24`).
- « Test » : 7 s. Tests unitaires : 75 réussis sur 75 (191 ms). Tests d'intégration : 88 réussis sur 88 (1 s). Total : 163 réussis, 0 échec. Le texte est en anglais sur le runner (`Passed! - Failed: 0, Passed: 75, …`), alors que C4 était écrite avec la formulation française : seuls les nombres comptent.

Observé, tâche `frontend` (19 s) : lint (`oxlint`) « Found 0 warnings and 0 errors » sur 69 fichiers ; build de 61 modules, JS 293,21 ko et CSS 14,55 ko (mêmes chiffres qu'au lot 4b) ; Vitest 5.0.5 : 22 fichiers réussis sur 22 et 178 tests réussis sur 178 (7,14 s). Le rapport de la page de l'exécution indique « 22 passes · 22 total » et « 178 passes · 178 total ».

Annotations : 2 notices, une par tâche, avec le même texte : « The ubuntu-latest label will migrate to Ubuntu 26 beginning October 19, 2026. For more information, see https://github.com/actions/runner-images/issues/14748 ». Les deux exécutions observées ont encore tourné sur Ubuntu 24.04.5 ; ce qui se passera après la migration n'a pas été observé.

Résultat des hypothèses :

| N° | Résultat | Observation |
|---|---|---|
| C1 | **Vraie** | Le serveur a répondu dès la première tentative de la boucle (étape de 0 s), en authentification SQL avec le secret. |
| C3 | **Vraie** | Les 6 scripts se sont exécutés sans erreur sur une base vierge, et la base créée est `TraceabilityTest`. |
| C4 | **Vraie** | 75 + 88 = 163 tests réussis, 0 échec. |
| C5 | **Vraie** | Déjà relevée en 14.2 ; mêmes chiffres dans cette exécution. |
| C6 | **Vraie** | La tâche `backend` a duré 1 min 3 s, pour une limite de 10 minutes. |
| C10 | **Vraie** | Installation en 15 s, pour une limite de 90 s ; `/opt/mssql-tools18/bin/sqlcmd` existe ensuite. |

Bilan des hypothèses du lot : C1, C3, C4, C5, C6 et C10 sont vraies ; C2 et C7 sont fausses ; C8 et C9 n'ont pas été fausses mais n'ont pas été essayées jusqu'au bout (C9 : le téléchargement de `go-sqlcmd` n'a pas été tenté, la solution retenue passe par `apt`).

### 14.5 Quatrième et cinquième lancements : runner fixé et versions

**Exécution n° 4**, commit `61ea27c`, lancée par un push le 2026-10-26 vers 10:25 (heure locale = UTC) : les deux tâches demandent maintenant `ubuntu-24.04` au lieu de `ubuntu-latest`. Statut : réussie, 1 min 12 s au total (`backend` 1 min 8 s, `frontend` 26 s).

- Runner, sur les deux tâches : Ubuntu 24.04.5 LTS, image `ubuntu-24.04` version `20261012.334.1`, agent 2.338.0. C'est la même image que pour les exécutions n° 1 et n° 3 : le journal montre que le runner fixé fonctionne, mais il n'a pas pu montrer de différence avec `ubuntu-latest`, qui désignait encore cette image. L'intérêt de la fixation ne se verra qu'après la migration annoncée.
- `backend`, étape Test (5 s) : 75 réussis sur 75 (120 ms) et 88 réussis sur 88 (1 s), soit 163 tests, 0 échec.
- `frontend`, étape Test (11 s) : 22 fichiers réussis sur 22, 178 tests réussis sur 178 (Vitest 9,99 s).
- Les annotations de cette exécution n'ont pas été relevées.

**Exécution n° 5**, commit `20e1cd87df7ad7e41dacd33a0b4d5e781a749ab4` (`20e1cd8`), lancée par un push le 2026-10-26 vers 10:35 (Vitest a démarré à 10:35:22). Elle ajoute des étapes qui affichent les versions des outils, sans changer ce qui est construit ni testé. Statut : réussie, 56 s au total (`backend` 53 s, `frontend` 25 s). Aucune annotation n'est affichée sur la page de l'exécution, alors que celle de l'exécution n° 3 en affichait deux, sur l'étiquette `ubuntu-latest`.

Versions relevées dans les journaux :

| Élément | Dans la CI (exécution n° 5) | Sur la machine de développement (README ; section 7 pour le moteur) |
|---|---|---|
| SDK .NET | 10.0.403 | 10.0.402 |
| `sqlcmd` | 18.7.0001.1 Linux (paquet `mssql-tools18` 18.7.1.1-1) | non relevé |
| Moteur SQL Server | 2025 (RTM-CU10), KB5125471, 17.0.5035.5, Enterprise Developer Edition sous Ubuntu 24.04.5 LTS, compilé le 2026-10-15 | 17.0.1145.4 |
| Image du conteneur | `mcr.microsoft.com/mssql/server@sha256:245f6b1c8903edae52cb20fa31419cefcde1a49938bb8c3447099011fc871ca3` (étiquette `2025-latest`) | sans objet |
| Node.js | v22.23.3 | 22.23.4 |
| npm | 10.9.9 | 10.9.9 |

Tests de l'exécution n° 5 : `backend` 75 réussis sur 75 (123 ms) et 88 réussis sur 88 (1 s), soit 163 tests, 0 échec ; `frontend` 22 fichiers réussis sur 22 et 178 tests réussis sur 178 (Vitest 12,44 s).

Le moteur de la CI est donc une version plus récente que celle de la machine de développement (17.0.5035.5 contre 17.0.1145.4) : les tests passent sur les deux. L'étiquette `2025-latest` se déplace avec le temps : le digest ci-dessus identifie l'image de cette exécution.

### 14.6 Sixième et septième exécutions : push de documentation et pull request

Écrit le 2026-10-26 après observation. Aucune hypothèse n'avait été écrite avant pour le déclenchement par pull request : ce qui suit est un constat, pas une hypothèse confirmée après coup. Statuts et durées des exécutions : page publique « Actions » du dépôt ; détail des étapes : journaux copiés du run n° 7.

**Exécution n° 6**, commit `7615535f7140884326366bb6948f4c1b2621fe09` (`7615535`), lancée par un push (modification de ce fichier seulement). Statut : réussie, 1 min 4 s. Le détail de ses étapes n'a pas été relevé.

**Exécution n° 7**, lancée par la pull request n° 12 « Add the continuous integration (lot 6) » : `feature/lot-6-ci` vers `main`, 10 commits, **en brouillon** au moment de l'exécution. Statut : réussie, 1 min 3 s. Le workflow n'a aucune condition sur l'état « brouillon » : il s'est donc exécuté sur une pull request en brouillon.

Commit testé par l'exécution n° 7 :

- Le journal de l'étape « Check out the repository » (tâche `backend`) récupère le commit `13f2078ff3156542fad0e60dab80cb32cfc9e581` (`13f2078`), avec `fetch --depth=1`, sous le nom `pull/12/merge` ; `git log -1 --format=%H` affiche le même hash.
- Relevé en local le 2026-10-26 vers 10:55 (`git fetch origin "refs/pull/12/merge"` puis `git log -1 --format="%H %P" FETCH_HEAD`) : `13f2078` a deux parents, `45e3f600cc509ce5fe89dd3cf91a1ed71c67f82c` et `7615535f7140884326366bb6948f4c1b2621fe09`.
- Relevé vers 10:57 (`git fetch origin main` puis `git rev-parse origin/main`) : la pointe de `main` est `45e3f600cc509ce5fe89dd3cf91a1ed71c67f82c`, le premier parent.
- Une pull request teste donc la fusion temporaire de la branche avec `main`, pas le dernier commit de la branche seul. Ce commit de fusion est calculé par GitHub ; il n'est pas dans l'historique de la branche.

Tests de l'exécution n° 7 :

- `backend`, étape Test : 75 réussis sur 75 (181 ms) et 88 réussis sur 88 (1 s), soit 163 tests, 0 échec.
- `frontend`, étape Test : 22 fichiers réussis sur 22, 178 tests réussis sur 178 (Vitest 10,14 s, démarré à 10:46:54). Vitest affiche un conseil (isolation : environ 4,80 s gagnées avec `isolate: false`) ; il n'est pas appliqué.
- Le journal montre `SQLCMDPASSWORD: ***` : le secret est masqué.
- Les annotations de cette exécution n'ont pas été relevées.

Durées des exécutions réussies (page « Actions ») : n° 3 1 min 6 s, n° 4 1 min 12 s, n° 5 56 s, n° 6 1 min 4 s, n° 7 1 min 3 s. Exécutions en échec : n° 1 (33 s) et n° 2 (1 min 34 s), voir 14.2 et 14.3.

Note du 2026-10-27, ajoutée après coup : la page du workflow « CI » (onglet Actions) liste aussi la n° 8 (push du commit `aed1519`, « Record the pull request run and the lot 6 proven and unproven points », réussie en 1 min 4 s) et la n° 9 (pull request n° 12, déclenchement `synchronize`, réussie en 1 min 18 s). Elles ne sont pas décrites plus haut. Les neuf exécutions citées par l'[ADR 0009](adr/0009-integration-continue-github-actions.md) sont donc les n° 1 à 9 : n° 1 et 2 en échec, n° 3 à 9 réussies.

### 14.7 Ce qui est prouvé

- **Déclenchement** : la CI se lance à chaque push de la branche (exécutions n° 1 à 6) et sur une pull request (n° 7), y compris en brouillon.
- **Commit testé en pull request** : la fusion de la branche avec `main` (`13f2078`, parents `45e3f60` et `7615535`).
- **Backend sous Linux** : un conteneur SQL Server 2025 en authentification SQL, la base `TraceabilityTest` construite par les scripts `001`, `002`, `004`, `005`, `011` et `017`, puis 163 tests réussis (75 unitaires et 88 d'intégration). Observé dans les journaux des exécutions n° 3, 4, 5 et 7. Le code C# n'a pas changé : la méthode d'authentification dépend seulement du contenu de la chaîne de connexion.
- **Frontend** : lint à 0 avertissement, build réussi et 178 tests réussis (22 fichiers) sous Node 22.
- **Durée** : de 56 s à 1 min 12 s pour les exécutions réussies, très en dessous des limites (20 min pour `backend`, 15 min pour `frontend`).
- **Secret** : `MSSQL_SA_PASSWORD` est lu depuis les secrets du dépôt et apparaît masqué (`***`) dans le journal de l'exécution n° 7.
- **Une CI peut être rouge** : les exécutions n° 1 et 2 ont échoué, pour une cause d'environnement (`sqlcmd` absent du runner), pas à cause d'un test.
- **Versions** : outils, moteur SQL Server et image du conteneur relevés au 14.5 (digest de l'image inclus).
- **Un test en échec rend la CI rouge, et la règle bloque la fusion** : observé le 2026-10-26 sur une branche jetable (14.12). La tâche `backend` est rouge à l'étape de test, `frontend` reste verte, et GitHub affiche « Merging is blocked due to failing merge requirements ».

### 14.8 Ce qui n'est pas prouvé

- **Les refus de la règle `protect-main` autres que la fusion** : une poussée directe sur `main`, sa suppression et une poussée forcée n'ont pas été essayées (si la règle avait échoué, l'essai aurait abîmé `main`). Seul le blocage d'une fusion avec une CI rouge est observé (14.12).
- **Les scripts `006` et `012`** (données d'exemple) ne sont pas exécutés par la CI : leur effet n'y est pas vérifié.
  - Note du 2026-11-04, ajoutée après coup : rejoués par la CI depuis le lot 9 (section 17, G15 à G19).
- **L'authentification Windows** : la CI ne prouve que l'authentification SQL. Le chemin utilisé en local (authentification Windows) n'est pas couvert.
- **La migration d'`ubuntu-latest`** (annoncée vers Ubuntu 26 à partir du 2026-10-19) : le runner est fixé à `ubuntu-24.04`, mais la différence n'a pas été observée.
- **L'étiquette `2025-latest`** : elle se déplace avec le temps ; seule l'image des exécutions relevées (digest au 14.5) est connue. Une version plus récente du moteur peut changer un résultat.
- **Une pull request venant d'un fork** : selon la documentation de GitHub (« secrets are not passed to the runner when a workflow is triggered from a forked repository »), le secret ne serait pas transmis et la tâche `backend` échouerait. Non essayé.
- **Une CI exigée avant fusion** : une règle `protect-main` l'exige depuis le 2026-10-26 (constat en 14.10). Qu'elle empêche de fusionner une CI rouge est observé : voir 14.11 (hypothèses) et 14.12 (résultats).
- **L'application lancée à la main contre le SQL Server de la CI** : la CI ne lance que les tests ; l'API y démarre à l'intérieur des tests d'intégration. Ni `dotnet run`, ni Swagger UI, ni l'interface (Vite) n'ont été essayés contre un SQL Server en conteneur. Aucun Dockerfile n'existe dans le dépôt.
  - Note du 2026-11-02, ajoutée après coup : essayé au lot 7 contre un conteneur local, pour les fermes seulement (section 15).
  - Note du 2026-11-03, ajoutée après coup : un `Dockerfile` existe depuis le lot 8 (section 16 et [ADR 0011](adr/0011-api-dans-une-image-docker.md)).
- **Le réglage « Workflow permissions » du dépôt** (Settings, Actions, General) n'a pas été regardé. Il n'a pas d'effet sur cette CI, car `ci.yml` déclare lui-même `permissions: contents: read`.
- **L'effet du cache npm** : la durée avec et sans cache n'est pas mesurée.
- **Les annotations** de l'exécution n° 7 n'ont pas été relevées, et le détail des étapes de l'exécution n° 6 non plus.
- **Seules les exécutions du 2026-10-26 sont observées** : rien n'est dit de leur comportement à une autre date.

### 14.9 Rejouer la vérification

- Sur GitHub, onglet « Actions » : ouvrir une exécution puis « Re-run all jobs », ou pousser un nouveau commit sur la branche. Résultat attendu : les deux tâches vertes en environ 1 minute ; étape Test du `backend` : 75 et 88 réussis ; étape Test du `frontend` : 22 fichiers et 178 tests réussis.
- Pour voir le commit de fusion d'une pull request (remplacer 12 par son numéro), dans PowerShell, depuis le dépôt :

  ```powershell
  git fetch origin "refs/pull/12/merge"
  git log -1 --format="%H %P" FETCH_HEAD
  ```

  Résultat observé : le hash `13f2078…` suivi de ses deux parents. Ce hash est celui relevé le 2026-10-26 : il n'a pas été vérifié à quel moment GitHub recalcule la fusion, ni si « Re-run all jobs » reteste le même commit de fusion ou un nouveau.
- Pour comparer avec la machine de développement : `dotnet test Traceability.slnx` (résumé attendu `total : 163; échec : 0; réussi : 163`) et, dans `web/`, `npm run lint`, `npm run build`, `npm test`.

### 14.10 Protection de `main` : constat

Observé le 2026-10-26 sur GitHub, par captures d'écran. Décision et alternatives : [ADR 0010](adr/0010-protection-de-main-par-ruleset.md).

**Avant** (vers 19:48 et 19:52) : la page d'accueil du dépôt affichait « Your main branch isn't protected », et la page Settings, Branches (« Branch protection rules ») ne listait aucune règle. Elle proposait « Add branch ruleset » et « Add classic branch protection rule », en indiquant que les rulesets sont la méthode recommandée.

**Création** : le ruleset `protect-main` a été créé entre 20:00 et 20:02 (heure locale = UTC). GitHub a affiché « Ruleset created » et l'état « Active ».

**Réglages relevés sur la page du ruleset après création** :

- État **Active**, bypass list **vide**, cible : la branche par défaut (« Applies to 1 target: `main` »).
- Cochées : « Restrict deletions », « Block force pushes », « Require a pull request before merging » et « Require status checks to pass ».
- Pull request obligatoire : 0 approbation requise ; modes de fusion autorisés : Merge, Squash, Rebase. Parmi les réglages de cette règle, seul « Require an additional approval for unattributed Copilot pull requests » est coché (valeur par défaut de GitHub) ; son libellé dit qu'il ne joue que si un nombre d'approbations non nul est exigé.
- Vérifications exigées : `backend` et `frontend`, source GitHub Actions. « Require branches to be up to date before merging » et « Do not require status checks on creation » sont décochées.
- Décochées : « Restrict creations », « Restrict updates », « Require linear history », « Require deployments to succeed », « Require signed commits », « Require code scanning results », « Require code quality results », « Restrict code coverage », « Automatically request Copilot code review ».

**Effet vu sur la pull request n° 12** (vers 20:03 et 20:04, encore en brouillon, dernier commit `ba39c34`) :

- « All checks have passed » (4 vérifications réussies) et « No conflicts with base branch ».
- « This pull request is still a work in progress : Draft pull requests cannot be merged » : le bouton « Merge pull request » est grisé, à cause du brouillon.
- Détail des quatre vérifications, toutes marquées « Required » :

| Vérification | Durée |
|---|---|
| `CI / backend (pull_request)` | 1 min |
| `CI / backend (push)` | 54 s |
| `CI / frontend (pull_request)` | 22 s |
| `CI / frontend (push)` | 30 s |

Ce que ce constat montre : la règle existe, elle est active sur `main`, et la pull request rattache `backend` et `frontend` aux vérifications exigées, pour les deux déclenchements. Ce qu'il ne montre pas : qu'une vérification en échec empêche la fusion, ni qu'une poussée directe sur `main` est refusée ; l'essai du test cassé est en 14.11 et 14.12. Le brouillon masque l'effet de la règle sur le bouton de fusion.

### 14.11 Essai du test cassé : hypothèses écrites avant

Écrit le 2026-10-26 (soir), avant la création de la branche jetable et avant tout lancement de l'essai. Rien n'est encore observé.

**But** : voir un test en échec rendre la CI rouge, et voir la règle `protect-main` empêcher la fusion.

**Méthode prévue** :

1. La branche jetable `test/ci-red-check` est créée à partir de `feature/lot-6-ci`, une fois les commits de la documentation poussés.
2. Une seule ligne change : dans `src/Traceability.Api/Errors/SqlErrorTranslator.cs`, la ligne qui traduit la famille d'erreurs 502xx passe de 409 à 400. C'est le même défaut que la « casse volontaire » du lot 3b (section 9.2).
3. Le changement est commité et poussé, puis une pull request de cette branche vers `main` est ouverte, **pas en brouillon** : le message « Draft pull requests cannot be merged » masquerait l'effet de la règle. Cette pull request affichera aussi les commits de `feature/lot-6-ci`, puisque la branche en part.
4. On regarde l'onglet Actions (exécutions `push` et `pull_request`) et le cadre de fusion de la pull request.
5. La pull request n'est **jamais fusionnée** : elle est fermée sans fusion, la branche est supprimée, et on vérifie que `main` n'a pas bougé.

| N° | Prédiction | Fausse si… |
|---|---|---|
| E1 | Avec la ligne de `SqlErrorTranslator.cs` qui traduit la famille 502xx passée de 409 à 400, la tâche `backend` est rouge, à l'étape « Test », avec 4 échecs unitaires et 3 d'intégration. | La tâche est verte, ou l'étape rouge est une autre, ou les nombres diffèrent. |
| E2 | La tâche `frontend` reste verte : le changement ne touche pas `web/`. | Elle est rouge. |
| E3 | La pull request vers `main` montre `backend` en échec, signalé « Required », et le bouton de fusion n'est pas utilisable. | Le bouton de fusion reste utilisable malgré la tâche rouge. |

Remarque écrite avant l'essai : les nombres de E1 (4 et 3) viennent du lot 3b ; depuis, des tests ont été ajoutés (lots 3c à 5), et E1 est écrite telle quelle, avec ces nombres.

Résultats : voir 14.12.

### 14.12 Essai du test cassé : résultats

Observé le 2026-10-26 entre 20:59 et 21:12 (heure locale = UTC), par les captures d'écran et les journaux copiés. Les hypothèses E1 à E3 sont écrites en 14.11 (commit `2edf254`), avant l'essai ; elles ne sont pas modifiées.

**Ce qui a été fait** : la branche `test/ci-red-check`, créée à partir de `feature/lot-6-ci`, ne contient qu'un commit de plus, `2b53981` (« Break the 502xx status on purpose to see the CI fail »), poussé vers 20:59. Il change la ligne 34 de `SqlErrorTranslator.cs` : `>= 50200 and <= 50299 => new ApiError(409, …)` devient `new ApiError(400, …)`. Les lignes 49, 54 et 59 (doublons détectés par la base, aussi en 409) ne sont pas touchées.

**Exécution du push (`2b53981`)** : échec, 56 s au total. `backend` rouge (54 s), `frontend` vert (30 s).

Journal de l'étape `dotnet test Traceability.slnx --no-build` de la tâche `backend`, terminée par « Error: Process completed with exit code 1 » :

- Tests unitaires : `Failed: 4, Passed: 71, Total: 75` (118 ms). Les 4 échecs sont `Procedure_errors_map_to_the_status_of_their_family` pour les numéros 50200, 50201, 50202 et 50203 : « Expected: 409, Actual: 400 ».
- Tests d'intégration : `Failed: 5, Passed: 83, Total: 88` (1 s). Les 5 échecs sont `StationsTests.A_code_that_differs_only_by_case_is_already_taken`, `StationsTests.A_function_already_declared_gives_409`, `StationsTests.A_code_already_taken_gives_409`, `FarmsTests.A_code_already_taken_gives_409` et `BatchesTests.A_batch_code_already_taken_gives_409` : « Expected: Conflict, Actual: BadRequest ».
- Au total : 9 échecs et 154 réussis sur 163.
- La compilation avait réussi : l'étape de test lance les binaires déjà compilés (`--no-build`). C'est une déduction, le journal de l'étape de compilation n'a pas été relevé.
- Le journal copié est celui du push ; celui des exécutions de la pull request n'a pas été relevé.

**Pull request n° 13** (« Test only: break the 502xx status to see the CI fail (do not merge) », de `test/ci-red-check` vers `main`, 14 commits, pas en brouillon : l'écran affiche « Still in progress? Convert to draft »). Ses exécutions `pull_request` : `backend` rouge (1 min), `frontend` vert (26 s).

Cadre de fusion, état final (capture vers 21:08) : « Some checks were not successful : 2 failing, 2 successful checks » ; `backend (pull_request)` et `backend (push)` en échec, `frontend (pull_request)` et `frontend (push)` réussies, les quatre étiquetées « Required » ; le bouton « Merge pull request » est grisé. La capture suivante (vers 21:09), faite sur le bouton, affiche l'infobulle « Merging is blocked due to failing merge requirements », sans zone de confirmation de fusion.

| N° | Verdict | Observé |
|---|---|---|
| E1 | **Fausse** | `backend` rouge à l'étape de test, comme prévu, avec 4 échecs unitaires comme prévu. Mais 5 échecs d'intégration au lieu de 3 : la condition « les nombres diffèrent » est remplie. Les nombres 4 et 3 venaient du lot 3b ; des tests ajoutés depuis couvrent le même cas (remarque écrite avant l'essai en 14.11). |
| E2 | **Vraie** | `frontend` vert sur le push (30 s) et sur la pull request (26 s). |
| E3 | **Vraie** | `backend` en échec, signalé « Required », et fusion bloquée : « Merging is blocked due to failing merge requirements ». |

**Nettoyage** : la pull request n° 13 a été fermée sans fusion (« Closed with unmerged commits »), sa branche supprimée sur GitHub puis en local. Après `git fetch origin --prune`, `origin/main` vaut `45e3f600cc509ce5fe89dd3cf91a1ed71c67f82c`, comme avant l'essai : rien du test n'est entré dans `main`.

**Ce que l'essai ne montre pas** : une poussée directe sur `main`, sa suppression et une poussée forcée n'ont pas été essayées, car si la règle avait échoué l'essai aurait abîmé `main`. Il ne montre pas non plus ce qui arrive quand `frontend` seul est rouge, ni quand seule la vérification du déclencheur `push` ou celle de `pull_request` échoue.

### 14.13 Suivi après la fusion de la pull request n° 12

Écrit le 2026-10-27 d'après la page du workflow « CI » (onglet Actions, 26 exécutions) et l'historique Git local. Les exécutions décrites ont eu lieu le 2026-10-26.

- **Fusion** : la pull request n° 12 a été fusionnée par un commit de fusion, `05d1485` (2026-10-26 21:40:26 UTC), sans squash. Ses deux parents sont `45e3f60` (la pointe de `main` avant la fusion) et `6708285` (la pointe de la branche) : les commits de la branche restent dans l'historique de `main`.
- **Dernières exécutions avant la fusion** : n° 24 (push du commit `6708285`, réussie, 59 s) et n° 25 (pull request n° 12, déclenchement `synchronize`, réussie, 1 min 1 s).
- **Exécution après la fusion** : n° 26, push du commit `05d1485` sur `main`, réussie, 1 min 8 s. C'est la première exécution sur `main` : les 25 précédentes concernent les branches `feature/lot-6-ci` et `test/ci-red-check`.
- **Affichage de GitHub à la fusion** : « 4 checks passed », relevé le 2026-10-26 avec la règle `protect-main` active ; non revu le 2026-10-27 (la page publique des exécutions ne l'affiche pas).
- **« Ready for review »** : la pull request n° 12 était en brouillon à son ouverture (n° 7, voir 14.6) ; elle a été passée à « Ready for review » avant la fusion (relevé du 2026-10-26, non revu le 2026-10-27). Parmi les 26 exécutions de la page, aucune n'est déclenchée par cet événement : les exécutions `pull_request` listées sont `opened` (n° 7, pull request n° 12, et n° 15, pull request n° 13) et `synchronize`. Ce passage n'a donc pas lancé d'exécution.

## 15. Lot 7 : SQL Server en conteneur, application lancée à la main

Écrit le 2026-11-02, avant l'essai. Tant que l'essai n'est pas fait, chaque ligne de la liste vaut « À observer ». Il n'y a pas de prédiction chiffrée : chaque ligne se termine par « Observé » ou « Non observé », avec ce qui a été vu.

### 15.1 Ce qui est essayé

- Un conteneur SQL Server 2025 (image `mcr.microsoft.com/mssql/server:2025-latest`, authentification SQL, utilisateur `sa`) sur le PC de développement (Windows 11, environ 8 Go de RAM), sur le port 14330 côté PC pour ne pas gêner l'instance SQL Server locale.
- La base `TraceabilityDev` reconstruite dans ce conteneur par les scripts `001`, `002`, `004`, `005`, `011` et `017`, sans les données volumineuses.
- L'API (`dotnet run`) et l'interface (Vite) lancées à la main contre ce conteneur. La chaîne de connexion n'est remplacée que dans la fenêtre PowerShell de l'essai, pas dans les variables du compte Windows. Le mot de passe de `sa` n'est écrit nulle part dans le dépôt ni dans le chat.
- Aucun code, aucun script SQL et aucun fichier de la CI n'est modifié. Aucun Dockerfile, aucun fichier `docker-compose.yml`, aucun volume : les données disparaissent avec le conteneur.

### 15.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| D1 | `docker version` répond, côté client et côté serveur. | Observé. Client 29.6.1, serveur Docker Desktop 4.81.0, moteur 29.6.1 (`linux/amd64`). |
| D2 | Le conteneur démarre (`docker ps` le liste) et SSMS s'y connecte en authentification SQL sur `localhost,14330`. | Observé. `docker ps` : `traceability-sql`, état « Up », ports `0.0.0.0:14330->1433/tcp`. Journaux : « SQL Server is now ready for client connections » à 09:52:36. SSMS 22 connecté à `localhost,14330` en authentification SQL (chiffrement « Obligatoire », certificat de serveur de confiance coché). |
| D3 | Relever la version du moteur, l'édition et le système (`@@VERSION`, `SERVERPROPERTY('Edition')`), et l'empreinte (digest) de l'image utilisée. | Observé. `Microsoft SQL Server 2025 (RTM-CU10) (KB5125471) - 17.0.5035.5 (X64)`, 15 octobre 2026, Enterprise Developer Edition (64-bit) sur Linux (Ubuntu 24.04.5 LTS) ; `ProductVersion` 17.0.5035.5. Empreinte de l'image : `sha256:245f6b1c8903edae52cb20fa31419cefcde1a49938bb8c3447099011fc871ca3`, la même qu'au 14.5. Le moteur est donc celui de la CI, et non celui de l'instance locale (17.0.1145.4, relevée au lot 2b). |
| D4 | Les scripts `001`, `002`, `004`, `005`, `011` et `017` s'exécutent sans erreur dans le conteneur. | Observé. `001` : « Database TraceabilityDev created. » (`SIMPLE`, `ONLINE`, fichiers sous `/var/opt/mssql/data/`) ; `002` : 5 tables dans le schéma `trace` ; `004` : 3 procédures ; `005` : 7 ; `011` : 10 ; `017` : « Index IX_Batch_FarmId created. » (index `IX_Batch_FarmId` NONCLUSTERED, `PK_Batch` CLUSTERED, `UQ_Batch_BatchCode` NONCLUSTERED ; `ListBatches` modifiée à 10:15:19). Aucune erreur dans les sorties relevées ; pour `011`, seule la grille de résultat a été relevée, pas les messages. |
| D5 | L'API démarre contre le conteneur et Swagger UI s'ouvre sur `https://localhost:7080/swagger`. | Observé. « Now listening on: https://localhost:7080 », « Application started », « Hosting environment: Development ». Swagger UI affichée dans Edge sur `https://localhost:7080/swagger/index.html` (Traceability.Api v1, OAS 3.1). La chaîne de connexion a été définie dans la fenêtre PowerShell de l'essai seulement. |
| D6 | `GET /farms` répond ; relever le code. | Observé. Code 200, corps `{"items": [], "totalCount": 0, "pageNumber": 1, "pageSize": 20}`. Le conteneur est donc bien celui qui répond : la base locale compte 200 fermes (section 11). |
| D7 | Une ferme créée par `POST /farms` est relue par `GET /farms`. | Observé. `POST /farms` avec `TEST-DOCKER`, `Ferme essai Docker`, `Souss` : code 201 et corps identique. `GET /farms` ensuite : code 200, une ferme dans `items`, `totalCount` à 1. |
| D8 | L'interface web (Vite) s'ouvre contre cette API, et un formulaire de l'interface crée une ferme qui apparaît dans la liste. | Observé. `http://localhost:5173/farms` : une ferme, `TEST-DOCKER` (« Page 1 sur 1 · 1 au total »). Formulaire « Nouvelle ferme » (`UI-DOCKER`, `Ferme creee avec interface`, `Souss`) : message « Ferme UI-DOCKER créée. », puis la liste affiche 2 fermes (« 2 au total »). La sortie de Vite n'a pas été relevée : seule la page affichée l'est. |
| D9 | Relever la mémoire utilisée par le conteneur (`docker stats --no-stream`) pendant que l'API et Vite tournent. | Observé. `docker stats --no-stream` : 671,4 MiB utilisés sur une limite de 3,825 GiB (17,14 %), 4,16 % de processeur, 87 processus, l'API et Vite étant en marche et les deux fermes écrites. |
| D10 | Le conteneur est arrêté et supprimé (`docker stop`, `docker rm`) ; la base disparaît avec lui. | Observé. `docker inspect traceability-sql --format '{{json .Mounts}}'` : `[]` (aucun montage) ; `docker stop` puis `docker rm` ; `docker ps -a` ne liste plus le conteneur. Que la base disparaisse avec lui est une déduction (aucun montage), pas relevé sur un nouveau conteneur. |

### 15.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- L'authentification Windows : le conteneur est en authentification SQL.
- Les données volumineuses (un million de lots), les scripts `006` et `012`, et les tests C# contre ce conteneur.
- Un Dockerfile pour l'API ou l'interface, un fichier `docker-compose.yml`, un volume, une sauvegarde.
- Tout usage en production ou sur un serveur distant.

Ajouté après l'essai, le 2026-11-02 :

- Seules les fermes ont été lues et écrites. Les lots, les stations, les mouvements, `ListBatches` et les erreurs de l'API n'ont pas été essayés contre le conteneur.
- L'essai a eu lieu une seule fois, sur une seule machine : les scripts n'ont pas été rejoués une deuxième fois dans le conteneur.
- Le démarrage de Vite et les messages de `011` n'ont pas été relevés (voir D4 et D8).
- La limite de mémoire de 3,825 GiB est celle relevée par `docker stats` ; son origine (réglage de Docker Desktop) n'a pas été vérifiée.

### 15.4 Ce qui est prouvé

Essai du 2026-11-02, de 09:52 (création du conteneur) à 10:38 (suppression), heure UTC.

- **Le conteneur** : SQL Server 2025 en conteneur, avec la même image (même empreinte) et le même moteur que la CI, démarre sur le PC de développement et accepte une connexion SSMS en authentification SQL (D1 à D3).
- **La base** : les scripts `001`, `002`, `004`, `005`, `011` et `017` la reconstruisent dans le conteneur : 5 tables, 10 procédures et l'index `IX_Batch_FarmId` (D4).
- **L'API** : lancée à la main contre le conteneur, elle démarre, Swagger UI s'affiche, et une ferme créée par `POST /farms` est relue par `GET /farms` (D5 à D7). Aucun code n'a été modifié.
- **L'interface** : lancée contre cette API, elle liste les fermes du conteneur et en crée une par son formulaire (D8).
- **La mémoire** : 671,4 MiB pour le conteneur pendant l'essai (D9), sur une machine d'environ 8 Go.
- **Le nettoyage** : le conteneur ne montait aucun volume et a été supprimé (D10).

### 15.5 Rejouer la vérification

Dans PowerShell, depuis la racine du dépôt, dans la même fenêtre pour tout ce qui suit. Le mot de passe de `sa` (au moins 12 caractères, majuscules, minuscules et chiffres, sans symbole) est saisi masqué : il n'est écrit ni dans le dépôt ni dans une commande.

```powershell
$env:MSSQL_SA_PASSWORD = [Net.NetworkCredential]::new('', (Read-Host 'Mot de passe sa' -AsSecureString)).Password
docker run --name traceability-sql -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD -p 14330:1433 -d mcr.microsoft.com/mssql/server:2025-latest
```

Attendre la ligne « SQL Server is now ready for client connections » dans `docker logs traceability-sql`. Dans SSMS, se connecter à `localhost,14330` (authentification SQL, utilisateur `sa`, certificat de serveur de confiance coché) et exécuter, un par un et avec le mode SQLCMD actif, les scripts `001`, `002`, `004`, `005`, `011` et `017`. Puis lancer l'API contre le conteneur, dans la même fenêtre :

```powershell
$env:ConnectionStrings__Default = "Server=localhost,14330;Database=TraceabilityDev;User Id=sa;Password=$env:MSSQL_SA_PASSWORD;TrustServerCertificate=True"
dotnet run --project src/Traceability.Api --launch-profile https
```

Ouvrir `https://localhost:7080/swagger`, puis lancer l'interface dans une autre fenêtre (`cd web`, `npm run dev`). Pour nettoyer : arrêter l'API et Vite (Ctrl+C), puis `docker stop traceability-sql` et `docker rm traceability-sql`.

## 16. Lot 8 : l'API dans un conteneur Docker

Écrit le 2026-11-03, avant l'essai. Tant que l'essai n'est pas fait, chaque ligne de la liste vaut « À observer ». Il n'y a pas de prédiction chiffrée : chaque ligne se termine par « Observé » ou « Non observé », avec ce qui a été vu.

### 16.1 Ce qui est essayé

- Une image Docker de l'API, construite par un `Dockerfile` à la racine du dépôt (une étape de compilation, puis une image d'exécution `aspnet`) et un `.dockerignore`.
- Un réseau Docker, SQL Server 2025 (la même image qu'au lot 7) et l'API, chacun dans son conteneur. L'API joint SQL Server par le nom de son conteneur.
- La chaîne de connexion et le mot de passe de `sa` sont passés par des variables d'environnement au lancement du conteneur : ils ne sont écrits ni dans l'image, ni dans le dépôt, ni dans le chat.
- L'interface web (Vite) reste sur le PC et appelle l'API du conteneur : l'adresse est donnée par `VITE_API_URL` dans la fenêtre PowerShell de l'essai, sans créer de fichier.
- Aucun code C#, aucun script SQL, aucun fichier de l'interface et aucun fichier de la CI n'est modifié. Les fichiers ajoutés sont le `Dockerfile` et le `.dockerignore`.

### 16.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| F1 | `docker build` de l'image réussit. Relever la durée, la taille de l'image (`docker image ls`) et les étiquettes des images de base utilisées. | Observé. `docker build -t traceability-api .` : 16 étapes sur 16, 259,5 s au premier lancement, dont environ 152 s pour télécharger l'image SDK et 49 s pour l'image `aspnet` ; `dotnet restore` 37,4 s, `dotnet publish` 53,9 s. Contexte envoyé à Docker : 54,70 ko. Images de base : `mcr.microsoft.com/dotnet/sdk:10.0` et `mcr.microsoft.com/dotnet/aspnet:10.0` (empreintes tronquées dans le journal, non relevées en entier ; le filtre `docker image ls` n'a listé aucune image de base). Image finale `traceability-api:latest` : 356 Mo sur le disque, 102 Mo de contenu. |
| F2 | Relever l'utilisateur qui fait tourner l'image (`docker image inspect`, champ `Config.User`). | Observé. `Config.User` vaut `app`. |
| F3 | Relever les variables d'environnement de l'image (`Config.Env`) et le contenu du dossier de l'application dans l'image : ni mot de passe, ni chaîne de connexion, ni dossiers `web`, `database`, `tests` ou `.git`. | Observé. Variables : `PATH`, `APP_UID=1654`, `ASPNETCORE_HTTP_PORTS=8080`, `DOTNET_RUNNING_IN_CONTAINER=true`, `DOTNET_VERSION=10.0.14` et `ASPNET_VERSION=10.0.14` : ni mot de passe, ni chaîne de connexion. Dossier `/app` : l'API publiée et ses bibliothèques, les dossiers de langues et `runtimes`, `web.config`, `appsettings.json` (151 octets) et `appsettings.Development.json` (127 octets), dont le contenu n'a pas été lu. Pas de `web`, `database`, `tests` ni `.git`. |
| F4 | Un réseau Docker et un nouveau conteneur SQL Server sont créés, et les scripts `001`, `002`, `004`, `005`, `011` et `017` s'exécutent sans erreur dans ce conteneur (5 tables, 10 procédures, index `IX_Batch_FarmId`). | Observé. Réseau `traceability-net` créé ; conteneur `traceability-sql` (même image qu'au lot 7) lancé sur ce réseau, « ready for client connections » à 08:51:59. Les six scripts rejoués dans SSMS : 5 tables, 10 procédures et l'index `IX_Batch_FarmId` (contrôle final). Aucune erreur signalée ; seul le contrôle final a été collé. |
| F5 | Le conteneur de l'API démarre sans forcer l'environnement. Relever les journaux : adresse d'écoute, environnement affiché, avertissements éventuels. | Observé. `docker ps` : `traceability-api` « Up », `0.0.0.0:8080->8080/tcp`. Journaux : « Now listening on: http://[::]:8080 », « Application started », « Hosting environment: Production », « Content root path: /app », sans avertissement au démarrage. La chaîne de connexion, donnée par la variable `ConnectionStrings__Default`, désigne `traceability-sql,1433` : le nom du conteneur et son port interne. |
| F6 | Dans cet état, `GET /farms` et `GET /batches` répondent. Relever les codes et les corps. | Observé. `GET /farms` et `GET /batches` : code 200, corps `{"items":[],"totalCount":0,"pageNumber":1,"pageSize":20}` (base neuve). L'API du conteneur atteint donc SQL Server par le nom `traceability-sql`. Les journaux contiennent ensuite `warn: Microsoft.AspNetCore.HttpsPolicy.HttpsRedirectionMiddleware[3] Failed to determine the https port for redirect.` ; aucune redirection n'a eu lieu. |
| F7 | Dans cet état, relever la réponse de `/swagger`. | Observé. `GET /swagger` : 404 Not Found, corps vide. |
| F8 | Relancé avec `ASPNETCORE_ENVIRONMENT=Development`, Swagger UI s'affiche. | Observé. Conteneur relancé avec `ASPNETCORE_ENVIRONMENT=Development` : Swagger UI s'affiche sur `http://localhost:8080/swagger/index.html` (Traceability.Api v1, OAS 3.1, serveur `http://localhost:8080/`). |
| F9 | L'interface (Vite) contre l'API du conteneur liste les fermes et en crée une par son formulaire. | Observé, dans Chrome (le navigateur est donné par l'utilisateur, il n'est pas visible sur les captures ; la barre d'adresse montre `localhost:5173/farms`). Vite lancé avec `VITE_API_URL=http://localhost:8080` dans la fenêtre PowerShell. Liste vide (« Aucune ferme enregistrée. », « 0 au total ») : elle vient de la base du conteneur, la base locale comptant 200 fermes. Formulaire `API-DOCKER`, `Ferme avec API dans le conteneur`, `Souss` : « Ferme API-DOCKER créée. », puis la liste affiche « 1 au total ». La sortie de Vite n'a pas été relevée. |
| F10 | Relever la mémoire des deux conteneurs (`docker stats --no-stream`) pendant l'essai. | Observé. `docker stats --no-stream` : `traceability-api` 60,64 MiB (22 processus, 0,04 % de processeur) et `traceability-sql` 953,7 MiB (86 processus, 5,95 %), sur une limite de 3,825 GiB chacun, Vite en marche et une ferme écrite. |
| F11 | Les conteneurs, le réseau et l'image sont supprimés : `docker ps -a`, `docker network ls` et `docker image ls` ne les listent plus. | Observé. `docker stop` et `docker rm` des deux conteneurs, `docker network rm traceability-net`, `docker rmi traceability-api` (`Untagged` et `Deleted`). `docker ps -a` ne liste plus de conteneur, `docker network ls` ne liste plus `traceability-net` et `docker image ls traceability-api` est vide. Les images de base n'ont pas été supprimées. |

### 16.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- L'authentification Windows : le conteneur SQL Server est en authentification SQL.
- Les données volumineuses, les lots, les stations et les mouvements : seules les routes de lecture `GET /farms` et `GET /batches` et la création d'une ferme sont essayées.
- Un fichier `docker-compose.yml`, un registre d'images et l'envoi de l'image, un déploiement, un orchestrateur.
- Le HTTPS dans le conteneur : l'API y écoute en HTTP simple.
- La construction de l'image dans la CI.
  - Note du 2026-11-04, ajoutée après coup : faite par la CI depuis le lot 9 (section 17, G1 à G8).
- L'alternative sans Dockerfile (publication d'une image par le SDK .NET) : citée dans l'ADR, non essayée.

Ajouté après l'essai, le 2026-11-03 :

- Un seul essai, sur une seule machine, avec une seule construction de l'image : la construction avec le cache de Docker n'a pas été essayée, et sa durée n'est pas mesurée.
- Seules la création d'une ferme et les lectures `GET /farms` et `GET /batches` ont été essayées. Les stations, les mouvements et la création d'un lot n'ont pas été essayés avec l'API en conteneur.
- Le contenu de la configuration du conteneur (`docker inspect`) n'a pas été relevé, et aucun coffre à secrets n'est essayé : la chaîne de connexion est passée par une variable d'environnement.
- La sortie de Vite, les empreintes complètes des images de base et le contenu des deux fichiers `appsettings` de l'image n'ont pas été relevés.
- L'interface n'a été vue que dans Chrome pour cet essai (Edge ne l'a pas été).

### 16.4 Ce qui est prouvé

Essai du 2026-11-03 (heure UTC).

- **L'image** : un `Dockerfile` en deux étapes construit l'image de l'API (356 Mo). Elle s'exécute avec l'utilisateur `app`, et ses variables d'environnement ne contiennent ni mot de passe ni chaîne de connexion (F1 à F3).
- **L'API en conteneur** : lancée sur un réseau Docker avec la chaîne de connexion donnée au démarrage, elle joint SQL Server dans un autre conteneur par son nom, et répond à `GET /farms` et `GET /batches` (F4 à F6).
- **L'environnement** : sans le forcer, le conteneur démarre en `Production` : Swagger répond 404 et l'API journalise un avertissement sur la redirection HTTPS. Avec `ASPNETCORE_ENVIRONMENT=Development`, Swagger UI s'affiche (F5 à F8).
- **L'interface** : lancée contre l'API du conteneur, elle liste les fermes et en crée une par son formulaire (F9).
- **La mémoire et le nettoyage** : 60,64 MiB pour l'API et 953,7 MiB pour SQL Server pendant l'essai (F10) ; les conteneurs, le réseau et l'image sont supprimés (F11).
- Aucun code C#, aucun script SQL, aucun fichier de l'interface et aucun fichier de la CI n'a été modifié.

### 16.5 Rejouer la vérification

Dans PowerShell, depuis la racine du dépôt, dans la même fenêtre pour tout ce qui suit. Construire l'image, puis démarrer SQL Server sur un réseau Docker (le mot de passe de `sa` est saisi masqué, comme en 15.5) :

```powershell
docker build -t traceability-api .
$env:MSSQL_SA_PASSWORD = [Net.NetworkCredential]::new('', (Read-Host 'Mot de passe sa' -AsSecureString)).Password
docker network create traceability-net
docker run --name traceability-sql --network traceability-net -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD -p 14330:1433 -d mcr.microsoft.com/mssql/server:2025-latest
```

Dans SSMS, se connecter à `localhost,14330` et exécuter les scripts `001`, `002`, `004`, `005`, `011` et `017`, comme en 15.5. Puis lancer l'API en conteneur (sans `ASPNETCORE_ENVIRONMENT`, `/swagger` répond 404) :

```powershell
$env:ConnectionStrings__Default = "Server=traceability-sql,1433;Database=TraceabilityDev;User Id=sa;Password=$env:MSSQL_SA_PASSWORD;TrustServerCertificate=True"
docker run --name traceability-api --network traceability-net -e ConnectionStrings__Default -e ASPNETCORE_ENVIRONMENT=Development -p 8080:8080 -d traceability-api
```

Ouvrir `http://localhost:8080/swagger`. Pour l'interface, dans une autre fenêtre : `cd web`, `$env:VITE_API_URL = "http://localhost:8080"`, `npm run dev`, puis `http://localhost:5173/farms`. Pour nettoyer : arrêter Vite (Ctrl+C), puis `docker stop` et `docker rm` des deux conteneurs, `docker network rm traceability-net` et `docker rmi traceability-api`.

## 17. Lot 9 : la CI construit l'image Docker

Écrit le 2026-11-03, avant l'essai. Tant que l'essai n'est pas fait, chaque ligne de la liste vaut « À observer ». Il n'y a pas de prédiction chiffrée : chaque ligne se termine par « Observé » ou « Non observé », avec ce qui a été vu. Cette section est complétée au fil du lot : un changement de la CI, un commit, une exécution observée.

### 17.1 Ce qui est essayé

- Une troisième tâche `docker` dans `.github/workflows/ci.yml` : sur le runner `ubuntu-24.04`, elle construit l'image de l'API avec le `Dockerfile` du lot 8 (`docker build`). Elle ne lance pas l'image, ne l'envoie dans aucun registre et n'utilise aucun secret.
- La variable `SQLCMDPASSWORD` n'est plus définie pour toute la tâche `backend` : elle est donnée seulement aux trois étapes qui appellent `sqlcmd` pour se connecter à SQL Server (attente, construction de `TraceabilityTest`, liste en lecture seule). L'étape `Show tool versions` ne la reçoit pas : elle lance seulement `sqlcmd -?`, sans connexion. L'étape `Test` ne change pas : le mot de passe lui vient de `ConnectionStrings__Test`.
- Les cinq références à des actions de GitHub passent de l'étiquette de version majeure à l'empreinte complète du commit, relevée le 2026-11-03 avec `git ls-remote` (étiquettes non annotées) : `actions/checkout` `3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7.0.1`, trois occurrences), `actions/setup-dotnet` `0f4a354dd5547a28c70b7853dbd95d5b67886e73` (`v6.1.0`) et `actions/setup-node` `949feb2413d6458794dcd2491c4babbbce0c15c1` (`v7.1.0`). La version reste en commentaire sur chaque ligne.
- Les scripts `006` et `012` reçoivent à la fin de leur dernier lot un contrôle qui déclenche une erreur (niveau 16) si une ligne de résultat commence par `ATTENTION`, si le total vaut 0 ou si les comptes ne s'additionnent pas. Les résultats affichés ne changent pas. Un test « à vérifier à l'œil » compte comme réussi pour sa forme seulement : son contenu n'est pas contrôlé.
- Deux étapes de la tâche `backend` lancent `006` puis `012` avec `sqlcmd -b`, entre `List what was created` et `Build`, avec `SQLCMDPASSWORD` au niveau de l'étape. Les deux scripts écrivent `TraceabilityTest` en dur : aucune copie temporaire n'est nécessaire.
- Le `Dockerfile`, le `.dockerignore`, le code C#, les scripts SQL et l'interface ne sont pas modifiés sur la branche du lot. Seul un essai sur une branche jetable casse volontairement le `Dockerfile` (G6 à G8).
- La tâche `docker` ne fait pas partie des vérifications exigées par la règle `protect-main` (voir l'[ADR 0010](adr/0010-protection-de-main-par-ruleset.md)) : le réglage est dans GitHub et n'est pas modifié.

### 17.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| G1 | Après le push du premier commit du lot, l'exécution de la CI sur cette branche liste trois tâches : `backend`, `frontend` et `docker`. | Observé. Exécution n° 36 de la CI, commit `7aa5bf6`, déclenchement `push` sur la branche `feature/lot-9-ci` : trois tâches, `backend`, `frontend` et `docker`, toutes vertes. Durée de l'exécution : 1 min 10 s. |
| G2 | La tâche `docker` va au bout : l'étape `Build the API image` se termine sans erreur. Relever la durée de cette étape et celle de la tâche. | Observé. Tâche `docker` réussie en 35 s ; étape `Build the API image` : 16 s. Les 16 étapes du `Dockerfile` s'exécutent (`#1` à `#16`), sans ligne `CACHED`. Détail du journal : téléchargement de l'image SDK 7,6 s, `dotnet restore` 2,4 s, `dotnet publish` 4,7 s ; contexte envoyé à Docker : 53,51 ko ; builder : instance `default`, pilote `docker`. Images de base de cette exécution : `mcr.microsoft.com/dotnet/aspnet:10.0@sha256:de0ee358cdd672f7017a003bed21e9ac9ed48a27c922a59b18175b6e82fa7fee` et `mcr.microsoft.com/dotnet/sdk:10.0@sha256:de4fe90a98845d75910b9769662465c84de1a934665c431279d1382b2bddc02b`. |
| G3 | L'étape `Show the image` affiche l'image `traceability-api` : relever sa taille et la comparer aux 356 Mo observés en local (16.2, F1). | Observé. `docker image ls traceability-api` : étiquette `latest`, identifiant `9c36eb4c9611`, taille 240 MB (356 Mo en local au lot 8, F1). La cause de l'écart n'est pas établie : la version de Docker du runner n'a pas été relevée et la méthode de calcul de la taille n'a pas été comparée. |
| G4 | Le journal de la tâche `docker` ne contient ni `docker push`, ni connexion à un registre, ni valeur de secret, et le fichier ne contient aucune référence à `secrets.` dans cette tâche. | Observé. La tâche n'a ni étape d'envoi ni étape de connexion. Le journal de l'étape `Build the API image` a été lu en entier : ni `docker push`, ni connexion à un registre, ni `***`. Le fichier ne contient aucune référence à `secrets.` dans cette tâche. La zone de recherche des journaux de GitHub n'est pas retenue comme preuve (voir G10). |
| G5 | `backend` et `frontend` restent verts, avec des durées comparables à celles du lot 6 (environ 1 minute). | Observé. `backend` : vert en 1 min 6 s ; `frontend` : vert en 34 s. |
| G6 | Sur une branche jetable partie de `feature/lot-9-ci`, le `Dockerfile` est cassé en retirant la ligne qui copie `Traceability.Data.csproj` (le projet dont dépend l'API), puis poussé : la tâche `docker` devient rouge. Relever l'étape en échec et le message d'erreur. | Observé. Exécution n° 37 de la CI, commit `78c5ae2`, branche `test/lot-9-dockerfile-casse` (la ligne `COPY src/Traceability.Data/Traceability.Data.csproj …` est retirée du `Dockerfile`) : la tâche `docker` est rouge en 23 s. L'étape `Build the API image` échoue (15 s), l'annotation affiche « Process completed with exit code 1 » et l'étape `Show the image` n'est pas exécutée. Dans le journal : l'étape `[build 4/6] RUN dotnet restore` se termine sans erreur (1,4 s) en ignorant le projet absent (« Skipping project … Traceability.Data.csproj because it was not found. », deux fois) ; l'étape en échec est `[build 6/6] RUN dotnet publish … --no-restore` (`Dockerfile:18`), avec `error NETSDK1004: Assets file '/src/src/Traceability.Data/obj/project.assets.json' not found. Run a NuGet package restore to generate this file.` et le code de sortie 1. |
| G7 | Dans la même exécution, `backend` et `frontend` restent verts. | Observé. Dans la même exécution, `backend` : vert en 55 s ; `frontend` : vert en 38 s. Statut de l'exécution : Failure (58 s), à cause de `docker` seul. |
| G8 | La branche jetable est supprimée en local et sur GitHub, et le `Dockerfile` de `feature/lot-9-ci` n'est pas modifié (`git diff` vide sur ce fichier). | Observé. Branche jetable supprimée : `git branch -D` (« Deleted branch … (was 78c5ae2) ») et `git push origin --delete` (« [deleted] »). `git branch -a` ne liste plus que `feature/lot-9-ci`, `main` et leurs versions `origin`. `git diff --stat main feature/lot-9-ci` ne montre qu'un fichier, `.github/workflows/ci.yml` (20 insertions, 1 suppression) : le `Dockerfile` de la branche du lot n'est pas modifié. L'exécution n° 37 reste visible dans l'onglet Actions. |
| G9 | Après le push du commit de ce changement, `backend` est vert : les trois étapes qui appellent `sqlcmd` (attente, construction de `TraceabilityTest`, liste en lecture seule) se terminent sans erreur de connexion. | Observé. Exécution n° 38 de la CI, commit `6771666`, déclenchement `push` : `backend` vert en 57 s. Les trois étapes qui appellent `sqlcmd` se terminent sans erreur de connexion : `Wait for SQL Server` (« SQL Server answered after about 2 s »), `Build TraceabilityTest from the SQL scripts` (les six scripts s'exécutent : base créée, 5 tables, 10 procédures, index `IX_Batch_FarmId`) et `List what was created` (moteur 17.0.5035.5 sous Ubuntu 24.04.5, 10 procédures, 3 index de `trace.Batch`). |
| G10 | Dans les journaux de `backend`, l'en-tête des trois étapes `sqlcmd` affiche `SQLCMDPASSWORD: ***`, et celui des autres étapes (récupération du dépôt, installation de .NET, installation de `sqlcmd`, versions, compilation, tests) ne l'affiche pas. | Observé. En-têtes lus dans les journaux : les trois étapes `sqlcmd` affichent `SQLCMDPASSWORD: ***` sous `env:` ; les étapes `Install sqlcmd (mssql-tools18)` et `Build` (`dotnet build`) n'affichent que `DOTNET_ROOT`. Les autres étapes de la tâche (récupération du dépôt, installation de .NET, versions, tests) n'ont pas été relevées une à une. Une recherche de `SQLCMDPASSWORD` dans les journaux de `backend` a affiché 0 résultat, alors que ce nom figure dans l'en-tête de trois étapes : la zone de recherche des journaux n'est pas retenue comme preuve, et la cause de ce résultat n'est pas établie. |
| G11 | `frontend` et `docker` restent verts dans la même exécution. | Observé. Dans la même exécution, `frontend` : vert en 22 s ; `docker` : vert en 24 s. Exécution : Success, 1 min 1 s. |
| G12 | Après le push du commit de ce changement, `backend`, `frontend` et `docker` sont verts. | Observé. Exécution n° 39 de la CI, commit `3368b3c`, déclenchement `push` : `backend` vert en 1 min 32 s, `frontend` vert en 32 s, `docker` vert en 32 s. Exécution : Success, 1 min 35 s. |
| G13 | Dans l'étape `Set up job` de chaque tâche, le journal indique les actions téléchargées avec leur empreinte : ce sont celles du 17.1. | Observé. Journaux de l'étape `Set up job` : `backend` télécharge `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` et `actions/setup-dotnet@0f4a354dd5547a28c70b7853dbd95d5b67886e73` ; `frontend` télécharge `actions/checkout` (même empreinte) et `actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1` ; `docker` télécharge `actions/checkout` (même empreinte). Pour chaque action, le journal affiche `SHA:` suivi de la même empreinte. Ce sont celles du 17.1. Image du runner : `ubuntu-24.04`, version 20261025.353.1, Ubuntu 24.04.5 LTS. |
| G14 | Les versions d'outils affichées par les étapes `Show tool versions` sont celles d'avant ce changement (SDK .NET 10.0.403, Node v22.23.3). | Observé : une valeur a changé. SDK .NET `10.0.403` : identique. Node : `v22.23.4` (npm `10.9.9`), alors que `v22.23.3` avait été relevé en CI au lot 6 : la version a changé entre les deux exécutions sans modification de `node-version: 22` ; la cause n'a pas été relevée (le fichier demande la dernière version 22.x). Autres valeurs relevées : `sqlcmd` `18.7.0001.1` (Linux) ; image SQL Server `mcr.microsoft.com/mssql/server@sha256:245f6b1c8903edae52cb20fa31419cefcde1a49938bb8c3447099011fc871ca3`, la même empreinte qu'au lot 7 (section 15). |
| G15 | `006` rejoué dans SSMS sur `TraceabilityTest` avec le contrôle ajouté : relever le résumé (`tests_total`, `tests_ok`, `tests_by_eye`) et la liste d'erreurs (aucune erreur attendue). | Observé. `006` rejoué dans SSMS (instance locale, base `TraceabilityTest`, résultats en texte) le 2026-11-04 à 08:41:33 UTC, avec le contrôle ajouté : `tests_total` 38, `tests_ok` 34, `tests_by_eye` 4. La sortie contient les messages du serveur (« lignes affectées ») et aucun message d'erreur. Les tableaux des 4 tests à vérifier à l'œil (30, 32, 33 et 38) s'affichent et, comparés par lecture de la sortie collée aux attendus que le script affiche, sont conformes. Le test 32 affiche aussi deux lots de préfixe `ZT-`, qui ne viennent ni de `006` ni de `012` (origine non relevée). |
| G16 | `012` rejoué de la même façon : relever le résumé et la liste d'erreurs. | Observé. `012` rejoué de la même façon à 08:42:34 UTC : `tests_total` 16, `tests_ok` 10, `tests_by_eye` 6, aucun message d'erreur dans la sortie. Les 6 tableaux à l'œil sont conformes aux attendus affichés : `ListFarms` page 1 (36 fermes, les 5 dernières `ZY-F01` à `ZY-F05`, `TotalCount` 36) et page au-delà de la fin (aucune ligne, 36) ; `ListStations` page 1 (37 stations, les 5 dernières `ZY-S01` à `ZY-S05`, 37) et page au-delà de la fin (aucune ligne, 37) ; `GetStation` `ZY-S01` (deux fonctions, `RECEPTION` puis `SORTING`) et `ZY-S02` (aucune fonction). La base contient des fermes et des stations de préfixe `ZT-` qui ne viennent pas de `012`. |
| G17 | Après le push du commit des deux étapes, `backend` : relever l'état des étapes `006` et `012`, et le résumé que le journal de chacune affiche. | Observé. Exécution n° 41 de la CI, commit `86e0642`, déclenchement `push` : verte en 56 s (`backend` 52 s, `frontend` 23 s, `docker` 24 s). Les étapes `Run 006 (stored procedure tests)` et `Run 012 (list procedure tests)` sont vertes. Résumé affiché par `006` : `tests_total` 38, `tests_ok` 34, `tests_by_eye` 4 ; par `012` : 16, 10, 6. Ce sont les mêmes chiffres qu'en local (G15 et G16), alors que la base de la CI a le classement `SQL_Latin1_General_CP1_CI_AS` (journal de l'exécution n° 38). Les tableaux des tests à vérifier à l'œil s'affichent dans les journaux ; comparés aux attendus du script par lecture, ils sont conformes, sur une base neuve : `TotalCount` 2 au test 32 de `006`, et 9 fermes et 10 stations dans `012`, sans lignes de préfixe `ZT-`. Aucun message d'erreur dans les deux journaux. |
| G18 | Sur une branche jetable, une règle d'une procédure est cassée : la CI devient rouge à l'étape `006` ou `012` (message de verdict relevé), et les étapes `Build` et `Test` ne sont pas exécutées. | Observé pour `006`. Exécution n° 42 de la CI, commit `24cd5b1`, branche `test/lot-9-regle-cassee`, déclenchement `push` (une seule exécution : pas de pull request sur cette branche). La règle 8 de `AddMovement` est cassée dans `005` (`IF @QuantityKg > @CurrentQuantity + 100000` au lieu de `IF @QuantityKg > @CurrentQuantity`). Statut de l'exécution : Failure (35 s) ; `backend` rouge en 31 s, `frontend` vert en 30 s, `docker` vert en 25 s. Dans `backend`, `Run 006 (stored procedure tests)` est rouge (1 s) ; `Run 012`, `Build`, `Test` et `Post Set up .NET` sont grisés (non exécutés) ; `Post Check out the repository`, `Stop containers` et `Complete job` s'exécutent et sont verts. Journal de `006` : test 29 (`AddMovement: quantity goes up`) attendu `50302`, résultat `ATTENTION: accepted`, détail `NULL` ; résumé `tests_total` 38, `tests_ok` 33, `tests_by_eye` 4 (contre 34 en G15 et G17) ; puis `Msg 50000, Level 16, State 1, Line 958` : `006 verdict: FAILED (tests_total = 38, passed or to check by eye = 37, marked ATTENTION = 1).` et `Error: Process completed with exit code 1.` Pour `012` : non essayé avec une règle cassée (G19 essaie son contenu à l'œil). |
| G19 | Sur une autre branche jetable, le contenu d'un test « à vérifier à l'œil » est modifié sans changer la forme des tableaux : relever l'état de l'étape du script et celui de l'étape `Test`. | Observé. Exécution n° 43 de la CI, commit `2aa83e9`, branche `test/lot-9-contenu-casse`, déclenchement `push`. Dans `011`, `ListFarms` est modifié : `ORDER BY FarmId` devient `ORDER BY FarmId DESC`. Statut de l'exécution : Failure (1 min 0 s) ; `backend` rouge en 56 s, `frontend` vert en 28 s, `docker` vert en 28 s. Dans `backend` : `Run 006` vert (0 s), `Run 012` vert (0 s), `Build` vert (18 s), `Test` rouge (7 s) ; `Post Set up .NET` grisé. Journal de `012` : aucune erreur, résumé `tests_total` 16, `tests_ok` 10, `tests_by_eye` 6, identique à G17. Le tableau de `ListFarms` du test 1 affiche `ZY-F05`, `ZY-F04`, `ZY-F03`, `ZY-F02`, `ZY-F01`, puis `ZZ-F10`, `ZZ-F03`, `ZZ-F02`, `ZZ-F01` (`TotalCount` 9), alors que le test demande les 5 dernières lignes `ZY-F01` à `ZY-F05` dans cet ordre : le script reste vert (« The script checked the number and the shape of the result sets, not the values »). Journal de l'étape `Test` : tests unitaires 75 réussis sur 75 ; tests d'intégration 88 au total, 87 réussis, 1 échec : `FarmsTests.The_list_returns_the_farms_in_creation_order_with_the_total`, `Assert.Equal() Failure: Collections differ`, attendu `[0, 1, 2]`, obtenu `[2, 1, 0]` (`FarmsTests.cs`, ligne 75), puis `Error: Process completed with exit code 1.` Pour cette modification, l'étape `012` ne voit rien et c'est un test C# de l'API qui fait rougir la CI. Les autres contenus vérifiés à l'œil (4 dans `006`, 6 dans `012`) ne sont pas essayés : l'existence d'un test C# équivalent n'est pas relevée. |
| G20 | Les branches jetables sont supprimées, et ni les scripts ni `ci.yml` de la branche du lot ne sont modifiés par ces essais. | Observé. Branches jetables supprimées : `git branch -D` (« Deleted branch test/lot-9-regle-cassee (was 24cd5b1) » et « Deleted branch test/lot-9-contenu-casse (was 2aa83e9) ») et `git push origin --delete` (deux « [deleted] »). `git branch -a` ne liste plus que `feature/lot-9-ci`, `main` et leurs versions `origin`. `git status --short` ne montre que ` M docs/verification.md` (non commité). `git diff --stat main feature/lot-9-ci` ne montre que trois fichiers : `.github/workflows/ci.yml` (61 lignes touchées), `database/006_check_procedures.sql` (+15) et `database/012_check_list_procedures.sql` (+15), soit 81 insertions et 10 suppressions : ni `005`, ni `011`, ni le `Dockerfile` ne sont modifiés sur la branche du lot. |
| G21 | Le badge de la CI ajouté au `README.md` s'affiche sous le titre sur la page de la branche, avec l'état « passing ». (Ligne ajoutée après le push : elle n'avait pas été écrite avant l'essai, contrairement aux lignes G1 à G20.) | Observé. Exécution n° 44 de la CI, commit `f529b9a` (« Add the CI badge to the README »), déclenchement `push`, branche `feature/lot-9-ci` : Success en 50 s ; `backend` vert en 47 s, `frontend` vert en 18 s, `docker` vert en 21 s. Le commit modifie un seul fichier, `README.md` (2 lignes ajoutées : le badge et une ligne vide). Sur la page de la branche (`/tree/feature/lot-9-ci`), le README affiche sous le titre un badge « CI » avec « passing » sur fond vert. Dernier run de `main` (filtre `branch:main`) : n° 35, commit `38da64e` (fusion de la pull request n° 16, lot 8), le 3 novembre à 09:43 UTC, Success en 1 min 4 s, deux jobs seulement (`backend` 1 min 0 s, `frontend` 26 s : le job `docker` n'existe pas encore sur `main`). Cet état est cohérent avec le badge ; l'origine exacte de l'état affiché par le badge n'a pas été relevée. |
| G22 | Dans le ruleset `protect-main` (réglages du dépôt), `docker` est ajouté aux vérifications exigées ; après enregistrement et rechargement de la page (F5), la liste montre `backend`, `frontend` et `docker`. (Ligne écrite après le réglage, avant l'essai G23.) | Observé. Le ruleset `protect-main` (Active, liste de contournement vide, une seule cible : `main`) liste après rechargement trois vérifications exigées, toutes de GitHub Actions : `backend`, `frontend`, `docker`. Les autres options visibles n'ont pas changé : « Require a pull request before merging » coché ; « Require branches to be up to date before merging » et « Do not require status checks on creation » décochés ; « Block force pushes » coché ; « Require code scanning results » décoché. |
| G23 | Sur une branche jetable partie de `feature/lot-9-ci`, le `Dockerfile` est cassé comme en G6 (ligne `COPY` de `Traceability.Data.csproj` retirée), puis une pull request vers `main` est ouverte (sans être fusionnée) : relever l'état des trois jobs, le message affiché à la place du bouton de fusion, et le nombre d'exécutions de la CI pour ce commit (déclenchements `push` et `pull_request`). | Observé. Branche `test/lot-9-pr-docker-cassee`, commit `f07c095` (la ligne `COPY src/Traceability.Data/Traceability.Data.csproj …` est retirée du `Dockerfile`). Le premier et le deuxième `git push` ont été refusés par GitHub (« Internal Server Error », puis « fatal error in commit_refs »), sans que la branche existe sur GitHub ; la page d'état de GitHub n'affichait alors aucun incident sur les opérations Git (un seul incident, sur Copilot Mission Control) ; le troisième `git push`, identique, a réussi. La cause des refus n'est pas établie. Pull request n° 17 (« Throwaway trial: broken Dockerfile (do not merge) »), ouverte vers `main` : 7 commits, 5 fichiers modifiés. Zone des vérifications : « Some checks were not successful — 2 failing, 4 successful checks ». En échec : `CI / docker (pull_request)` (19 s) et `CI / docker (push)` (21 s), toutes deux marquées « Required ». Réussies, toutes marquées « Required » : `CI / backend (pull_request)` 51 s, `CI / backend (push)` 51 s, `CI / frontend (pull_request)` 24 s, `CI / frontend (push)` 26 s. Le bouton « Merge pull request » est grisé ; le bouton « Merge status » affiche une croix rouge. Aucune phrase du type « Merging is blocked » n'est visible sur la capture. Actions, filtre `branch:test/lot-9-pr-docker-cassee` : deux exécutions, toutes deux rouges : n° 45 déclenchée par `push` (53 s) et n° 46 déclenchée par l'ouverture de la pull request (55 s) ; elles ne sont pas simultanées, la pull request ayant été ouverte après le push. Le bouton de fusion n'a pas été cliqué. |
| G24 | La pull request jetable est fermée sans fusion et la branche jetable supprimée (local et GitHub) : le dernier run de `main` reste le n° 35, et `git diff --stat main feature/lot-9-ci` ne montre ni le `Dockerfile` ni autre fichier de l'essai. | Observé. La pull request n° 17 est fermée sans fusion : statut « Closed » (et non « Merged »), message « Closed with unmerged commits », ses commits restent visibles, dont `f07c095` marqué d'une croix rouge. Branche supprimée : `git branch -D` (« Deleted branch test/lot-9-pr-docker-cassee (was f07c095) ») et `git push origin --delete` (« [deleted] »). `git branch -a` ne liste plus que `feature/lot-9-ci`, `main` et leurs versions `origin`. `git status --short` ne montre que ` M docs/verification.md` (non commité). `git diff --stat main feature/lot-9-ci` : `.github/workflows/ci.yml` (61 lignes touchées), `README.md` (+2), `database/006_check_procedures.sql` (+15) et `database/012_check_list_procedures.sql` (+15), soit 83 insertions et 10 suppressions : ni le `Dockerfile`, ni `005`, ni `011` ne sont modifiés sur la branche du lot. Actions, filtre `branch:main` : toujours 4 exécutions, la dernière est le n° 35 (commit `38da64e`, le 3 novembre à 09:43 UTC) ; les exécutions n° 45 et n° 46 de l'essai ne sont pas sur `main`. Onglet « Pull requests » (filtre `is:pr state:open`) : 0 ouverte, 17 fermées ; la pull request du lot 9 n'est pas encore créée (GitHub propose « Compare & pull request » pour `feature/lot-9-ci`). |

### 17.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- L'envoi de l'image dans un registre, un déploiement, un fichier `docker-compose.yml`.
- Le démarrage de l'image construite par la CI et un appel à l'API : la CI construit seulement l'image.
- L'ajout de `docker` aux vérifications exigées de `protect-main`, et la fusion d'une pull request dont la tâche `docker` est rouge : non essayés.
- La construction avec le cache de Docker : sur le runner, le premier lancement ne l'utilise pas.
- Une étape qui appelle `sqlcmd` sans la variable `SQLCMDPASSWORD` : l'échec de connexion qui en résulterait n'est pas essayé.
- La mise à jour future des empreintes (à la main ou par un outil) et le cas d'une étiquette déplacée par son propriétaire : non essayés.
- Le contenu des tests « à vérifier à l'œil » (4 dans `006`, 6 dans `012`) : la CI ne le contrôle pas.
- L'effet de la différence de classement entre la CI (`SQL_Latin1_General_CP1_CI_AS`, relevé dans le journal de l'exécution n° 38) et la base locale de développement (`French_CI_AS`, section 2) sur le résultat des tests.
- Une erreur de niveau 16 déclenchée par le contrôle, vue par un utilisateur dans SSMS : le message s'affiche en rouge dans l'onglet Messages, sans autre conséquence (non essayé tant que la CI n'a pas été rouge).

Ajouté après l'essai, le 2026-11-03 :

- Un seul type de casse est essayé : une ligne `COPY` retirée du `Dockerfile`. Les autres erreurs possibles (image de base introuvable, faute dans une commande) ne sont pas essayées.

Ajouté après les essais G18 à G24, le 2026-11-04 :

- Contenu des tests « à vérifier à l'œil » : un seul cas est essayé (l'ordre de `ListFarms` inversé) ; il est détecté par un test C# de l'API, pas par `012`. Les 9 autres contenus (4 dans `006`, soit les tests 30, 32, 33 et 38 ; 5 dans `012`) ne sont pas essayés.
- Le badge de la CI : l'état « failing » (dernier run de `main` rouge) et l'état après la fusion de la pull request du lot 9 (premier run de `main` avec les trois jobs) ne sont pas essayés.
- Mise à jour d'un point écrit avant l'essai : l'ajout de `docker` aux vérifications exigées de `protect-main` est fait (G22), et une pull request jetable au `Dockerfile` cassé est essayée (G23 et G24). Le point correspondant plus haut est donc réglé.
- La fusion elle-même : le bouton « Merge pull request » de la pull request n° 17 n'a pas été cliqué. L'effet du réglage est lu sur le bouton grisé et sur la liste des vérifications « Required ». Le texte exact affiché à la place du bouton n'a pas été relevé, et le renommage de la tâche `docker` sans changer la règle n'est pas essayé.
- Une règle cassée dans une procédure lue par `012` : seul `006` est essayé avec une règle cassée (G18) ; `012` l'est avec un contenu cassé (G19).
- Le double déclenchement : conservé (voir l'[ADR 0009](adr/0009-integration-continue-github-actions.md)). L'effet d'un seul déclenchement sur les vérifications exigées n'est pas essayé.

Ajouté après la fusion, le 2026-11-04 :

- Le badge de la CI : l'état après la fusion de la pull request du lot 9 (premier run de `main` avec les trois jobs) est maintenant essayé (voir 17.6). L'état « failing » (dernier run de `main` rouge) reste non essayé.

### 17.4 Ce qui est prouvé

Essais du 2026-11-03 et du 2026-11-04.

- **La CI construit l'image** : la tâche `docker` construit l'image de l'API avec le `Dockerfile` (étape `Build the API image` de 16 s, image `traceability-api` de 240 MB), sans la lancer, sans l'envoyer dans un registre et sans secret (G1 à G4).
- **Un `Dockerfile` cassé met la CI au rouge** : avec la ligne `COPY` de `Traceability.Data.csproj` retirée, la tâche `docker` est rouge, l'étape en échec est `dotnet publish` (et non `dotnet restore`), et `backend` et `frontend` restent verts (G6 et G7). Avec `docker` exigé par `protect-main`, le bouton « Merge pull request » de la pull request jetable n° 17 est grisé (G22 et G23).
- **Les scripts `006` et `012`** sont rejoués par la CI avec le même résumé qu'en local (38, 34 et 4 ; 16, 10 et 6) (G15 à G17). Avec une règle de `AddMovement` cassée dans `005`, l'étape `Run 006` devient rouge (`006 verdict: FAILED`) et les étapes `Run 012`, `Build` et `Test` ne sont pas exécutées (G18).
- **Limite observée** : le contenu des tests « à vérifier à l'œil » n'est pas contrôlé par les scripts. Avec l'ordre de `ListFarms` inversé, `Run 012` reste vert ; c'est un test C# de l'API qui rend l'étape `Test` rouge (G19). Les 9 autres contenus ne sont pas essayés.
- **`SQLCMDPASSWORD`** est défini sur les étapes qui appellent `sqlcmd`, et les en-têtes lus dans les journaux l'affichent masqué (`***`) sur ces étapes ; les autres étapes n'ont pas toutes été relevées une à une (G9 et G10).
- **Les actions** sont fixées par empreinte de commit, et l'étape `Set up job` de chaque tâche affiche ces empreintes (G12 et G13).
- **Le badge** de la CI s'affiche sous le titre du README de la branche avec « passing » ; son état « failing » n'est pas essayé (G21).
- **Le double déclenchement** : pour un même commit, une exécution `push` et une exécution `pull_request`, soit six vérifications au lieu de trois (G23). Il est conservé.
- Aucun code C#, script SQL (hors `006` et `012`), fichier de l'interface ni `Dockerfile` n'est modifié sur la branche du lot ; les branches jetables sont supprimées et la pull request jetable est fermée sans fusion (G8, G20 et G24).

### 17.5 Rejouer la vérification

- Sur GitHub, onglet « Actions » : ouvrir une exécution de la branche du lot puis « Re-run all jobs », ou pousser un nouveau commit. Résultat attendu : les trois tâches vertes en environ une minute (50 s pour l'exécution n° 44) ; dans `backend`, les étapes `Run 006` et `Run 012` vertes ; dans `docker`, l'étape `Build the API image`.
- Pour voir la CI rouge avec un `Dockerfile` cassé : sur une branche jetable partie de `feature/lot-9-ci`, retirer du `Dockerfile` la ligne `COPY src/Traceability.Data/Traceability.Data.csproj src/Traceability.Data/`, pousser, ouvrir une pull request vers `main` sans la fusionner. Résultat observé : `docker` rouge pour `push` et `pull_request`, `backend` et `frontend` verts, bouton de fusion grisé. Fermer la pull request sans fusion, puis supprimer la branche.
- Pour voir `Run 006` rouge : sur une branche jetable, dans `database/005_create_batch_procedures.sql`, remplacer `IF @QuantityKg > @CurrentQuantity` par `IF @QuantityKg > @CurrentQuantity + 100000` (dans `AddMovement`), puis pousser. Résultat observé : `Run 006` rouge, message `006 verdict: FAILED`, test 29 en `ATTENTION: accepted`.
- Pour rejouer `006` et `012` à la main : dans SSMS, sur `TraceabilityTest`. Résultat observé au lot 9 : `tests_total` 38, `tests_ok` 34, `tests_by_eye` 4 pour `006` ; 16, 10 et 6 pour `012` ; aucune erreur dans la sortie.

### 17.6 Suivi après la fusion de la pull request n° 18

Écrit le 2026-11-04 d'après la page de l'exécution n° 49 (onglet Actions), la page du dépôt et le `README.md` de `main`, relevés le 2026-11-04 vers 11:55 UTC. Cette section existe parce que ces observations n'étaient possibles qu'après la fusion : elles n'avaient pas été prévues dans le plan du commit final de documentation du lot.

- **Fusion** : la pull request n° 18 est fusionnée par un commit de fusion, `697523b` (« Merge pull request #18 from MBakkar2705/feature/lot-9-ci »). L'heure exacte de la fusion n'est pas relevée.
- **Exécution après la fusion** : n° 49, déclenchement `push`, branche `main`, commit `697523b`, Success en 59 s. Trois tâches vertes : `backend` 56 s, `frontend` 19 s et `docker` 23 s. C'est le premier run de `main` avec les trois tâches : le précédent, n° 35 (commit `38da64e`, fusion de la pull request n° 16), n'en avait que deux (`backend` et `frontend`).
- **Page du dépôt** : à côté du commit `697523b`, un point orange (exécution en cours) sur la première capture, puis une coche verte sur la capture prise après la fin de l'exécution.
- **Badge** : le `README.md` de `main` affiche « CI passing » sur la capture prise pendant l'exécution et sur celle prise après. Limite : le run précédent de `main` (n° 35) était vert lui aussi, donc le badge ne distingue pas le n° 49 du n° 35. L'état « failing » n'est pas essayé.

## 18. Lot 10a : le pseudo annuaire Keycloak, dans Docker et sous Windows

Écrit le 2026-11-04, avant l'essai. Tant que l'essai n'est pas fait, chaque ligne de la liste vaut « À observer ». Il n'y a pas de prédiction chiffrée : chaque ligne se terminera par « Observé » ou « Non observé », avec ce qui a été vu. Le lot 10a prépare seulement le serveur de connexion : l'API (lot 10b) et l'interface (lot 10c) ne sont pas touchées.

### 18.1 Ce qui est essayé

- Un serveur de connexion Keycloak, version 26.6.2 (celle du guide Docker officiel), lancé en mode développement (`start-dev`) : d'abord dans un conteneur Docker, ensuite directement sous Windows avec un JDK 21 extrait d'une archive `.zip` à côté du Java 24 existant (sans installation et sans changer le PATH de Windows). Le JDK 21 est dans la liste des JDK pris en charge par Keycloak (OpenJDK 17, 21 et 25, page « Supported Configurations » relevée le 2026-11-04) et c'est celui de l'image officielle.
- Un fichier de réglages, `identity/traceability-realm.json`, importé au démarrage (`--import-realm`) : un realm `traceability` (l'espace isolé de comptes de l'application), deux rôles `reader` (lecture seule) et `writer` (saisie), et un client d'essai `traceability-trial` qui permet d'obtenir un jeton avec un nom d'utilisateur et un mot de passe. Le fichier ne contient ni utilisateur ni mot de passe.
- Deux comptes d'essai, un par rôle, créés à la main dans la console d'administration. Leurs mots de passe sont saisis dans cette console et ne sont écrits dans aucun fichier du dépôt.
- Un jeton obtenu pour chaque compte, dont le contenu est lu pour y relever les rôles.
- Le port 8180 du PC est utilisé pour Keycloak dans les deux modes (un seul mode à la fois), car l'API en conteneur du lot 8 utilise le port 8080. Sous Windows, Keycloak n'écoute que sur `127.0.0.1` (`--http-host=127.0.0.1`) ; en Docker, le port est publié sur `127.0.0.1`.
- Le flux « mot de passe direct » du client d'essai ne sert qu'aux essais à la main : les sources consultées le réservent aux applications de confiance et le déconseillent en production. L'interface utilisera un autre flux (lot 10c).
- Aucun code C#, script SQL, fichier de la CI ni fichier de l'interface n'est modifié sur la branche du lot.

### 18.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| H1 | L'image `quay.io/keycloak/keycloak:26.6.2` se télécharge (`docker pull`). Relever sa taille et son empreinte (`docker image ls --digests`). | Observé le 2026-11-05. `docker ps -a` : aucun conteneur. `docker pull` : « Downloaded newer image for quay.io/keycloak/keycloak:26.6.2 », empreinte `sha256:f9ba7b2af90db8dc749a57ca9aedca51e840cb9224441ab546a968da941da900`. `docker image ls --digests` : identifiant `f9ba7b2af90d`, créée « 5 months ago », taille 751MB. |
| H2 | Le conteneur démarre avec `start-dev --import-realm` : le fichier `identity/traceability-realm.json` est monté en lecture seule dans `/opt/keycloak/data/import`, le port 8180 du PC est publié sur `127.0.0.1`, l'administrateur est créé par `KC_BOOTSTRAP_ADMIN_USERNAME` et `KC_BOOTSTRAP_ADMIN_PASSWORD` (mot de passe saisi en masqué). Relever le message de fin de démarrage et la durée. | Observé. `docker run -d --name traceability-keycloak -p 127.0.0.1:8180:8080 …` avec le fichier monté en lecture seule (`:ro`) ; mot de passe administrateur saisi masqué. `docker ps` après 40 s : `Up 41 seconds`, `127.0.0.1:8180->8080/tcp`. Premier filtre des journaux après 40 s : aucune ligne, Keycloak n'avait pas fini de démarrer. Journal : `Quarkus augmentation completed in 42776ms`, `Bootstrap completed in 31.418000 seconds`, `Keycloak 26.6.2 on JVM (powered by Quarkus 3.33.1.1) started in 47.631s. Listening on: http://0.0.0.0:8080`, `Profile dev activated`, `Running the server in development mode. DO NOT use this configuration in production.` ; `jdbc-h2` figure dans la liste des fonctions installées. |
| H3 | Le journal indique l'import du realm `traceability`. | Observé. Journal : `Importing from directory /opt/keycloak/bin/../data/import`, `KC-SERVICES0030: Full model import requested. Strategy: IGNORE_EXISTING`, `Realm 'traceability' imported`, `KC-SERVICES0032: Import finished successfully`, `KC-SERVICES0077: Created temporary admin user with username admin`. Aucune ligne `WARN` ni `ERROR` dans les 40 dernières lignes, qui couvrent tout le journal. |
| H4 | La console d'administration (`http://localhost:8180`) montre le realm `traceability`, ses rôles `reader` et `writer` et le client `traceability-trial`. | Observé, sur captures de la console (`http://localhost:8180/admin`, realm `traceability`). Realm roles : cinq rôles, `default-roles-traceability` (composite), `offline_access`, `reader` (« Read-only access: can list and view farms, stations and batches. »), `uma_authorization` et `writer` (« Data entry: can also create farms, batches and movements. »). Clients : sept, `account`, `account-console`, `admin-cli`, `broker`, `realm-management`, `security-admin-console` et `traceability-trial`. Bandeau jaune : « You are logged in as a temporary admin user. To harden security, create a permanent admin account and delete the temporary one. » |
| H5 | Deux comptes sont créés à la main dans la console, un par rôle, avec le rôle affecté. Les mots de passe sont saisis dans la console. | Observé, sur captures. `reader-test` et `writer-test` créés (adresses `reader-test@example.com` et `writer-test@example.com`, prénoms `Reader` et `Writer`, nom `Test`), sans action requise ni groupe. Onglet Role mapping : `reader` et `default-roles-traceability` pour le premier, `writer` et `default-roles-traceability` pour le second, tous en `Inherited : False`. Les mots de passe sont saisis dans la console et ne sont pas visibles. Dans la liste Users, un point d'exclamation rouge marque chaque adresse. |
| H6 | Un jeton est obtenu pour chaque compte auprès de `/realms/traceability/protocol/openid-connect/token` (`curl.exe`, mot de passe saisi en masqué). Relever le code, `token_type` et `expires_in`. | Observé. Fonction PowerShell `Get-Trial` (`curl.exe`, flux « mot de passe direct » du client `traceability-trial`, mot de passe saisi masqué) : `Code : HTTP:200`, `token_type : Bearer`, `expires_in : 300` pour `reader-test` et pour `writer-test`. Seul le contenu décodé du jeton est affiché, jamais le jeton brut. |
| H7 | Le contenu du jeton du compte « lecture seule » contient le rôle `reader` et pas `writer` ; celui du compte « saisie » contient `writer`. Relever dans quel champ du jeton se trouvent les rôles, ainsi que l'émetteur (`iss`), la date d'expiration (`exp`) et le public visé (`aud`). | Observé. `reader-test` : `realm_access.roles` contient `reader`, `offline_access`, `default-roles-traceability` et `uma_authorization`, pas `writer`. `writer-test` : `offline_access`, `default-roles-traceability`, `writer` et `uma_authorization`, pas `reader`. Les rôles sont dans `realm_access.roles`. `iss` : `http://localhost:8180/realms/traceability` ; `aud` : `account` ; `azp` : `traceability-trial` ; `exp` moins `iat` : 300 s (1793869060 − 1793868760 et 1793869066 − 1793868766) ; `scope` : `profile email` ; `email_verified` : `false`. |
| H8 | Un mauvais mot de passe est refusé. Relever le code et le corps de la réponse. | Observé. Mauvais mot de passe pour `reader-test` : `Code : HTTP:400`, corps `{"error":"invalid_grant","error_description":"Invalid user credentials"}` (code 400 et non 401). |
| H9 | Relever la mémoire du conteneur (`docker stats --no-stream`) après l'obtention des jetons. | Observé, après les jetons et un essai refusé seulement : la mémoire juste après le démarrage n'a pas été relevée. `traceability-keycloak` : 706.3MiB / 3.825GiB (18,03 %), 0,77 % de processeur, 44 processus, E/S réseau 262kB / 7.43MB. |
| H10 | Le conteneur supprimé puis recréé avec le même fichier réimporte le realm, les rôles et le client (sans les comptes, à recréer). | Observé. `docker rm -f traceability-keycloak`, puis le même `docker run` : journal `Realm 'traceability' imported` et `started in 50.183s`. Console : Realm roles avec les mêmes cinq rôles ; Clients avec les sept clients dont `traceability-trial` ; Users : « No users found ». Un `Get-Trial` lancé ensuite a répondu `HTTP:400` `invalid_grant`, mais le mot de passe a peut-être été mal saisi : non retenu comme preuve. |
| H11 | Un JDK 21 est extrait d'une archive `.zip` à côté du Java 24, sans installation. Relever sa version exacte et son dossier. `java -version` affiche toujours la version 24. | Observé. Archive `OpenJDK21U-jdk_x64_windows_hotspot_21.0.13_9.zip` (Eclipse Temurin) extraite dans `$HOME\tools\jdk-21.0.13+9`. `java.exe -version` de ce dossier : `openjdk version "21.0.13" 2026-10-20 LTS`, `OpenJDK Runtime Environment Temurin-21.0.13+9 (build 21.0.13+9-LTS)`. `java -version` dans la même fenêtre : `java version "24" 2025-03-18`, `Java(TM) SE Runtime Environment (build 24+36-3646)`. |
| H12 | Keycloak 26.6.2 (archive zip) est extrait hors du dépôt, le fichier de réglages est copié dans `data\import`, et Keycloak démarre dans une nouvelle fenêtre avec `bin\kc.bat start-dev --import-realm --http-port=8180 --http-host=127.0.0.1`, `JAVA_HOME` posé pour cette fenêtre seulement. Relever le message de fin de démarrage et la durée. | Observé. Archive `keycloak-26.6.2.zip` (page « Downloads 26.6.2 » de keycloak.org) extraite dans `$HOME\tools\keycloak-26.6.2` ; fichier copié dans `data\import` (738 octets). Un premier lancement, sans mot de passe administrateur défini, s'est arrêté aussitôt avec `bootstrap-admin-username available only when bootstrap admin password is set` : rien n'a démarré. Avec `KC_BOOTSTRAP_ADMIN_USERNAME` et `KC_BOOTSTRAP_ADMIN_PASSWORD` (saisi masqué) définis, journal : `Quarkus augmentation completed in 18138ms`, `Importing from directory …\keycloak-26.6.2\bin\..\data\import`, `Realm 'traceability' imported`, `Import finished successfully`, `Bootstrap completed in 16.741000 seconds`, `Keycloak 26.6.2 on JVM (powered by Quarkus 3.33.1.1) started in 26.456s. Listening on: http://127.0.0.1:8180`. L'option `--http-host=127.0.0.1` a été acceptée. |
| H13 | Sous Windows, les contrôles H3 à H8 donnent les mêmes résultats que dans Docker. Relever toute différence. | Observé. Mêmes résultats que dans Docker pour H3 (journal), H4 (cinq rôles, sept clients), H5 (comptes recréés, mêmes rôles), H6 (`HTTP:200`, `Bearer`, 300), H7 (`reader` sans `writer`, `writer` sans `reader`, mêmes `iss`, `aud` et durée) et H8 (`HTTP:400`, même corps). Différences relevées : l'ordre des rôles dans `realm_access.roles` et celui du champ `scope` (`email profile` sous Windows, `profile email` en Docker) ; l'adresse d'écoute (`127.0.0.1:8180` sous Windows ; port 8080 du conteneur publié sur `127.0.0.1:8180` en Docker). |
| H14 | Relever la mémoire du processus Java de Keycloak sous Windows (`Get-Process java`). | Observé, après les jetons et le refus. `Get-Process java` : un seul processus, `MemMiB : 512,5` (mémoire de travail du processus Windows), chemin `…\tools\jdk-21.0.13+9\bin\java.exe` : c'est le JDK 21 qui fait tourner Keycloak. Cette mesure n'est pas comparable terme à terme à celle de `docker stats` (H9). |
| H15 | Après l'essai, le serveur est arrêté (Ctrl+C), aucun `java.exe` lancé pour l'essai ne reste, le conteneur est supprimé et `java -version` affiche encore la version 24. | Observé. Docker : `docker rm -f traceability-keycloak`, puis `docker ps -a` ne liste aucun conteneur. Windows : après Ctrl+C dans la fenêtre de Keycloak, `Get-Process java` n'affiche rien et `java -version` affiche `java version "24" 2025-03-18`. L'image `quay.io/keycloak/keycloak:26.6.2` et le dossier `tools` (JDK 21 et Keycloak) sont conservés. |
| H16 | Le fichier `identity/traceability-realm.json` ne contient aucun mot de passe ni secret : relever le résultat d'une recherche des mots `password`, `secret` et `credentials`. | Observé. Recherche (insensible à la casse) de `password`, `secret` et `credentials` dans `identity/traceability-realm.json` : aucune ligne. Le fichier fait 28 lignes et 738 octets, la taille de la copie importée sous Windows. |

### 18.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- Keycloak avec Java 24 : cette version n'est pas dans la liste des JDK pris en charge. Java 25, qui y figure, n'est pas essayé non plus.
- Le mode production (`start`), HTTPS, une base de données externe, la conservation des données entre deux démarrages (aucun volume) et la haute disponibilité.
- Un vrai annuaire d'entreprise (LDAP, Active Directory, Entra ID) et la fédération de comptes.
- La vérification du jeton par l'API et le refus selon le rôle : lot 10b. La connexion depuis l'interface, avec le flux par code d'autorisation : lot 10c.
- La CI : elle ne lance pas Keycloak à ce lot.
- L'enregistrement de l'utilisateur sur chaque mouvement : lot suivant.
- Un fichier `docker-compose.yml`, un registre, un déploiement.

Ajouté après l'essai (2026-11-05) :

- Une version de Keycloak plus récente que 26.6.2 : des versions plus récentes existent (par exemple 26.6.3, 26.6.4 et 26.7.2). La 26.6.2 est gardée dans les deux modes pour qu'ils soient comparables.
- Un compte administrateur permanent : l'essai utilise l'administrateur temporaire de démarrage, que la console signale par un bandeau.
- La mémoire de Keycloak juste après le démarrage : H9 est relevée après les jetons seulement.
- La conservation des données : en Docker, la base H2 est dans le conteneur et les comptes disparaissent avec lui (H10).
- Le flux par code d'autorisation avec PKCE (lot 10c). Le flux « mot de passe direct » n'est utilisé qu'à la main, avec le client d'essai.
- L'effet de l'adresse utilisée pour demander le jeton sur `iss` : observé seulement avec `http://localhost:8180`.
- Le contenu du jeton face à une API qui le vérifie : lot 10b.

### 18.4 Ce qui est prouvé

Essais du 2026-11-05.

- **Keycloak 26.6.2 démarre** en mode développement dans Docker (`started in 47.631s`, puis `50.183s` au second lancement) et sous Windows avec un JDK 21 (`started in 26.456s`), sans ligne `WARN` ni `ERROR` relevée (H2, H3, H10, H12).
- **Le fichier `identity/traceability-realm.json` suffit à reconstruire le realm** `traceability`, ses rôles `reader` et `writer` et le client `traceability-trial`, sans aucun utilisateur, dans les deux modes. Un conteneur supprimé puis recréé réimporte le même fichier (H4, H10, H13).
- **Deux comptes créés à la main, un par rôle, obtiennent un jeton** (`HTTP:200`, `Bearer`, 300 s). Le jeton de `reader-test` contient `reader` et pas `writer`, celui de `writer-test` contient `writer` et pas `reader`, dans `realm_access.roles` (H5 à H7, H13).
- **Un mauvais mot de passe est refusé** : `HTTP:400`, `invalid_grant`, `Invalid user credentials` (H8).
- **Sous Windows, c'est le JDK 21 qui fait tourner Keycloak** (chemin du `java.exe`), le Java 24 reste celui par défaut, et il ne reste aucun processus Java après l'arrêt (H11, H14, H15).
- **Le fichier de réglages ne contient ni mot de passe ni secret** (H16). Les mots de passe de l'administrateur et des deux comptes sont saisis masqués dans PowerShell ou dans la console, et ne sont écrits dans aucun fichier du dépôt.
- **Mémoire** (après les jetons) : 706,3 MiB pour le conteneur et 512,5 MiB pour le processus Java sous Windows ; ce sont deux mesures différentes (H9 et H14).
- **Constats à traiter au lot 10b** (non essayés) : le jeton du rôle `writer` ne contient pas `reader`, donc l'API devra accepter l'un ou l'autre rôle pour consulter, ou les rôles devront être redéfinis ; `aud` vaut `account` et non l'API, donc l'API devra soit exiger un public qui lui est propre, soit ne pas contrôler ce champ ; `iss` n'a été observé qu'avec `http://localhost:8180`.
- Le lot ne modifie ni l'API, ni l'interface, ni la CI, ni la base : seuls `identity/traceability-realm.json` et des documents sont ajoutés.

### 18.5 Rejouer la vérification

Dans PowerShell, depuis la racine du dépôt. Les mots de passe sont saisis masqués et ne sont jamais écrits dans un fichier.

**Dans Docker** (Docker Desktop démarré) :

```powershell
docker pull quay.io/keycloak/keycloak:26.6.2
$env:KC_BOOTSTRAP_ADMIN_PASSWORD = [Net.NetworkCredential]::new('', (Read-Host 'Mot de passe admin Keycloak' -AsSecureString)).Password
docker run -d --name traceability-keycloak -p 127.0.0.1:8180:8080 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD -v "${PWD}\identity\traceability-realm.json:/opt/keycloak/data/import/traceability-realm.json:ro" quay.io/keycloak/keycloak:26.6.2 start-dev --import-realm
```

Attendre environ 2 minutes, puis `docker logs traceability-keycloak` doit contenir `Realm 'traceability' imported` et `started in`. Ouvrir `http://localhost:8180/admin`, se connecter avec `admin`, choisir le realm `traceability` (Manage realms). Créer à la main `reader-test` et `writer-test` (Users, Create new user ; adresse, prénom et nom renseignés ; aucune action requise ; Credentials : mot de passe avec Temporary sur Off ; Role mapping : `reader` ou `writer`). Pour nettoyer : `docker rm -f traceability-keycloak`.

**Sous Windows** (sans installer quoi que ce soit) : télécharger l'archive `.zip` du JDK 21 (Eclipse Temurin, Windows x64, JDK) sur adoptium.net et l'archive `keycloak-26.6.2.zip` sur `https://www.keycloak.org/archive/downloads-26.6.2.html`, puis :

```powershell
$zip = Get-ChildItem "$HOME\Downloads" -Filter "OpenJDK21U-jdk_x64_windows_hotspot_*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
New-Item -ItemType Directory -Force "$HOME\tools" | Out-Null
Expand-Archive -Path $zip.FullName -DestinationPath "$HOME\tools"
$jdk = (Get-ChildItem "$HOME\tools" -Directory -Filter "jdk-21*").FullName
Expand-Archive -Path "$HOME\Downloads\keycloak-26.6.2.zip" -DestinationPath "$HOME\tools"
$kc = "$HOME\tools\keycloak-26.6.2"
New-Item -ItemType Directory -Force "$kc\data\import" | Out-Null
Copy-Item .\identity\traceability-realm.json "$kc\data\import\traceability-realm.json" -Force
$env:KC_BOOTSTRAP_ADMIN_PASSWORD = [Net.NetworkCredential]::new('', (Read-Host 'Mot de passe admin Keycloak' -AsSecureString)).Password
$cmd = "`$env:JAVA_HOME = '$jdk'; `$env:KC_BOOTSTRAP_ADMIN_USERNAME = 'admin'; & '$kc\bin\kc.bat' start-dev --import-realm --http-port=8180 --http-host=127.0.0.1"
Start-Process powershell -ArgumentList "-NoExit -Command `"$cmd`""
```

La commande `Start-Process` ouvre une nouvelle fenêtre où Keycloak démarre (environ 2 minutes) : elle hérite du mot de passe administrateur défini dans la fenêtre d'origine. La suite est la même qu'en Docker (console, deux comptes à créer). Pour arrêter : Ctrl+C dans la fenêtre de Keycloak.

**Obtenir un jeton** (le mot de passe du compte est saisi masqué) :

```powershell
$pw = [Net.NetworkCredential]::new('', (Read-Host 'Mot de passe du compte' -AsSecureString)).Password
curl.exe -s -d "grant_type=password&client_id=traceability-trial&username=reader-test&password=$([uri]::EscapeDataString($pw))" http://localhost:8180/realms/traceability/protocol/openid-connect/token
```

La réponse contient `access_token` : un jeton dont la partie du milieu (entre les deux points) est du JSON codé en base64url. Il se décode et contient `realm_access.roles`. Un jeton brut ne se colle jamais dans un message ni dans un fichier. Un mauvais mot de passe donne `HTTP 400` et `invalid_grant`.

## 19. Lot 10b : l'API vérifie les jetons de Keycloak et applique les rôles

Écrit le 2026-11-07, avant l'essai. Tant que l'essai n'est pas fait, chaque ligne de la liste vaut « À observer ». Il n'y a pas de prédiction chiffrée : chaque ligne se terminera par « Observé » ou « Non observé », avec ce qui a été vu. Le lot 10b modifie l'API et le fichier de réglages de Keycloak ; l'interface (lot 10c), la CI et les scripts SQL ne sont pas touchés.

### 19.1 Ce qui est essayé

- L'API accepte un appel seulement s'il porte un jeton d'accès (en-tête `Authorization: Bearer …`) émis par le realm `traceability` de Keycloak. Sont contrôlés la signature, l'émetteur (`iss`), la date d'expiration (`exp`) et le public visé (`aud`). L'API lit la configuration publique de Keycloak (dont les clés de signature) : elle n'a besoin d'aucun secret.
- Deux variables d'environnement, lues comme `ConnectionStrings__Default` et jamais dans un fichier du dépôt : `Authentication__Authority` (adresse du realm : `http://localhost:8180/realms/traceability`) et `Authentication__Audience` (`traceability-api`).
- Les rôles. Les rôles du jeton sont dans `realm_access.roles` (observé au lot 10a, section 18) ; l'API les transforme en rôles utilisables par ses règles. Les 5 routes de lecture (`GET`) acceptent `reader` ou `writer`, parce que le jeton d'un `writer` ne contient pas `reader` (observé en 18.2, ligne H7). Les 5 routes d'écriture (`POST`) demandent `writer`. Sans jeton valide : 401. Jeton valide sans le bon rôle : 403.
- Le public visé. Un mappeur d'audience est ajouté au client `traceability-trial` dans `identity/traceability-realm.json`, pour que `aud` contienne `traceability-api` (il valait `account` au lot 10a) ; l'API exige ce nom.
- Les tests automatiques utilisent un faux schéma d'authentification : aucun Keycloak, aucun vrai jeton. Ils contrôlent les règles de rôles route par route, pas la vérification d'un vrai jeton. Un test échoue si une route de l'API n'a aucune règle.
- La vérification d'un vrai jeton est essayée à la main avec Keycloak : dans Docker d'abord, puis les contrôles principaux sous Windows. L'API des essais est lancée sur la base `TraceabilityTest`, qui est vidée à chaque exécution des tests d'intégration : aucune donnée à garder n'y est écrite.
- Swagger (Development seulement) déclare le schéma « Bearer » : le bouton Authorize permet d'envoyer un jeton depuis la page.
- Le client d'essai garde le flux « mot de passe direct » (18.1) : il ne sert qu'aux essais à la main.

### 19.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| I1 | `dotnet test Traceability.slnx`, API arrêtée : relever le nombre de tests unitaires et d'intégration et le résultat. Les tests d'intégration existants ne sont pas modifiés ; leur client agit en `writer`. | Observé le 2026-11-07. `dotnet test Traceability.slnx`, API arrêtée : tests unitaires `échec : 0`, `réussite : 89` (75 avant le lot, 14 ajoutés) ; tests d'intégration `échec : 0`, `réussite : 129` (88 avant le lot, 41 ajoutés). Même résultat en fin d'essais, après le nettoyage. La première compilation (`dotnet build`, 0 erreur) signalait un avertissement CS8603 dans `Program.cs` (la liste des opérations du document OpenAPI peut être nulle) : il est corrigé, et les deux exécutions de `dotnet test` n'affichent aucune ligne d'avertissement. |
| I2 | Pour chacune des 10 routes : sans jeton, la réponse est 401 ; avec `reader`, 200 sur une lecture et 403 sur une écriture ; avec `writer`, ni 401 ni 403. Relever les tests qui le contrôlent. | Observé. Les 40 cas de `AuthorizationTests` (10 routes, quatre appelants : sans jeton, `reader`, `writer`, un rôle inconnu `other`) passent. Sans jeton : 401 sur les 10 routes. `reader` : ni 401 ni 403 sur les 5 lectures, 403 sur les 5 écritures. `writer` : ni 401 ni 403 sur les 10 routes. Rôle inconnu : 403 sur les 10 routes. Les cas « ni 401 ni 403 » ne relèvent pas le code exact (codes inexistants et corps vides dans les appels). Le test « chaque route demande une règle » trouve 10 routes de contrôleurs, toutes avec une règle. |
| I3 | Casse volontaire : la règle d'une route est retirée temporairement (puis remise). Le test qui contrôle que chaque route a une règle échoue et nomme la route. Relever le message. | Observé le 2026-11-07. La ligne `[Authorize(Policy = Policies.CanWrite)]` de `POST /farms` est retirée temporairement de `FarmsController.cs`. `AuthorizationTests` : `échec : 4`, `réussite : 37`, `total : 41`. Le test « chaque route demande une règle » échoue : `Assert.Empty() Failure: Collection was not empty`, `Collection: ["Traceability.Api.Controllers.FarmsController.Creat…"]` (nom coupé à l'affichage). Les noms des trois autres tests en échec n'ont pas été relevés. Le fichier est ensuite remis : son empreinte SHA-256 est identique à celle d'avant la casse, et les 10 règles sont de nouveau présentes. |
| I4 | Keycloak est démarré dans Docker avec le fichier de réglages modifié : le journal indique l'import du realm `traceability` et la console montre le mappeur d'audience sur le client `traceability-trial`. | Observé le 2026-11-07, dans Docker (conteneur `traceability-keycloak`, image 26.6.2, fichier de réglages modifié monté en lecture seule). Journal : `Realm 'traceability' imported`, puis `started in 45.513s` ; le filtre sur `imported`, `started in`, `ERROR` et `WARN` n'affiche aucune ligne `ERROR` ni `WARN` à ce relevé. Console (realm `traceability`, Clients, `traceability-trial`, Client scopes, `traceability-trial-dedicated`, onglet Mappers), sur capture : une ligne `traceability-api-audience`, catégorie Token mapper, type Audience, priorité 0. Les comptes `reader-test` et `writer-test` sont recréés à la main (onglet Role mapping, sur captures : `reader` et `default-roles-traceability` pour le premier, `writer` et `default-roles-traceability` pour le second). Plus tard, le journal montre un `WARN` (`LOGIN_ERROR`, `invalid_user_credentials`, `writer-test`, 09:59:47) : une demande de jeton refusée, cause non confirmée. |
| I5 | Contenu décodé d'un jeton de `writer-test` : relever `aud`, `iss`, et vérifier que les rôles sont toujours dans `realm_access.roles`. Le jeton brut n'est jamais affiché. | Observé. Jeton de `writer-test` (`HTTP 200`, `Bearer`, `expires_in 300`, reçu à 09:50:24 UTC), contenu décodé : `iss` `http://localhost:8180/realms/traceability` ; `aud` `traceability-api,account` (il valait `account` au lot 10a) ; `azp` `traceability-trial` ; `exp` moins `iat` : 300 ; rôles dans `realm_access.roles` : `offline_access`, `default-roles-traceability`, `writer`, `uma_authorization` (pas `reader`). Seul le contenu décodé est affiché (fonctions `Get-Trial` et `Show-Token`, 19.5). |
| I6 | L'API est lancée (`--launch-profile https`) avec les deux variables d'environnement, sur la base `TraceabilityTest`. Relever le démarrage et toute erreur. | Observé. `dotnet run --project src/Traceability.Api --launch-profile https`, avec `ConnectionStrings__Default` copiée de `ConnectionStrings__Test` (base `TraceabilityTest`), `Authentication__Authority` et `Authentication__Audience` : `Now listening on: https://localhost:7080`, `Application started`, `Hosting environment: Development`, aucune erreur. |
| I7 | Sans jeton : `GET /farms` répond 401. Relever l'en-tête `WWW-Authenticate`. | Observé. `GET /farms` sans en-tête `Authorization` : `HTTP/1.1 401 Unauthorized`, `Content-Length: 0`, `WWW-Authenticate: Bearer`. |
| I8 | Avec le jeton de `reader-test` : `GET /farms` répond 200. | Observé. Jeton de `reader-test` (reçu à 09:54:51 UTC) : `GET /farms` répond `HTTP 200`. |
| I9 | Avec le jeton de `reader-test` : `POST /farms` répond 403. | Observé. Même jeton : `POST /farms` avec le corps `{}` répond `HTTP 403`. |
| I10 | Avec le jeton de `writer-test` : `GET /farms` répond 200. | Observé. Jeton de `writer-test` (reçu à 09:55:39 UTC) : `GET /farms` répond `HTTP 200`. |
| I11 | Avec le jeton de `writer-test` : `POST /farms` (une nouvelle ferme) répond 201. | Observé. Même jeton : `POST /farms` (`AUTH-I11`, `Auth trial farm`, `Test`) répond `HTTP/1.1 201 Created`, corps `{"code":"AUTH-I11","name":"Auth trial farm","region":"Test"}`. La ferme est écrite dans `TraceabilityTest`. |
| I12 | Un jeton mal formé (`Authorization: Bearer abc`) : relever le code. | Observé. `Authorization: Bearer abc` : `HTTP/1.1 401 Unauthorized`, `WWW-Authenticate: Bearer error="invalid_token"`. |
| I13 | Un jeton dont la date d'expiration est dépassée : relever le code et le temps écoulé depuis la demande du jeton quand le premier refus apparaît. | Observé. Jeton de `writer-test` reçu à 09:55:39 UTC (`expires_in 300`, expiration estimée à 10:00:38). Un sondage en arrière-plan rappelle `GET /farms` avec ce jeton toutes les 15 secondes : `HTTP 200` jusqu'à 10:05:32, premier `HTTP 401` à 10:05:47, soit entre 4 min 54 s et 5 min 09 s après l'expiration estimée. Cet écart est compatible avec la tolérance d'horloge par défaut de la validation (5 minutes), que le code ne modifie pas ; elle n'a été ni lue ni mesurée séparément. |
| I14 | Mauvais émetteur : un jeton demandé à `http://127.0.0.1:8180` au lieu de `http://localhost:8180`. Relever son `iss` et le code de l'API. | Observé. Jeton de `writer-test` demandé à `http://127.0.0.1:8180` : `iss` `http://127.0.0.1:8180/realms/traceability` ; `aud` `traceability-api,account`, `azp`, `exp` moins `iat` (300) et rôle `writer` comme pour les autres jetons ; `GET /farms` avec ce jeton : `HTTP 401`. L'émetteur est le seul champ relevé qui diffère ; la raison du refus n'a pas été lue dans le journal de l'API. |
| I15 | Mauvais public visé : l'API est relancée avec une autre valeur de `Authentication__Audience`, puis appelée avec un jeton valide. Relever le code. | Observé. API relancée avec `Authentication__Audience` égal à `autre-nom`, jeton valide de `writer-test` (reçu à 10:21:05 UTC) : `GET /farms` répond `HTTP 401`. Avec `traceability-api`, des jetons du même type donnent 200 (I8 et I10). La première demande de jeton de cet essai a été refusée (`HTTP 400`, `invalid_grant`) : mot de passe mal saisi. |
| I16 | Keycloak arrêté pendant que l'API tourne : relever la réponse de l'API à un jeton encore valide, déjà utilisé avant l'arrêt. | Observé, avec une sortie manquante. Un jeton valide de `writer-test` est utilisé avant l'arrêt ; `docker stop traceability-keycloak` (`docker ps -a` : `Exited (143)`), puis le même appel avec le même jeton répond `HTTP 200` (résultat rapporté en une ligne ; les sorties des deux appels n'ont pas été collées). Un jeton que l'API n'avait jamais vu n'a pas pu être essayé (Keycloak arrêté). Après `docker start`, Keycloak repart (`started in 18.303s`) et `writer-test` obtient de nouveau un jeton (I15) : les comptes survivent à un arrêt du conteneur. |
| I17 | Swagger (`/swagger`) : le bouton Authorize est présent ; avec un jeton, `GET /farms` répond 200 ; sans jeton, 401. | Observé. Swagger (`https://localhost:7080/swagger`) : le bouton Authorize est présent (constaté à l'écran, sans capture). Avec un jeton de `writer-test` collé dans Authorize : `GET /farms` répond 200, avec la ferme `AUTH-I11` (`totalCount` 1). Après Logout : même appel, code 401, en-tête `www-authenticate: Bearer`. |
| I18 | Sous Windows : relever si le mappeur d'audience est pris en compte (le realm existant est ignoré à l'import, stratégie `IGNORE_EXISTING`, section 18). Puis : sans jeton 401, `reader` sur un `POST` 403, `writer` sur un `POST` 201. | Observé sous Windows (Keycloak 26.6.2, JDK 21). 1) Base de Keycloak du lot 10a conservée : `Realm 'traceability' already exists. Import skipped`, `started in 27.518s` ; `writer-test` (compte conservé) obtient un jeton (`HTTP 200`) avec `aud` `account` seulement : le mappeur n'est pas pris en compte. 2) Dossier `data\h2` supprimé, Keycloak relancé : `Realm 'traceability' imported`, `started in 27.420s` ; comptes recréés à la main. Jeton de `writer-test` : `aud` `traceability-api,account`, `iss` `http://localhost:8180/realms/traceability`, rôle `writer`. Contrôles avec l'API (audience `traceability-api`) : sans jeton, `GET /farms` 401 ; `reader-test`, `POST /farms` 403 ; `writer-test`, `POST /farms` (`AUTH-I18`) `HTTP/1.1 201 Created`. |
| I19 | L'interface web (Vite) avec l'API protégée : relever ce qu'elle affiche pour la liste des fermes. | Observé, sur captures de l'interface (Vite sur `http://localhost:5173`, API protégée) : les pages Lots (`/batches`) et Fermes (`/farms`) affichent « Erreur 401. ». L'interface n'a pas de connexion avant le lot 10c. |
| I20 | Aucun jeton brut ni mot de passe dans les fichiers du dépôt : recherche de `eyJ` (début d'un jeton), de `password` et de `secret` dans les fichiers modifiés par le lot, et dans `identity/traceability-realm.json`. | Observé le 2026-11-07, après les essais. Recherche dans les 14 fichiers du lot à ce moment (modifiés et nouveaux) : `eyJ` n'apparaît que dans le texte de cette ligne I20. `identity/traceability-realm.json` : 0 ligne pour `password`, `secret` et `credentials`. Fichiers de tests : 0 ligne. Code de l'API : une seule ligne, un commentaire de `Program.cs` (« the API needs no secret »). `docs/verification.md` : les mots apparaissent dans du texte (noms de variables, commandes avec saisie masquée) ; à la relecture des lignes, aucune valeur de mot de passe ni de secret. Dans le dépôt, `eyJ` apparaît aussi dans `web/package-lock.json`, que le lot ne modifie pas, à l'intérieur d'une empreinte `integrity` (`sha512-…`). |
| I21 | La CI (`backend`, `frontend`, `docker`) est verte sur la branche, sans modification de `.github/`. Relever les numéros d'exécution. | Observé le 2026-11-09. Sur la branche `feature/lot-10b-api-jetons`, la CI est verte : exécution #56 (événement `push`, commit `dcbf213`, 1 min 1 s) et exécution #57 (événement `pull_request`, PR #21, 52 s). Sur la page de la PR, les six contrôles requis sont réussis (`backend`, `docker` et `frontend`, chacun pour `push` et `pull_request`). Le commit ne modifie aucun fichier de `.github/` (liste des fichiers du commit relue avant le push). Après la fusion (commit `6e16ab9`), l'exécution #58 sur `main` est verte (1 min 5 s). La CI n'utilise aucun vrai jeton : elle ne prouve pas la vérification d'un jeton. |

### 19.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- L'API dans un conteneur Docker avec Keycloak : l'adresse où l'API lit les clés de Keycloak peut différer de l'émetteur attendu quand elle tourne dans un conteneur. Non essayé.
- Le mode production de Keycloak, HTTPS (la lecture de la configuration de Keycloak en HTTP n'est permise qu'en Development), la rotation des clés de signature.
- La révocation d'un jeton avant son expiration, le jeton de rafraîchissement, un jeton sans compte utilisateur.
- Un rôle composite (`writer` qui inclurait `reader`).
- Le flux code d'autorisation avec PKCE, la connexion dans l'interface et l'en-tête `Authorization` dans la règle CORS (lot 10c).
- L'enregistrement de l'auteur de chaque mouvement.
- Une CI avec un vrai Keycloak : les tests automatiques n'utilisent aucun vrai jeton.
- Les routes de l'API ajoutées après ce lot : seul le test qui contrôle que chaque route a une règle les couvre.

**Ajouté après les essais (2026-11-07)**

- La tolérance d'horloge de la validation du jeton (5 minutes par défaut) n'est ni modifiée ni mesurée : le délai relevé en I13 lui est compatible, sans que sa cause soit isolée.
- Keycloak arrêté (I16) : seul un jeton déjà vu par l'API a été essayé. Un jeton que l'API n'avait jamais vu, ou une API démarrée pendant l'arrêt de Keycloak, ne l'ont pas été ; le mécanisme (clés mises en mémoire) n'est pas isolé.
- Sous Windows, un realm déjà présent n'est pas réimporté (I18) : un changement du fichier de réglages n'y est pris en compte qu'après suppression de `data\h2` dans le dossier de Keycloak, ce qui supprime aussi les comptes (à recréer à la main). Dans Docker, le conteneur des essais a été créé avec le fichier modifié.
- I2 ne relève pas le code exact des réponses « ni 401 ni 403 » ; I3 ne relève pas les noms des trois autres tests en échec ; I16 n'a pas les sorties collées des deux appels.
- La raison exacte du refus du jeton à mauvais émetteur (I14) et du jeton à mauvais public visé (I15) n'a pas été lue dans le journal de l'API : seul le code 401 est observé.
- L'interface web affiche « Erreur 401. » tant que le lot 10c n'a pas ajouté la connexion (I19).
- Les fonctions `Get-Trial` et `Show-Token` de 19.5 sont réécrites pour ce document, les versions utilisées pendant les essais n'étant pas gardées. Leur syntaxe a été contrôlée avec l'analyseur de PowerShell le 2026-11-07 (0 erreur) ; elles n'ont pas été exécutées avec Keycloak sous cette forme.

### 19.4 Ce qui est prouvé

Essais du 2026-11-07.

- **Les règles de rôles sont contrôlées route par route** par 41 tests d'intégration avec un faux schéma d'authentification : les 10 routes, avec quatre appelants (sans jeton, `reader`, `writer`, un rôle inconnu). Les 89 tests unitaires et les 129 tests d'intégration passent (I1, I2). Un test échoue si une route de contrôleur n'a aucune règle, ce qui a été vérifié en en retirant une (I3). Ces tests ne vérifient aucun vrai jeton.
- **Avec un vrai jeton de Keycloak (Docker), l'API répond comme prévu** : sans jeton 401 avec `WWW-Authenticate: Bearer` ; `reader` 200 sur une lecture et 403 sur une écriture ; `writer` 200 sur une lecture et 201 sur une écriture ; jeton mal formé 401 (I7 à I12). Les rôles sont donc bien lus dans `realm_access.roles` d'un vrai jeton.
- **Le public visé est fourni par le realm et contrôlé par l'API** : `aud` vaut `traceability-api,account` avec le mappeur ajouté (il valait `account` au lot 10a), et l'API configurée avec un autre nom de public refuse le même jeton (I5, I15).
- **L'émetteur est contrôlé** : un jeton demandé à `http://127.0.0.1:8180` (seul son `iss` diffère parmi les champs relevés) est refusé en 401 (I14).
- **L'expiration est contrôlée** : un jeton de 300 s est encore accepté après son expiration puis refusé, le premier 401 apparaissant 4 min 54 s à 5 min 09 s après l'expiration estimée (I13).
- **Swagger** propose le bouton Authorize : avec un jeton, `GET /farms` répond 200 ; après Logout, 401 (I17).
- **Sous Windows**, un realm existant n'est pas réimporté, donc le mappeur d'audience n'y est pas pris en compte tant que la base de Keycloak n'est pas supprimée ; après suppression de `data\h2` et réimport, `aud` contient `traceability-api` et les contrôles principaux donnent 401, 403 et 201 (I18).
- **Keycloak arrêté** : un jeton valide déjà utilisé reste accepté (200) (I16).
- **Aucun jeton brut ni mot de passe dans les fichiers du lot** relevés lors de la recherche (I20) ; le fichier de réglages de Keycloak ne contient ni mot de passe ni secret.
- Le lot ne modifie ni l'interface web ni la CI (`.github/`).
- **La CI est verte sur la branche** (I21, exécutions #56 et #57, relevées le 2026-11-09). Elle n'utilise aucun vrai jeton.
- **Non prouvé** : tout ce qui figure en 19.3, dont la cause du délai de 5 minutes (I13) et le mécanisme du cas Keycloak arrêté (I16).

### 19.5 Rejouer la vérification

Dans PowerShell. Les mots de passe sont saisis masqués ; un jeton n'est jamais affiché en entier, ni collé dans un message ou un fichier. Fenêtres conseillées : `Docker` (Keycloak), `Essais` (jetons et appels), `API` (l'API).

**1. Tests automatiques** (depuis la racine du dépôt, API arrêtée, `ConnectionStrings__Test` définie comme aux sections précédentes) :

```powershell
dotnet test Traceability.slnx
```

**2. Keycloak** avec le fichier de réglages modifié : voir 18.5 (Docker ou Windows). Un conteneur ou un dossier de Keycloak créés avant le lot 10b n'ont pas le mappeur d'audience : supprimer le conteneur (`docker rm -f traceability-keycloak`) ou, sous Windows, arrêter Keycloak, supprimer `$kc\data\h2` (les comptes sont supprimés aussi), recopier `identity\traceability-realm.json` dans `$kc\data\import`, relancer. Puis créer à la main `reader-test` et `writer-test` (18.5).

**3. L'API**, dans la fenêtre `API`, depuis la racine du dépôt :

```powershell
$env:ConnectionStrings__Default = $env:ConnectionStrings__Test
$env:Authentication__Authority = 'http://localhost:8180/realms/traceability'
$env:Authentication__Audience = 'traceability-api'
dotnet run --project src/Traceability.Api --launch-profile https
```

**4. Deux fonctions d'aide**, dans la fenêtre `Essais` (elles n'affichent jamais le jeton) :

```powershell
function Get-Trial($User, $Base = 'http://localhost:8180') {
  $pw = [Net.NetworkCredential]::new('', (Read-Host "Mot de passe de $User" -AsSecureString)).Password
  $r = curl.exe -s -w "`n%{http_code}" -d "grant_type=password&client_id=traceability-trial&username=$User&password=$([uri]::EscapeDataString($pw))" "$Base/realms/traceability/protocol/openid-connect/token"
  $code = $r[-1]
  if ($code -eq '200') {
    $j = $r[0] | ConvertFrom-Json
    $global:Token = $j.access_token
    "HTTP $code $($j.token_type) expires_in $($j.expires_in)"
  } else { "HTTP $code" }
}

function Show-Token {
  $p = $global:Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
  $p = $p.PadRight($p.Length + (4 - $p.Length % 4) % 4, '=')
  $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
  [pscustomobject]@{
    iss = $c.iss; aud = ($c.aud -join ','); azp = $c.azp
    exp_moins_iat = $c.exp - $c.iat
    exp_utc = [DateTimeOffset]::FromUnixTimeSeconds($c.exp).UtcDateTime.ToString('HH:mm:ss')
    roles = ($c.realm_access.roles -join ',')
  } | Format-List
}
```

**5. Les appels** (`--ssl-no-revoke` : le certificat de développement de l'API n'a pas de liste de révocation) :

```powershell
# sans jeton : 401 et WWW-Authenticate: Bearer
curl.exe -s --ssl-no-revoke -i https://localhost:7080/farms

# jeton de lecture : GET 200, POST 403
Get-Trial reader-test
Show-Token
curl.exe -s --ssl-no-revoke -o NUL -w "HTTP %{http_code}`n" -H "Authorization: Bearer $global:Token" https://localhost:7080/farms
'{"code":"AUTH-REJEU","name":"Auth trial farm","region":"Test"}' | Set-Content -Encoding ascii "$env:TEMP\farm.json"
curl.exe -s --ssl-no-revoke -o NUL -w "HTTP %{http_code}`n" -X POST -H "Authorization: Bearer $global:Token" -H "Content-Type: application/json" -d "@$env:TEMP\farm.json" https://localhost:7080/farms

# jeton d'écriture : GET 200, POST 201 (la ferme est écrite dans TraceabilityTest)
Get-Trial writer-test
curl.exe -s --ssl-no-revoke -o NUL -w "HTTP %{http_code}`n" -X POST -H "Authorization: Bearer $global:Token" -H "Content-Type: application/json" -d "@$env:TEMP\farm.json" https://localhost:7080/farms

# jeton mal formé : 401, error="invalid_token"
curl.exe -s --ssl-no-revoke -i -H "Authorization: Bearer abc" https://localhost:7080/farms

# mauvais émetteur : jeton demandé à 127.0.0.1, puis GET /farms (401 attendu)
Get-Trial writer-test http://127.0.0.1:8180
Show-Token
curl.exe -s --ssl-no-revoke -o NUL -w "HTTP %{http_code}`n" -H "Authorization: Bearer $global:Token" https://localhost:7080/farms
```

Un jeton demandé à `http://localhost:8180` après ces essais redevient accepté. Une ferme `AUTH-REJEU` déjà présente donne un conflit au deuxième `POST` (changer le code) ; la base `TraceabilityTest` est vidée à chaque exécution des tests d'intégration.

**6. Expiration** : avec un jeton de `writer-test` tout juste obtenu, un sondage toutes les 15 secondes jusqu'au premier 401 (compter environ 10 minutes) :

```powershell
$global:Poll = Start-Job -ArgumentList $global:Token -ScriptBlock {
  param($t)
  while ($true) {
    $c = curl.exe -s --ssl-no-revoke -o NUL -w "%{http_code}" -H "Authorization: Bearer $t" https://localhost:7080/farms
    "$(Get-Date -Format HH:mm:ss) $c"
    if ($c -eq '401') { break }
    Start-Sleep 15
  }
}
$global:Poll.State; Receive-Job $global:Poll -Keep
```

**7. Mauvais public visé** : arrêter l'API (Ctrl+C), définir `$env:Authentication__Audience = 'autre-nom'`, relancer l'API, obtenir un jeton valide, `GET /farms` doit répondre 401 ; remettre `traceability-api`.

**8. Keycloak arrêté** : obtenir un jeton, appeler `GET /farms` (200), puis `docker stop traceability-keycloak` et rappeler avec le même jeton. Relancer avec `docker start traceability-keycloak`.

**9. Swagger** : ouvrir `https://localhost:7080/swagger`, bouton Authorize, coller le jeton seul (`$global:Token | Set-Clipboard` le met dans le presse-papiers sans l'afficher), puis essayer `GET /farms` ; Logout, puis réessayer (401).

**10. Aucun secret dans les fichiers**, depuis la racine du dépôt :

```powershell
git grep -n --untracked "eyJ"
git grep -n --untracked -i "password" -- identity
```

Le premier ne doit montrer, hors de `web/package-lock.json` (empreintes `sha512-`), que du texte de ce document ; le second ne doit rien montrer.

**11. CI** (I21) : une fois la branche poussée, les trois contrôles `backend`, `frontend` et `docker` doivent être verts sur la branche.

## 20. Lot 10c : la connexion dans l'interface web

Écrit le 2026-11-09, avant l'essai à la main. Tant que l'essai n'est pas fait, chaque ligne de la liste vaut « À observer », sauf J1 et J2, déjà observées. Il n'y a pas de prédiction chiffrée : chaque ligne se terminera par « Observé » ou « Non observé », avec ce qui a été vu. Le lot 10c modifie l'interface, le fichier de réglages de Keycloak et la règle CORS de l'API ; la CI, les scripts SQL et le Dockerfile ne sont pas touchés.

### 20.1 Ce qui est essayé

- La connexion de l'utilisateur dans l'interface, avec le flux code d'autorisation et PKCE (méthode S256), par la bibliothèque `oidc-client-ts` 3.5.0 (Node 18 ou plus). Le flux « mot de passe direct » n'est jamais utilisé par l'interface.
- Un client Keycloak propre à l'interface, `traceability-web`, dans `identity/traceability-realm.json` : public, flux standard activé, flux « mot de passe direct » désactivé, adresse de retour `http://localhost:5173/auth/callback`, origine `http://localhost:5173`, PKCE exigé, même mappeur d'audience que `traceability-trial` (`aud` contient `traceability-api`).
- Un écran de connexion à un seul bouton : tant que personne n'est connecté, l'interface n'appelle pas l'API. Le bouton envoie l'utilisateur à Keycloak ; la page `/auth/callback` reçoit son retour.
- Le jeton est gardé en mémoire seulement (aucun `localStorage` ni `sessionStorage` pour l'utilisateur et ses jetons) : recharger la page déconnecte. La bibliothèque garde pendant la redirection, dans le `localStorage`, l'état de la demande de connexion (réglage par défaut de la bibliothèque).
- Le renouvellement automatique de la bibliothèque, réglé à son défaut : une minute avant l'expiration du jeton, qui dure 300 secondes.
- L'interface envoie `Authorization: Bearer …` à l'API (un seul endroit : `web/src/api/client.ts`). La règle CORS de l'API (Development seulement) accepte en plus l'en-tête `Authorization`.
- Les rôles, lus dans la charge utile du jeton (`realm_access.roles`) sans en vérifier la signature : seule l'API la vérifie et décide. Un utilisateur sans le rôle `writer` ne voit ni les boutons ni les formulaires d'écriture, et les pages `/new-farm`, `/new-batch` et `/new-station` affichent un message à leur place. Ce masquage est un confort : l'API refuse l'écriture (403) quoi que fasse l'interface.
- Deux messages en français : 401 (connexion absente ou expirée) et 403 (droit insuffisant).
- Les tests automatiques simulent l'utilisateur connecté (aucun Keycloak, aucune bibliothèque réelle) : ils contrôlent ce que l'interface fait d'un `reader`, d'un `writer` ou de personne, pas le flux PKCE. Un test C# contrôle que l'API accepte `Authorization` dans la pré-vérification CORS.
- La vraie connexion est essayée à la main avec Keycloak : dans Docker d'abord, puis les contrôles principaux sous Windows. L'API des essais est lancée sur la base `TraceabilityTest`.

### 20.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| J1 | Depuis `web/` : `npm run lint`, `npm run build` et `npm test`. Relever les résultats. | Observé le 2026-11-09. `npm run lint` : 0 avertissement, 0 erreur (85 fichiers). `npm run build` : 73 modules, construit en 1,12 s, aucune erreur de type. `npm test` : 27 fichiers et 248 tests passés (178 avant le lot, 70 ajoutés). |
| J2 | `dotnet test Traceability.slnx`, API arrêtée : relever le nombre de tests et le résultat. | Observé le 2026-11-09. Tests unitaires : `échec : 0`, `réussite : 89` (inchangés). Tests d'intégration : `échec : 0`, `réussite : 130` (129 avant le lot, 1 test CORS ajouté). Une première exécution a été interrompue par Ctrl+C après une erreur non relevée ; la seconde est allée au bout. |
| J3 | Casse volontaire : `Authorization` est retiré temporairement de la règle CORS de `Program.cs` (puis remis). Le test de la pré-vérification avec `Authorization` échoue. Relever le message et vérifier que le fichier remis est identique (empreinte SHA-256). | Observé le 2026-11-09. `Authorization` retiré de `.WithHeaders(...)` dans `Program.cs`. `dotnet test tests/Traceability.IntegrationTests --filter "FullyQualifiedName~CorsTests"` : `échec : 1`, `réussite : 8`, `total : 9`. L'échec est `A_preflight_for_GET_with_Authorization_allows_both`, à la ligne 110 de `CorsTests.cs` (la liste `Access-Control-Allow-Headers` ne contient plus `authorization` ; l'origine et la méthode passent). Fichier remis : empreinte SHA-256 identique à celle d'avant la casse. |
| J4 | Keycloak est démarré dans Docker avec le fichier de réglages modifié : le journal indique l'import du realm `traceability` ; la console montre le client `traceability-web` avec ses réglages (public, flux standard, mot de passe direct désactivé, PKCE S256, adresse de retour, origine, mappeur d'audience). | Observé le 2026-11-09, dans Docker (conteneur `traceability-keycloak`, image 26.6.2, fichier de réglages monté en lecture seule). Journal : `Realm 'traceability' imported`, `Keycloak 26.6.2 on JVM (powered by Quarkus 3.33.1.1) started in 54.621s`, aucune ligne `ERROR`. Console, sur captures : le client `traceability-web` a pour adresse de retour `http://localhost:5173/auth/callback`, pour adresse de retour après déconnexion `http://localhost:5173/` et pour origine `http://localhost:5173` ; Client authentication est sur Off, Standard flow est coché, Direct access grants et Implicit flow sont décochés ; Require PKCE est sur On, méthode S256. Le mappeur `traceability-api-audience` (catégorie Token mapper, type Audience) est listé dans `traceability-web-dedicated` ; son champ `Included Custom Audience` n'a pas été ouvert. Comptes créés à la main dans la console : `reader-test` (rôle `reader`, capture), `writer-test` (rôle `writer`, capture) et `norole-test` (rôles par défaut seulement, rapporté sans capture), ce dernier pour J18. |
| J5 | L'API est lancée (`--launch-profile https`) avec ses trois variables d'environnement sur la base `TraceabilityTest`, et l'interface avec `npm run dev`. Relever le démarrage et toute erreur. | Observé le 2026-11-09. API : `dotnet run --project src/Traceability.Api --launch-profile https`, avec `ConnectionStrings__Default` copiée de `ConnectionStrings__Test` (base `TraceabilityTest`), `Authentication__Authority` et `Authentication__Audience` : `Now listening on: https://localhost:7080`, `Hosting environment: Development`, aucune erreur. Interface : `npm run dev` : `VITE v8.3.5 ready in 1492 ms`, `http://localhost:5173/` ; Vite signale qu'il réoptimise ses dépendances parce que le fichier de verrouillage a changé. |
| J6 | Dans le navigateur, sans être connecté, ouvrir `http://localhost:5173/` : l'écran « Connexion » avec son bouton s'affiche ; l'onglet Réseau ne montre aucun appel vers l'API. | Observé le 2026-11-09, dans Chrome, sur captures. Sans être connecté, `http://localhost:5173/` affiche la page « Connexion » avec son texte et le bouton « Se connecter », sans barre de navigation ni liste. Onglet Réseau, filtre Fetch/XHR : liste vide, aucun appel de données (ni vers l'API, ni vers Keycloak). |
| J7 | Ouvrir à la main `http://localhost:5173/auth/callback` (sans code) : l'interface dit que la connexion a échoué et propose le retour à l'accueil. | Observé le 2026-11-09, sur captures. Adresse `http://localhost:5173/auth/callback` ouverte à la main dans un nouvel onglet de la fenêtre privée, sans être connecté : un cadre rouge affiche « La connexion a échoué. » avec le lien « Retour à l'accueil ». Un clic sur ce lien mène à `localhost:5173` avec l'écran « Connexion ». |
| J8 | Cliquer « Se connecter » : le navigateur arrive sur la page de Keycloak ; relever dans l'adresse `client_id`, `response_type`, `code_challenge_method` et la présence de `code_challenge` (sans en copier la valeur). | Observé le 2026-11-09. Le clic sur « Se connecter » amène le navigateur à l'adresse `http://localhost:8180/realms/traceability/protocol/openid-connect/auth` avec `client_id=traceability-web`, `redirect_uri` égal à `http://localhost:5173/auth/callback`, `response_type=code`, `scope=openid profile`, un `state`, un `code_challenge` et `code_challenge_method=S256` (les valeurs de `state` et de `code_challenge` ne sont pas consignées). |
| J9 | Se connecter avec `writer-test` : retour sur l'interface, la page Lots affiche sa liste (pas « Erreur 401. »), le nom de l'utilisateur est dans l'en-tête, les boutons « Nouveau lot », « Nouvelle ferme » et « Nouvelle station » sont présents. | Observé le 2026-11-09, sur captures. Connexion avec `writer-test` sur la page de Keycloak : retour sur l'interface, la page Lots affiche « Aucun lot enregistré. » (la base `TraceabilityTest` est vide) et non « Erreur 401. » ; la barre du haut montre `writer-test` et « Se déconnecter » ; le bouton « Nouveau lot » est présent. Onglet Réseau (Fetch/XHR) : `openid-configuration` 200, `token` 200 (lancé par `AuthCallbackPage`), un appel `batches` annulé puis un appel `batches` 200 ; l'annulation est attribuée au double déclenchement des effets de React en développement (non isolé). Page Fermes (capture) : la liste affiche une ferme (code préfixé `ZT-`, « Test farm », « Region A », laissée dans `TraceabilityTest` par le dernier `dotnet test`), avec le bouton « Nouvelle ferme ». Page Stations (capture, prise plus tard sous le Keycloak de Windows, voir J20) : en `writer-test`, le bouton « Nouvelle station » est présent. |
| J10 | Onglet Réseau : un appel vers l'API porte l'en-tête `Authorization: Bearer …` (le jeton n'est pas copié) ; relever le code de la pré-vérification (`OPTIONS`) qui le précède. | Observé le 2026-11-09, sur captures. L'appel `batches?pageNumber=1&pageSize=15` (type fetch, 200) porte l'en-tête `Authorization` dont la valeur commence par `Bearer` (le jeton n'est pas consigné). Il est précédé d'une ligne `batches?pageNumber=1&pageSize=15` de type `preflight`, statut 204. |
| J11 | Connecté en `writer-test` : créer une ferme depuis l'interface ; elle apparaît dans la liste. | Observé le 2026-11-09, sur captures. Formulaire « Nouvelle ferme » rempli avec le code `AUTH-J11`, le nom `Ferme essai J11 10c` et la région `Souss` : l'interface affiche « Ferme AUTH-J11 créée. » avec le lien « Voir les fermes ». La liste des fermes montre alors deux fermes (« Page 1 sur 1 · 2 au total ») : la ferme `ZT-…` déjà présente et `AUTH-J11`, `Ferme essai J11 10c`, `Souss`. La ferme est écrite dans `TraceabilityTest`. |
| J12 | Après la connexion, dans les outils du navigateur (Application) : relever les clés présentes dans le `localStorage` et le `sessionStorage` (sans copier de valeur) ; aucune ne contient le jeton ou l'utilisateur. | Observé le 2026-11-09, avec trois commandes dans la console de Chrome (fenêtre privée) qui n'affichent que des noms de clés ou un booléen. Après une connexion : `sessionStorage` vide ; `localStorage` avec deux clés `oidc.…` (type de demande `si:r`, créées la même seconde, champs `id, created, request_type, code_verifier, authority, client_id, redirect_uri, scope, extraTokenParams`) ; recherche de `eyJ` dans toutes les valeurs : `false` (aucun jeton stocké). Deuxième essai, dans une nouvelle fenêtre privée : 0 clé avant le clic sur « Se connecter », 1 clé après le clic (sans se connecter), puis 0 clé après une connexion complète : l'entrée n'existe que le temps du passage chez Keycloak. Les deux entrées du premier essai ne sont pas expliquées (un double clic non intentionnel est possible, non prouvé) ; aucune conséquence constatée. |
| J13 | Recharger la page (F5) : relever ce qui s'affiche (écran de connexion attendu) et si Keycloak reconnaît l'utilisateur sans redemander le mot de passe. | Observé le 2026-11-09, dans Chrome (fenêtre privée), rapporté sans capture. Après F5 : l'écran « Connexion » avec le bouton « Se connecter » (le jeton n'était qu'en mémoire). Un clic sur « Se connecter » ramène directement dans l'interface, sans redemander le mot de passe : Keycloak a gardé sa propre session. |
| J14 | Rester connecté plus de 5 minutes sans recharger : une liste rechargée après ce délai répond sans 401. Relever par quel moyen le jeton est renouvelé (demande vers `/token` avec un jeton de rafraîchissement, ou page cachée). Si le renouvellement échoue, relever ce qui s'affiche. | Observé le 2026-11-09, sur captures. Connexion vers 17:24, onglet Réseau avec « Keep log », liste vidée à 17:27, page jamais rechargée. Filtre `openid-connect/token` : une ligne `token` (fetch, 200, 191 ms) à 17:28, une seconde (fetch, 200, 96 ms) à 17:32, soit 4 minutes d'écart. Avec le filtre plus large `openid-connect`, ces deux lignes sont les seules : aucun appel `auth?…` (pas de page cachée). Le jeton de départ (5 minutes) était expiré depuis environ 17:29 : l'utilisateur est resté connecté et la liste des fermes s'est affichée normalement (2 fermes), avec le jeton renouvelé. Le moyen est donc un appel à `/token` sans page cachée ; qu'il s'agisse d'un jeton de rafraîchissement est déduit et non lu (le contenu des requêtes n'a pas été ouvert, il contient des jetons). La colonne Initiator de ces lignes indique `AuthCallbackPage.tsx:21` ; non expliqué, non étudié. |
| J15 | Cliquer « Se déconnecter » : retour sur l'écran de connexion ; se reconnecter redemande le mot de passe à Keycloak. | Observé le 2026-11-09, sur captures. « Se déconnecter » : onglet Réseau, une ligne `logout?id_token_hint=…` de type document, statut 302, 371 ms (la valeur du paramètre n'est pas consignée), puis retour sur `localhost:5173` avec l'écran « Connexion » ; la page de Keycloak n'a pas été vue pendant le passage (trop rapide). Un clic sur « Se connecter » affiche la page de Keycloak qui demande l'identifiant et le mot de passe (appel `auth?client_id=traceability-web…`, 200). |
| J16 | Se connecter avec `reader-test` : les listes (Lots, Fermes, Stations) se chargent ; aucun bouton d'écriture ; une fiche station sans formulaire de fonction ; une fiche lot sans « Ajouter un mouvement ». | Observé le 2026-11-09, sur captures. Connexion avec `reader-test` : l'en-tête montre `reader-test` ; la page Fermes (capture) affiche sa liste (2 fermes) sans bouton « Nouvelle ferme ». Lots et Stations : aucun bouton « Nouveau » ou « Nouvelle » (rapporté, sans capture ; chargement des listes non relevé). Fiches vues plus tard sous le Keycloak de Windows (voir J20), avec `reader-test` : la fiche du lot `LOT-J20` affiche ses informations et son parcours (Réception à `ST-J20`, 100,00 kg, 09/11/2026 18:43:00 UTC) sans bloc « Ajouter un mouvement » ; la fiche de la station `ST-J20` affiche la fonction Réception sans formulaire « Fonction à ajouter ». La page Stations (capture) n'a pas de bouton « Nouvelle station ». |
| J17 | Connecté en `reader-test`, ouvrir à la main `http://localhost:5173/new-farm` : le message de droit insuffisant s'affiche, sans formulaire. | Observé le 2026-11-09, sur capture. Connecté en `reader-test`, passage à `/new-farm` sans recharger la page (commande `history.pushState` suivie d'un événement `popstate` dans la console, car une adresse tapée dans la barre rechargerait la page et ferait perdre le jeton en mémoire) : l'adresse devient `localhost:5173/new-farm` et la page affiche « Vous n'avez pas le droit de saisir des données. », sans formulaire. |
| J18 | Se connecter avec un compte sans rôle `reader` ni `writer` (créé à la main dans la console, mot de passe saisi dans la console) : les listes affichent le message du 403 de l'API. | Observé le 2026-11-09, sur captures. Connexion avec `norole-test` (compte sans rôle `reader` ni `writer`) : les pages Lots, Fermes et Stations affichent toutes « Vous n'avez pas le droit de faire cela. » à la place des listes. La console montre les appels `GET …/batches`, `…/farms` et `…/stations` (`?pageNumber=1&pageSize=15`) en `403 (Forbidden)`, tous attribués à `client.ts:86`. |
| J19 | Keycloak arrêté, cliquer « Se connecter » : l'interface dit que le serveur de connexion est injoignable et reste sur l'écran de connexion. | Observé le 2026-11-09, sur captures. Après « Se déconnecter », conteneur arrêté par `docker stop traceability-keycloak`, puis clic sur « Se connecter » : l'écran « Connexion » affiche en rouge « Impossible de joindre le serveur de connexion. Est-il lancé ? » au-dessus de son texte habituel et l'application reste en place. Console : `GET http://localhost:8180/realms/traceability/.well-known/openid-configuration net::ERR_CONNECTION_REFUSED`. Relance par `docker start traceability-keycloak` (`started in 21.938s`) ; sans recharger la page, « Se connecter » affiche de nouveau la page de Keycloak. Journal du conteneur : `Realm 'traceability' already exists. Import skipped` à 17:07:59 et 17:41:48 (les deux redémarrages n'ont pas réimporté le fichier de réglages : les comptes créés à la main sont restés). |
| J20 | Sous Windows (Keycloak 26.6.2, JDK 21, `data\h2` supprimé pour réimporter le fichier de réglages) : se connecter avec `writer-test` (J9) puis `reader-test` (J16). | Observé le 2026-11-09, sur captures. Conteneur Docker arrêté (`docker stop`), puis dans `$HOME\tools\keycloak-26.6.2` : aucun processus Java en cours, `data\h2` supprimé, fichier de réglages recopié dans `data\import` (empreintes SHA-256 identiques à celle du fichier du dépôt, `CBD224EC…`). Démarrage avec le JDK 21 : journal `Realm 'traceability' imported`, `Import finished successfully`, `Created temporary admin user with username admin`, `Bootstrap completed in 25.499000 seconds`, `Keycloak 26.6.2 on JVM (powered by Quarkus 3.33.1.1) started in 43.592s. Listening on: http://127.0.0.1:8180`. Console (capture) : 8 clients, dont `traceability-web` et `traceability-trial`. Comptes `writer-test` et `reader-test` recréés à la main (rapporté, sans capture). API relancée pour reprendre les clés de signature de la base neuve. Dans une nouvelle fenêtre privée : `writer-test` arrive dans l'interface (nom en en-tête), Lots affiche « Aucun lot enregistré. » avec « Nouveau lot », Fermes affiche les 2 fermes avec « Nouvelle ferme » ; `reader-test` : Lots sans « Nouveau lot », Fermes avec les 2 fermes et sans « Nouvelle ferme », Stations (capture) avec « Aucune station enregistrée. » et sans « Nouvelle station ». Stations en `writer-test` : bouton « Nouvelle station » présent (capture). Écritures faites en `writer-test` sous Windows : station `ST-J20` (« Station test J20 lot 10c ») créée, fonction Réception ajoutée (« Fonction Réception ajoutée. »), lot `LOT-J20` créé (ferme `AUTH-J11`, Gala, récolte 08/11/2026, 100 kg, réception à `ST-J20`), le tout laissé dans `TraceabilityTest`. En `reader-test`, la fiche du lot `LOT-J20` n'a pas de bloc « Ajouter un mouvement » et la fiche de la station `ST-J20` n'a pas de formulaire de fonction (captures). |
| J21 | Aucun jeton brut ni mot de passe dans les fichiers du lot : recherche de `eyJ`, de `password` et de `secret` dans les fichiers modifiés ou nouveaux, et dans `identity/traceability-realm.json`. | Observé le 2026-11-09, sur le dépôt local, avant le commit. Recherche dans les 37 fichiers modifiés ou nouveaux (`git status`, fichiers non suivis inclus), puis dans `identity/traceability-realm.json`. `eyJ` : une ligne de `web/package-lock.json` (l'intérieur d'une empreinte `integrity` en `sha512-…`, pas un jeton) et du texte de `docs/verification.md` (les lignes qui décrivent cette recherche) ; rien dans le code, les tests ni le fichier de réglages. `password` : uniquement dans `docs/verification.md`, dans du texte des lots précédents (noms de variables, commandes avec saisie masquée, `grant_type=password` des essais) ; rien dans le code, les tests ni le fichier de réglages. `secret` : `docs/verification.md` (texte), un commentaire de `Program.cs` (« the API needs no secret ») et deux commentaires de `web/src/config.ts` (« never put a secret in a VITE_ variable », « there is no secret ») ; rien dans les tests ni le fichier de réglages. `identity/traceability-realm.json` : 0 ligne pour `eyJ`, `password` et `secret`. Les lignes de `docs/verification.md` ont été relues à l'écran coupées à 220 caractères : aucune valeur de mot de passe ni de secret n'y a été vue. |
| J22 | La CI (`backend`, `frontend`, `docker`) est verte sur la branche, sans modification de `.github/`. Relever les numéros d'exécution. | Observé le 2026-11-09, sur GitHub (onglet Actions et page de la pull request n° 23, captures). Branche poussée : exécution CI n° 62 (événement `push`, commit `baa518a`, 57 s) et n° 63 (événement `pull_request`, 1 min 10 s). Sur la pull request, 6 contrôles réussis, tous « Required » : `backend` (1 min en `pull_request`, 53 s en `push`), `docker` (23 s et 29 s), `frontend` (27 s et 21 s). Après la fusion (commit `8792943`), exécution CI n° 64 sur `main` (événement `push`), réussie en 1 min 9 s. Le lot ne modifie pas `.github/` (`git status` avant le commit). Le détail des étapes n'a pas été ouvert. |
| J23 | Casse volontaire de l'interface, sur une copie de `web/` hors du dépôt : `canWrite` (`web/src/auth/roles.ts`) renvoie toujours vrai. Les tests de l'interface doivent échouer ; relever le nombre. | Observé le 2026-11-09, sur une copie de `web/` installée avec `npm ci` (Node 22.23.4, sous Linux : pas sur le PC de développement) ; le dépôt n'est pas touché. Avant la casse : 27 fichiers, 248 tests passés. Avec `canWrite` toujours vrai : `Test Files  3 failed | 24 passed (27)`, `Tests  19 failed | 229 passed (248)` ; échecs dans `App.auth.test.tsx` (16), `WriterOnly.test.tsx` (2) et `roles.test.ts` (1), dont « is false for a reader, for another role and for no role ». Fichier remis à l'identique (comparé avec `diff`). |
| J24 | Casse volontaire de l'interface, sur la même copie : le client n'ajoute plus l'en-tête `Authorization` (`withAuthorization` de `web/src/api/client.ts` renvoie les en-têtes sans le jeton). Les tests du client doivent échouer ; relever lesquels. | Observé le 2026-11-09, même copie et même environnement que J23. `Test Files  1 failed | 26 passed (27)`, `Tests  2 failed | 246 passed (248)` ; les deux échecs sont dans `client.test.ts` : « sends the token of the signed-in user with a read and with a write » et « sends the new token after a renewal, and none after a sign-out ». La copie n'a pas été remise à l'identique après cette casse (elle est jetée) ; le dépôt n'est pas touché. |

### 20.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- Le mode production de Keycloak, HTTPS, une interface servie autrement que par le serveur de développement Vite (`npm run preview`, construction de production).
- Un seul navigateur est utilisé (relevé à l'essai) ; pas de téléphone, pas de test d'interface avec un vrai navigateur automatisé.
- Plusieurs onglets ouverts en même temps.
- Un renouvellement qui échoue pendant une session (Keycloak arrêté après la connexion), un jeton expiré non renouvelé.
- Un rôle retiré ou ajouté dans Keycloak pendant une session (le changement est attendu au prochain jeton, non vérifié).
- La déconnexion quand Keycloak est injoignable (l'interface retire alors seulement la connexion locale).
- Le retour à la page demandée avant la connexion : après la connexion, l'interface va toujours à l'accueil.
- L'enregistrement de l'auteur de chaque mouvement.
- Le client `traceability-trial` garde le flux « mot de passe direct » (essais à la main seulement).
**Ajouté après les essais (2026-11-09)**

- Les deux entrées `oidc.…` du `localStorage` relevées au premier essai de J12 ne sont pas expliquées (un double clic non intentionnel est possible, non prouvé). Un second essai, dans une nouvelle fenêtre privée, n'en montre qu'une après le clic (sans se connecter), puis aucune après une connexion complète. Aucune n'a contenu de jeton.
- Le moyen du renouvellement (J14) est déduit, pas lu : deux appels `token` (17:28 et 17:32) et aucun appel `auth?…` ; le contenu des requêtes n'a pas été ouvert (il contient des jetons), donc qu'il s'agisse d'un jeton de rafraîchissement n'est pas constaté. La colonne Initiator de ces appels indique `AuthCallbackPage.tsx:21` ; non expliqué, non étudié.
- J13 est rapporté sans capture. En J15, la page de Keycloak n'a pas été vue pendant la déconnexion (retour trop rapide), seul l'appel `logout` en 302 l'est.
- J16 sous Docker : les pages Lots et Stations sont rapportées sans capture ; les fiches lot et station en lecteur ont été vues plus tard, sous Windows (J20).
- Sous Windows (J20), seuls la connexion, les listes et trois écritures sont essayées : ni renouvellement, ni déconnexion, ni Keycloak arrêté.
- Les casses volontaires de l'interface (J23 et J24) sont faites sur une copie de `web/` sous Linux, pas sur le PC de développement ; la casse de la règle CORS (J3) est faite dans le dépôt, avec contrôle de l'empreinte.
- Les trois comptes de Keycloak sont créés à la main, mots de passe jamais consignés ; `norole-test` et, sous Windows, `writer-test` et `reader-test` sont rapportés sans capture.
- L'essai laisse des données dans la base `TraceabilityTest` : la ferme `ZT-…` (d'un `dotnet test`), la ferme `AUTH-J11`, la station `ST-J20` avec la fonction Réception et le lot `LOT-J20`.
- La CI (J22) a été relevée après le push, dans une pull request de suivi ; elle n'utilise ni Keycloak ni vrai jeton, et le détail de ses étapes n'a pas été ouvert.

### 20.4 Ce qui est prouvé

Essais du 2026-11-09.

- **Les tests automatiques passent et détectent les casses essayées** : 248 tests de l'interface (178 avant le lot, 70 ajoutés), 89 tests unitaires et 130 d'intégration en C# (J1, J2). Le test de la pré-vérification CORS avec `Authorization` échoue quand l'en-tête est retiré de la règle (J3). Avec `canWrite` toujours vrai, 19 tests de l'interface échouent ; avec l'en-tête `Authorization` retiré du client, 2 échouent (J23, J24, sur une copie sous Linux).
- **Le client `traceability-web` est importé par Keycloak et réglé comme prévu**, dans Docker et sous Windows (J4, J20).
- **La connexion se fait par le flux code d'autorisation avec PKCE** : l'adresse envoyée à Keycloak porte `client_id=traceability-web`, `response_type=code`, un `code_challenge` et `code_challenge_method=S256` (J8). Sans être connecté, l'interface n'appelle ni l'API ni Keycloak (J6). La page `/auth/callback` ouverte sans code affiche « La connexion a échoué. » avec un lien de retour (J7).
- **L'API reçoit le jeton** : un appel porte `Authorization: Bearer …`, précédé d'une pré-vérification en 204 ; en `writer-test`, les listes se chargent (pas de 401) et une ferme est créée depuis l'interface (J9 à J11). Une station, une fonction et un lot sont aussi créés ainsi, sous Windows (J20).
- **Le jeton n'est stocké nulle part dans le navigateur** : aucun `eyJ` dans le `localStorage` ni le `sessionStorage`, et rien ne reste dans le `localStorage` après une connexion complète (J12). Recharger la page déconnecte, et Keycloak, qui garde sa propre session, ramène dans l'interface sans mot de passe (J13).
- **Le renouvellement automatique fonctionne** : deux appels à `/token` à 4 minutes d'intervalle, aucune page cachée vers Keycloak, et la session reste ouverte après l'expiration du jeton de départ, avec une liste qui se charge (J14). Le moyen exact (jeton de rafraîchissement) est déduit.
- **La déconnexion ferme la session de Keycloak** : appel `logout` en 302, retour sur l'écran « Connexion », identifiant et mot de passe redemandés (J15).
- **Les rôles sont respectés dans l'interface** : `reader-test` ne voit aucun bouton d'écriture et ses fiches lot et station n'ont ni « Ajouter un mouvement » ni formulaire de fonction (J16, J20) ; une page d'écriture ouverte de force affiche « Vous n'avez pas le droit de saisir des données. » sans formulaire (J17) ; un compte sans rôle voit « Vous n'avez pas le droit de faire cela. » sur Lots, Fermes et Stations, avec des 403 dans la console (J18).
- **Keycloak arrêté** : « Se connecter » affiche « Impossible de joindre le serveur de connexion. Est-il lancé ? » ; relancé, il redonne sa page de connexion sans recharger (J19).
- **Sous Windows** (JDK 21, base neuve), `writer-test` et `reader-test` se connectent et voient ce qui leur revient (J20) ; le serveur est ensuite arrêté par Ctrl+C et aucun Java ne reste.
- **Aucun jeton brut ni mot de passe dans les fichiers du lot** (J21) ; la CI (`.github/`) n'est pas modifiée.
- **La CI est verte** sur la branche (exécutions n° 62 et 63), puis sur `main` après la fusion (n° 64), relevées le 2026-11-09 (J22). Elle n'utilise ni Keycloak ni vrai jeton : elle ne prouve pas la connexion elle-même.
- **Non prouvé** : tout ce qui figure en 20.3, dont le moyen exact du renouvellement.

### 20.5 Rejouer la vérification

Dans PowerShell. Fenêtres conseillées : `Docker` (Keycloak), `API`, `Vite`, `Essais` (git, tests). Les mots de passe sont saisis dans la console de Keycloak, jamais dans un message ni un fichier ; un jeton n'est jamais collé.

**1. Tests automatiques**. Depuis `web/` : `npm run lint`, `npm run build`, `npm test`. Depuis la racine du dépôt, API arrêtée, `ConnectionStrings__Test` définie : `dotnet test Traceability.slnx`.

**2. Keycloak** avec le fichier de réglages actuel : voir 18.5 (Docker ou Windows). Un realm déjà présent n'est pas réimporté : un conteneur ou un dossier de Keycloak créés avant le lot 10c n'a pas le client `traceability-web` ; supprimer le conteneur (`docker rm -f traceability-keycloak`) ou, sous Windows, le dossier `data\h2` de Keycloak (et recopier le fichier de réglages dans `data\import`). Les comptes sont à recréer à la main dans la console (`http://localhost:8180/admin`, realm `traceability`) : `reader-test` (rôle `reader`), `writer-test` (rôle `writer`) et `norole-test` (aucun des deux rôles).

**3. L'API**, dans la fenêtre `API`, depuis la racine du dépôt :

```powershell
$env:ConnectionStrings__Default = $env:ConnectionStrings__Test
$env:Authentication__Authority = 'http://localhost:8180/realms/traceability'
$env:Authentication__Audience = 'traceability-api'
dotnet run --project src/Traceability.Api --launch-profile https
```

Après un changement de Keycloak (nouvelle base, donc nouvelles clés de signature), relancer l'API.

**4. L'interface**, dans la fenêtre `Vite` : `cd web` puis `npm run dev` ; ouvrir `http://localhost:5173/` dans une fenêtre de navigation privée (J6 à J9, J13, J15).

**5. Ce que le navigateur garde** (J12). Dans la console des outils du navigateur, après la connexion : `Object.keys(localStorage)`, `Object.keys(sessionStorage)`, puis `[...Object.values(localStorage), ...Object.values(sessionStorage)].some(v => v.includes('eyJ'))` (attendu : `false`).

**6. Le renouvellement** (J14). Onglet Réseau, « Keep log » coché, filtre `openid-connect`, liste vidée juste après la connexion, page non rechargée : environ 4 minutes plus tard une ligne `token` apparaît (puis une autre 4 minutes après) et la liste de Fermes reste chargée au-delà de 5 minutes. Ne pas ouvrir ces lignes : leur contenu montre des jetons.

**7. Un rôle insuffisant** (J16 à J18). Se connecter avec `reader-test` : aucun bouton d'écriture. Pour atteindre une page d'écriture sans recharger la page, dans la console : `history.pushState({}, '', '/new-farm'); window.dispatchEvent(new PopStateEvent('popstate'))` (une adresse tapée dans la barre rechargerait la page et ferait perdre le jeton). Se connecter avec `norole-test` : le message du 403 sur les trois listes.

**8. Keycloak arrêté** (J19). Déconnecté, `docker stop traceability-keycloak`, puis « Se connecter » : le message d'injoignabilité. `docker start traceability-keycloak`, attendre `started in` dans `docker logs traceability-keycloak --tail 5`, puis « Se connecter » doit ramener sur la page de Keycloak sans recharger.

**9. Casses volontaires** (J3, J23, J24). J3 : retirer `Authorization` de `.WithHeaders(...)` dans `Program.cs`, lancer `dotnet test tests/Traceability.IntegrationTests --filter "FullyQualifiedName~CorsTests"` (un test doit échouer), puis remettre le fichier. J23 et J24 : sur une copie de `web/` hors du dépôt (installée avec `npm ci`), faire renvoyer toujours vrai à `canWrite` (`web/src/auth/roles.ts`), ou retirer l'en-tête dans `withAuthorization` (`web/src/api/client.ts`), puis lancer `npx vitest run`.

**10. Aucun secret dans les fichiers**, depuis la racine du dépôt :

```powershell
git grep -n --untracked "eyJ"
git grep -n --untracked -i "password" -- identity
```

Le premier ne doit montrer, hors de `web/package-lock.json` (empreintes `sha512-`), que du texte de ce document ; le second ne doit rien montrer.

**11. CI** (J22) : une fois la branche poussée, les trois contrôles `backend`, `frontend` et `docker` doivent être verts sur la branche.

## 21. Lot 11 : l'auteur de chaque mouvement

Écrit le 2026-11-10, avant l'essai à la main de l'API et de l'interface (fait le soir du même jour, entre 21 h 20 et 22 h 50 UTC environ). La partie base de données (K1 à K8) est déjà essayée avant ; les autres lignes valent « À observer » tant que l'essai n'est pas fait, puis le résultat les remplace. Il n'y a pas de prédiction chiffrée : chaque ligne se terminera par « Observé » ou « Non observé », avec ce qui a été vu. Le lot 11 modifie la base (colonnes `AuthorId` et `AuthorName` de `trace.Movement`, procédures `CreateBatch`, `AddMovement` et `GetBatch`), l'API, les tests, l'interface et les documents ; la CI (`.github/workflows/ci.yml`) n'est pas touchée.

### 21.1 Ce qui est essayé

- Chaque mouvement enregistre son auteur : `AuthorId` (identifiant stable du compte, champ `sub` du jeton, 64 caractères au plus) et `AuthorName` (nom d'utilisateur au moment de la saisie, champ `preferred_username`, 100 caractères au plus). Les deux colonnes sont obligatoires, sans valeur par défaut, et chacune a une contrainte `CHECK` (ni vide, ni espaces seulement).
- Les anciens mouvements reçoivent une valeur de remplacement : `AuthorId` = `00000000-0000-0000-0000-000000000000`, `AuthorName` = `Initial_User`. L'interface affiche « Données initiales » à la place de `Initial_User`.
- `CreateBatch` et `AddMovement` prennent deux paramètres, `@AuthorId` et `@AuthorName`. Les erreurs 50405 (auteur vide) et 50406 (auteur trop long) sont contrôlées en premier ; l'API les traduit en 400, comme les autres erreurs 504xx.
- L'API lit l'auteur dans le jeton déjà validé, jamais dans le corps de la requête. `MapInboundClaims` est réglé à `false` : les champs gardent le nom qu'ils ont dans le jeton. Un jeton valide sans `sub` ou sans `preferred_username` ne peut pas écrire : réponse 403.
- `GetBatch` et l'API renvoient seulement le nom de l'auteur ; l'identifiant ne sort pas de la base. Tous les rôles qui lisent voient le nom.
- L'interface ajoute une colonne « Auteur » au tableau des mouvements d'un lot.
- La base existante est mise à niveau par `database/018_add_movement_author.sql` (une transaction, essai à blanc possible) ; les bases neuves reçoivent les colonnes par `002`.
- Les tests automatiques remplacent l'authentification et donnent l'identité par des en-têtes de test ; la vraie lecture du jeton est essayée à la main avec Keycloak.

### 21.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| K1 | `018` en essai à blanc (`@keep = N'NO'`, tout est annulé) sur `TraceabilityDev` (1 000 000 de lots, 3 250 000 mouvements) : durée et résultat. | Observé le 2026-11-10. Essai à blanc : 2 min 08 s ; l'ajout des colonnes seul : 54 s. |
| K2 | `018` exécuté pour de bon sur `TraceabilityDev`, puis sur `TraceabilityTest` : ses contrôles intégrés. | Observé le 2026-11-10. Réussi sur les deux bases. Contrôles intégrés : colonnes présentes ; nombre de mouvements égal au nombre de mouvements portant la valeur de remplacement ; aucune valeur par défaut restante ; contraintes `CHECK` de confiance. La durée de l'exécution réelle n'a pas été relevée. |
| K3 | `005` puis `017` rejoués sur `TraceabilityDev` et sur `TraceabilityTest`. | Observé le 2026-11-10. Sans erreur ; 10 procédures sur `TraceabilityTest`. |
| K4 | `003` sur `TraceabilityDev` (21 tests, dont les tests 18 à 21 ajoutés par le lot). | Observé le 2026-11-10. 21 sur 21 ; nombre de lignes des tables inchangé. |
| K5 | `006` sur `TraceabilityTest` (47 tests, dont les tests 39 à 47 ajoutés par le lot). | Observé le 2026-11-10. 47 sur 47 : 42 « OK » et 5 « à vérifier à l'œil », ces 5 vérifiés. |
| K6 | `012` sur `TraceabilityTest` (16 tests). | Observé le 2026-11-10. 16 sur 16 : 10 « OK » et 6 « à vérifier à l'œil », vérifiés ; le test 2 donne un tableau vide avec `TotalCount` = 11. |
| K7 | `008` sur `TraceabilityDev`, après `018`. | Observé le 2026-11-10, vers 11:15 UTC. 28 sur 28 « OK ». Contrôle 28 (clés étrangères et `CHECK` non fiables) = 0 : les deux `CHECK` d'auteur sont de confiance sur 3 250 000 mouvements. Volumes inchangés : 1 000 000 de lots, 3 250 000 mouvements. |
| K8 | `GetBatch` sur `LOT-0000001` dans `TraceabilityDev`. | Observé le 2026-11-10. 4 mouvements (RECEPTION, SORTING, PACKING, SHIPMENT), tous avec `AuthorName` = `Initial_User`. |
| K9 | Depuis `web/` : `npm run lint`, `npm run build` et `npm test`. Relever les résultats (248 tests d'interface avant le lot). | Observé le 2026-11-10, sur le PC. `npm run lint` : « Found 0 warnings and 0 errors » (85 fichiers, 116 règles). `npm run build` : réussi en 2,21 s (CSS 14,62 ko, JS 365,73 ko). `npm test` : une première exécution, lancée en même temps que `dotnet test` (166 s au lieu d'une dizaine), a donné « Test Files 1 failed, 26 passed (27) » et « Tests 1 failed, 249 passed (250) » ; le test en échec n'a pas été identifié. Une seconde exécution, seule, a donné « Test Files 27 passed (27) » (la ligne « Tests » n'a pas été relevée). Une exécution faite plus tôt le même jour avait donné 27 fichiers et 250 tests réussis. |
| K10 | `dotnet test Traceability.slnx`, API arrêtée : relever le nombre de tests et le résultat (89 tests unitaires et 130 tests d'intégration avant le lot). | Observé le 2026-11-10, API arrêtée. Tests unitaires : 0 échec, 99 réussis (651 ms). Tests d'intégration : 0 échec, 136 réussis (1 min 30 s, lancés en même temps que `npm test` ; 13 à 17 s quand ils tournaient seuls pendant les casses). Avant le lot : 89 et 130 ; le lot ajoute 10 tests unitaires (`CurrentUserTests`) et 6 tests d'intégration. |
| K11 | Casse volontaire 1 : l'API ne transmet plus l'auteur lu dans le jeton (une valeur fixe à la place). Des tests d'intégration échouent ; le fichier remis est identique à l'original (empreinte SHA-256). | Observé le 2026-11-10. Dans `BatchesController.cs`, l'appel de `AddMovementAsync` passe `null, null` à la place de `author.Id, author.Name`. Tests d'intégration : 12 échecs sur 136 (124 réussis), tous dans `BatchesTests` et tous des ajouts de mouvement, dont `Each_movement_keeps_its_own_author_and_the_identifier_is_not_returned` ; par exemple `An_unknown_movement_type_gives_400_when_a_movement_is_added` attend 50402 et reçoit 50405. Fichier remis : empreinte SHA-256 `d75c201ea70582deaf0386f0cb17f8218a963bc2b75f9c6c82b142f9dd6e8c5c` avant la casse et après la remise, et `cmp` identique à la copie gardée. |
| K12 | Casse volontaire 2 : la règle « auteur vide » (50405) est retirée de `AddMovement` dans `005`, sur `TraceabilityTest`. `006` échoue ; `005` puis `017` rejoués remettent la base en l'état. | Observé le 2026-11-10. Dans `005`, la condition de la règle 50405 de `AddMovement` est remplacée par `IF 1 = 0` (le fichier cassé porte aussi `:setvar DbName TraceabilityTest`, pour ne pas atteindre `TraceabilityDev`). `005` puis `017` rejoués sur `TraceabilityTest`, puis `006` : verdict `FAILED` (47 tests, 46 réussis ou à vérifier à l'œil, 1 marqué ATTENTION). Ce test est le n° 45 (`AddMovement: author id NULL`) : il attend 50405 et reçoit l'erreur 515 de la colonne `NOT NULL`. Les contrôles de `CreateBatch` (42 à 44) restent verts. `005` remis (SHA-256 `f67559c52ebc99aac6d6f9872c9e0921e82b211f1f2a46261d470095d2982aee`, identique à la copie), `005` et `017` rejoués sans erreur, `006` : 47 tests, 42 « OK » et 5 « à vérifier à l'œil » (ces 5 n'ont pas été relus cette fois). Le test 45 est le seul à échouer : `006` n'a pas de test d'identifiant vide ni de nom vide pour `AddMovement`. |
| K13 | Casse volontaire 3 : `MapInboundClaims = false` est retiré de `Program.cs`. Un test échoue ; le fichier remis est identique à l'original (empreinte SHA-256). | Observé le 2026-11-10. `options.MapInboundClaims = false;` retiré de `Program.cs`. Tests d'intégration : 1 échec sur 136 (135 réussis), `The_token_handler_keeps_the_names_of_the_fields_of_the_token` ; les autres tests ne le voient pas, car leur faux jeton pose `sub` directement. Avec l'API ainsi cassée, lancée sur `TraceabilityTest`, et un vrai jeton de `writer-test` (`sub`, `preferred_username` et rôle `writer` présents) : `POST /batches` répond 403 avec « The token does not give the identity of the user (claims sub and preferred_username). » et le lot n'est pas créé (`GET` : 404). La cause, un renommage de `sub` par le gestionnaire de jetons par défaut, est déduite de ce comportement et de la documentation, elle n'est pas lue dans le jeton. `Program.cs` remis : SHA-256 `66ad8cfbad17d97639899ada451f73fb67472355b2825ba131bfe042910bac9a`, identique à l'original. |
| K14 | Keycloak est démarré dans Docker, l'API est lancée (`--launch-profile https`) sur `TraceabilityDev` avec `Authentication__Authority` et `Authentication__Audience`, l'interface avec `npm run dev`. Relever le démarrage et toute erreur. | Observé le 2026-11-10. Écart avec la ligne : l'API a d'abord tourné sur `TraceabilityTest`, parce que l'essai écrit ; `TraceabilityDev` n'a servi qu'en lecture, pour K19. Keycloak : le conteneur `traceability-keycloak` (image 26.6.2) était arrêté (`Exited (137)`) ; `docker start` l'a relancé (`127.0.0.1:8180->8080/tcp`) et `/realms/traceability/.well-known/openid-configuration` répond 200. API : `dotnet run --project src/Traceability.Api --launch-profile https`, avec `ConnectionStrings__Default` copiée de `ConnectionStrings__Test` et les deux variables `Authentication__*` : `Now listening on: https://localhost:7080`, `Hosting environment: Development`, aucune erreur. Interface : `npm run dev` : `VITE v8.3.5 ready in 2688 ms`, `http://localhost:5173/`, dans Edge, en fenêtre privée. Pour K19, l'API a été relancée sur `TraceabilityDev` (`Server=localhost` et `Database=TraceabilityDev` relevés avant le démarrage), même démarrage, sans erreur. |
| K15 | Connecté en `writer-test` : saisir un mouvement sur un lot (ou créer un lot, puis un mouvement). La colonne « Auteur » de la page du lot affiche `writer-test`. | Observé le 2026-11-10, sur captures (Edge, fenêtre privée, `writer-test` dans l'en-tête). Lot `ESSAI-L11-001` créé par le formulaire (ferme `ZT-A37BA818101D`, station `ZT-981DCA459836` avec la fonction Réception, 100 kg, Roma) : sa page montre une ligne `Réception`, 100,00 kg, 10/11/2026 21:39:00 UTC, auteur `writer-test`. Mouvement `Tri` ajouté (station `ZT-CFDD70DECE32`, 95 kg, 21:46:00 UTC) : message « Mouvement Tri ajouté. », lot « Trié », deux lignes, auteur `writer-test` sur les deux. Panneau Réseau pour ce mouvement : `preflight` 204 puis `movements` 201 ; une ligne `token` 200 (renouvellement) est aussi visible. Le code HTTP de la création du lot n'a pas été relevé. |
| K16 | Dans SSMS, sur `TraceabilityDev` : lire dans `trace.Movement` la ligne créée en K15. `AuthorName` vaut `writer-test` ; `AuthorId` vaut l'identifiant du compte affiché dans la console de Keycloak (aucun jeton copié). Cette ligne prouve aussi les noms de champs vus par .NET. | Observé le 2026-11-10, sur `TraceabilityTest`, où l'essai a écrit (écart avec la ligne, qui disait `TraceabilityDev`). Un `SELECT` sur `trace.Movement` joint à `trace.Batch` pour `ESSAI-L11-001` donne `MovementId` 658 (`RECEPTION`) et 659 (`SORTING`), `AuthorId` = `050d0bc3-160d-4f11-be89-857bf001bf10` et `AuthorName` = `writer-test` sur les deux. Cet identifiant est celui que la console de Keycloak affiche pour `writer-test` (page de détails du compte, champ ID, et adresse de la page). Aucun jeton copié. `AuthorId` vient donc du champ `sub` et `AuthorName` de `preferred_username`, lus par .NET sous leur nom d'origine. |
| K17 | Connecté en `reader-test` : la colonne « Auteur » est visible et aucun bouton d'écriture n'est affiché. | Observé le 2026-11-10, sur capture (Edge, `reader-test` dans l'en-tête). La page de `ESSAI-L11-001` montre la colonne « Auteur » avec `writer-test` sur les deux lignes, et aucun formulaire « Ajouter un mouvement ». Les boutons des pages de liste n'ont pas été revérifiés ce jour-là (voir J16). |
| K18 | Les rôles après `MapInboundClaims = false` : un appel d'écriture direct avec le jeton de `reader-test` reçoit 403 ; avec celui de `writer-test`, 201 (fonctions de 19.5, aucun jeton collé). | Observé le 2026-11-10, par appels directs sur l'API (`TraceabilityTest`), avec `Get-Trial` de 19.5 et `Show-Identity` de 21.5 (aucun jeton affiché). Jeton de `reader-test` : `sub` `3fd7389a-6ade-4fbe-b7dd-42cc12b149ff`, `preferred_username` `reader-test`, rôle `reader` ; `GET /batches` 200, `POST /batches` 403, `GET /batches/ESSAI-L11-LECTEUR` 404 (rien n'a été écrit). Le 201 du compte `writer` a été vu par l'interface (K15, `movements` 201), pas par un appel direct avec son jeton. |
| K19 | Ancien lot `LOT-0000001` : ses 4 mouvements affichent « Données initiales » dans la colonne « Auteur ». | Observé le 2026-11-10, sur capture, API sur `TraceabilityDev`, connecté en `reader-test`. `LOT-0000001` (ferme F001, « Expédié », 176,66 kg) a 4 mouvements du 20/10/2024 : `Réception` (SITE-02), `Tri` (SITE-02), `Emballage` (PCK-01), `Expédition` (SHP-01). Les quatre lignes affichent « Données initiales » dans la colonne « Auteur ». Aucune écriture n'a été faite sur cette base pendant l'essai. |
| K20 | Connecté en `norole-test` : comportement inchangé (403 et message « Vous n'avez pas le droit de faire cela. »). | Observé le 2026-11-10, par appels directs (pas dans l'interface). Jeton de `norole-test` obtenu (HTTP 200), `sub` `d1628d43-9071-49bc-b286-386f0c4e957f`, `preferred_username` `norole-test`, rôles sans `reader` ni `writer` ; `GET /batches/ESSAI-L11-001` répond 403. Le message affiché par l'interface n'a pas été revu. |
| K21 | Jeton valide sans `sub` ou sans `preferred_username` : l'écriture est refusée (403) et la lecture n'est pas touchée. À essayer avec un vrai jeton si Keycloak permet d'en obtenir un simplement ; sinon la ligne vaut « Non observé » et le cas reste couvert par les tests d'intégration. | Observé le 2026-11-10, avec un vrai jeton. Le groupe de réglages `profile` est retiré du client `traceability-trial` (console de Keycloak) : le jeton de `writer-test` a alors un `sub` rempli (`050d0bc3-…-857bf001bf10`), un `preferred_username` vide et le rôle `writer`. `POST /batches` répond 403 avec « The token does not give the identity of the user (claims sub and preferred_username). » ; `GET /batches/ESSAI-L11-SANSNOM` répond 404 : le lot n'existe pas, et la lecture n'est pas refusée. `profile` est ensuite ajouté de nouveau (type « Default ») : le jeton redonne `preferred_username` = `writer-test`. Le cas sans `sub` n'est pas essayé avec un vrai jeton ; il reste couvert par les tests. |
| K22 | Aucun jeton brut ni mot de passe dans les fichiers du lot (`git grep -n --untracked "eyJ"`, puis la recherche de `password` dans `identity`, comme en 20.5). | Observé le 2026-11-10, sur le dépôt local, avant le commit, une fois tous les documents écrits. Recherche de `eyJ` avec `grep` dans les 29 fichiers modifiés ou nouveaux (liste de `git status`, fichiers non suivis compris) et dans `identity/traceability-realm.json` : seulement des lignes de ce document qui nomment la recherche, aucun jeton. Recherche de `Bearer` suivi de 20 caractères ou plus : rien. Recherche de `password` et `secret` dans les lignes ajoutées du diff, dans les fichiers non suivis et dans `identity/` : rien en dehors du texte de ce document qui décrit la recherche. `git grep --untracked` lui-même n'a pas été lancé. |
| K23 | CI : une fois la branche poussée, les trois contrôles `backend`, `frontend` et `docker` sont verts sur la branche. | Observé le 2026-11-10, sur GitHub (onglet Actions et page de la pull request n° 25, captures). Branche poussée : exécution CI n° 68 (événement `push`, commit `90787ec`, 1 min 1 s) et n° 69 (événement `pull_request`, 1 min 3 s). Sur la pull request, 6 contrôles réussis : `backend` (pull_request 1 min, push 58 s), `docker` (26 s et 25 s) et `frontend` (30 s et 33 s). Après la fusion : exécution n° 70 sur `main` (commit de fusion `09622d5`, 59 s), verte. `.github/` n'est pas modifié. La CI n'utilise ni Keycloak ni vrai jeton, et ne rejoue pas `018`. |

### 21.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- `database/007` (générateur de volume) est modifié pour écrire la valeur de remplacement, mais jamais rejoué : le rejouer effacerait les 1 000 000 de lots de `TraceabilityDev`. Il a été relu seulement. Il en va de même de `database/016` (script de mesure), modifié pour passer les deux paramètres d'auteur à `CreateBatch`.
- `018` n'est pas rejoué par la CI : la CI reconstruit `TraceabilityTest` depuis `002`, qui contient déjà les colonnes.
- La taille de l'index cluster de `Movement` est de 194,92 Mo après la migration ; la taille avant n'a pas été mesurée, donc aucun effet de la migration sur la taille n'est affirmé.
- Les `MovementId` du premier lot de `TraceabilityDev` commencent à 5 : cause non étudiée, sans effet sur le lot.
- Aucune règle de visibilité du nom : tous les rôles qui lisent le voient. Avec des personnes réelles, ou pour un public extérieur (un organisme d'audit, par exemple), cela se déciderait avec les responsables des données (RGPD, audit).

Ajouté après l'essai du 2026-11-10 :

- Le code HTTP de la création du lot `ESSAI-L11-001` n'a pas été relevé (le panneau Réseau n'a été ouvert que pour le mouvement suivant, en 201). Aucun appel direct avec le jeton de `writer-test` n'a donné un 201 : seul l'interface l'a montré (K15, K18).
- Un lecteur et un compte sans rôle n'ont pas été essayés dans l'interface pour les boutons des listes et le message du 403 (K17, K20) ; ils l'ont été en appels directs.
- Un seul navigateur (Edge, fenêtre privée). Le renouvellement du jeton n'apparaît qu'en passant (une ligne `token` en 200 en K15) ; ni l'expiration, ni la déconnexion, ni Keycloak arrêté ne sont essayés pour ce lot.
- Un test de l'interface a échoué dans une exécution lente (K9) : son nom et sa cause ne sont pas connus ; il n'est pas reproduit en exécution seule.
- Pour `AddMovement`, `006` n'a pas de test d'identifiant vide ni de nom vide : la suppression de la règle 50405 n'est attrapée que par le test 45 (identifiant `NULL`), puis par la contrainte de la table (K12). Un seul test voit `MapInboundClaims` : `The_token_handler_keeps_the_names_of_the_fields_of_the_token` (K13).
- Jeton sans `sub` : non essayé avec un vrai jeton ; seul `preferred_username` a été retiré (K21).
- Le client `traceability-trial` a été modifié dans la console de Keycloak (`profile` retiré, puis remis en « Default ») : le retour à l'état d'origine est constaté par le jeton (le nom est revenu), pas par une comparaison des réglages du client.
- Données laissées dans `TraceabilityTest` : le lot `ESSAI-L11-001` et ses deux mouvements (identifiants 658 et 659). `dotnet test` et `006` ont tourné ensuite ; la présence de ces lignes n'a pas été revérifiée. Aucune écriture n'a été faite volontairement sur `TraceabilityDev`.
- Mesures : aucun temps de réponse de l'API n'a été relevé pour ce lot.

### 21.4 Ce qui est prouvé

- **La base reçoit l'auteur** : `018` migre `TraceabilityDev` et `TraceabilityTest`, avec ses contrôles intégrés ; `005`, `017`, `003`, `006`, `012` et `008` passent après la migration, y compris le contrôle des contraintes de confiance sur 3 250 000 mouvements (K1 à K7).
- **Les anciens mouvements ont l'auteur de remplacement** : les quatre mouvements de `LOT-0000001` portent `Initial_User` en base (K8) et l'interface les affiche « Données initiales » (K19).
- **L'auteur est lu dans un vrai jeton** : un lot et un mouvement créés par `writer-test` affichent `writer-test` dans la colonne « Auteur » (K15), et la base garde l'identifiant de son compte Keycloak dans `AuthorId` et son nom dans `AuthorName` (K16).
- **Les rôles ne changent pas** : `reader-test` voit la colonne « Auteur » et n'a pas de formulaire d'écriture (K17), son écriture directe est refusée (403) sans rien écrire, `norole-test` reste refusé (K18, K20), `writer-test` écrit (K15).
- **Un jeton valide sans nom d'utilisateur ne peut pas écrire** : réponse 403 et rien d'écrit (K21).
- **Les tests détectent les trois casses essayées** : l'auteur non transmis par l'API fait échouer 12 tests d'intégration (K11), la règle 50405 retirée fait échouer `006` (K12), `MapInboundClaims` retiré fait échouer un test et un vrai jeton de `writer-test` est alors refusé (K13). Les trois fichiers sont remis à l'identique, preuves par SHA-256 ou copie.
- **Les tests passent après le lot** : 99 tests unitaires et 136 tests d'intégration en C# (K10), `006` à 47 tests (K12) ; pour l'interface, une exécution seule a réussi les 27 fichiers (K9), mais une exécution lente a eu un échec non identifié.
- **Aucun jeton brut ni mot de passe dans les fichiers du lot** (K22).
- **La CI est verte** sur la branche (exécutions n° 68 et 69), puis sur `main` après la fusion (n° 70) (K23). Elle n'utilise ni Keycloak ni vrai jeton : elle ne prouve pas la lecture du jeton.
- **Non prouvé** : tout ce qui figure en 21.3.

### 21.5 Rejouer la vérification

Dans PowerShell. Fenêtres conseillées : `Docker` (Keycloak), `API`, `Vite`, `Essais`. Les mots de passe sont tapés dans la console de Keycloak ou dans la saisie masquée de `Get-Trial`, jamais dans un message ni un fichier ; un jeton n'est jamais collé.

**1. Base de données** : exécuter `018` sur chaque base existante (d'abord à blanc, `@keep = N'NO'`, puis pour de bon), rejouer `005` et `017`, puis `003`, `006`, `012` et `008` (voir leurs en-têtes pour la base visée). Ne pas rejouer `007` sur `TraceabilityDev`.

**2. Tests automatiques**, API arrêtée, sans rien lancer d'autre en parallèle : `dotnet test Traceability.slnx` depuis la racine, puis `npm run lint`, `npm run build` et `npm test` depuis `web/`.

**3. Keycloak, API et interface** : comme en 20.5. L'API est lancée avec `ConnectionStrings__Default` copiée de `ConnectionStrings__Test` quand l'essai écrit (K14).

**4. Une fonction d'aide de plus**, pour lire l'identité d'un jeton sans l'afficher, à côté de `Get-Trial` de 19.5 :

```powershell
function Show-Identity {
  $p = $global:Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
  $p = $p.PadRight($p.Length + (4 - $p.Length % 4) % 4, '=')
  $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
  [pscustomobject]@{ sub = $c.sub; preferred_username = $c.preferred_username; roles = ($c.realm_access.roles -join ',') } | Format-List
}
```

**5. L'essai** (K15 à K21) : se connecter en `writer-test`, créer un lot puis un mouvement ; lire `trace.Movement` dans SSMS et comparer `AuthorId` à l'identifiant du compte dans la console de Keycloak ; se connecter en `reader-test` ; avec `Get-Trial reader-test`, un `GET /batches` (200) et un `POST /batches` (403) ; avec `Get-Trial norole-test`, un `GET` (403) ; puis, pour K21, retirer `profile` du client `traceability-trial`, obtenir un jeton de `writer-test`, vérifier le `POST` (403), et remettre `profile` en « Default ».

**6. Les trois casses** : les fichiers touchés sont `BatchesController.cs` (appel de `AddMovementAsync`), `005` (règle 50405 de `AddMovement`) et `Program.cs` (`MapInboundClaims`). Relever les empreintes SHA-256 avant, casser, lancer les tests, remettre, contrôler les empreintes.

**7. Secrets** : `git grep -n --untracked "eyJ"` ne doit montrer que du texte de ce document ; la recherche de `password` et `secret` dans les lignes ajoutées et dans `identity/` ne doit rien montrer de réel.

**8. CI** (K23) : une fois la branche poussée, les trois contrôles `backend`, `frontend` et `docker` doivent être verts sur la branche.

## 22. Lot 12a : la correction des mouvements

Écrit le 2026-11-11, **après** l'essai à la main de l'API et **avant** l'essai à la main de l'interface. Ce n'est pas l'ordre prévu : la liste devait être écrite avant tout essai. Les lignes L1 à L14 (base de données, API, tests automatiques) ont donc été observées avant d'être écrites : elles n'ont pas de prédiction préalable, et leur résultat vient des affichages de la séance. Les lignes L15 à L25 (interface) ont été écrites avant l'essai ; L26 a été ajoutée pendant l'essai (un texte d'erreur jugé peu clair) ; L27 à L29 ont été écrites après l'essai, à partir de ce qui a été vu. Chaque ligne se terminera par « Observé » ou « Non observé », avec ce qui a été vu. Le lot 12a modifie la base (table `trace.MovementCorrection`, procédures `ReplaceMovement` et `CancelMovement`, `GetBatch`), l'API, les tests, l'interface, le fichier de réglages de Keycloak et les documents ; la CI (`.github/workflows/ci.yml`) n'est pas touchée. La correction de la fiche du lot et de son code est le lot 12b (section 23).

### 22.1 Ce qui est essayé

- Le journal `trace.Movement` n'est jamais modifié. Une correction est une ligne de plus dans `trace.MovementCorrection` : `REPLACE` (nouvelles valeurs : station, quantité, heure ; le type du mouvement ne change pas) ou `CANCEL` (le mouvement n'a pas eu lieu ; la ligne répète les valeurs de la version annulée). La version valable d'un mouvement est sa ligne du journal avec la dernière correction (plus grand `CorrectionId`) appliquée. Une annulation est définitive.
- Règles : la quantité corrigée reste entre celle de l'étape valable précédente et celle de l'étape valable suivante (égalité acceptée) ; la station doit avoir la fonction du mouvement ; des valeurs identiques à la version valable sont refusées (50308) ; seul le dernier mouvement valable peut être annulé (50306), jamais la réception (50307) ; un mouvement annulé ne peut plus être corrigé ni annulé (50305). Le statut et la quantité du lot sont mis à jour par les procédures. Les procédures prennent le même verrou `UPDLOCK` sur le lot que `AddMovement` (ADR 0003).
- Motif obligatoire : `DATA_ENTRY_ERROR`, `MEASUREMENT_ERROR` ou `OTHER` ; le commentaire (500 caractères au plus) est obligatoire pour `OTHER`. Chaque correction garde son auteur, lu dans le jeton comme au lot 11.
- Nouveau rôle Keycloak `supervisor` : il lit et corrige, il ne saisit pas de mouvement. Règles de l'API : lecture pour `reader`, `writer` et `supervisor` ; écriture pour `writer` ; correction pour `supervisor`. Deux routes : `POST /batches/{batchCode}/movements/{movementId}/replace` et `.../cancel` (réponse 201).
- `GetBatch` renvoie trois tableaux : le lot, ses mouvements (valeurs valables, valeurs d'origine, état annulé, nombre de corrections) et l'historique des corrections.
- L'interface montre les valeurs valables avec « saisie : … » pour la valeur d'origine, les mouvements annulés barrés, un historique des corrections avec leur auteur, et, pour le rôle `supervisor` seulement, la section « Corriger un mouvement ». Si le lot avait été expédié, l'interface propose un message à copier pour le destinataire : le supervisor le transmet lui-même, sans courriel et sans suivi dans l'application.
- La table est créée par `002` pour les bases neuves et par `database/019_add_movement_correction.sql` pour une base existante (rejouable). `019` n'a été exécuté que sur `TraceabilityTest`.

### 22.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| L1 | `003` (31 tests) et `006` (88 tests) sur `TraceabilityTest`. | Observé le 2026-11-11. `003` : 31 sur 31, six tables inchangées. `006` : 88 tests, 81 « OK », 7 « à vérifier à l'œil », aucun verdict d'erreur. Les 7 lignes « à vérifier à l'œil » (tests 30, 32, 33, 38, 41, 86, 87) ont été relues sur une seconde exécution complète de `006` (même jour, sortie envoyée en fichier) : chaque tableau correspond aux valeurs attendues que le script affiche. Test 32 : le tableau contient 4 lignes `SORTED`, dont `ZZ-B-SORT` et deux lignes `ZT-…` laissées par le dernier `dotnet test`, `TotalCount` 4 ; ces lignes `ZT-…` ne sont pas des données de `006`. Test 86 : `CorrectionId` 94, 95, 96, 102, 103, tous par `Supervisor One`. Test 87 : `CorrectionId` 97, 100, 101. |
| L2 | `dotnet build` à la racine du dépôt. | Observé le 2026-11-11 vers 10:49 UTC. Les quatre projets réussissent, sans erreur ni avertissement affiché. |
| L3 | `dotnet test` à la racine, sur `TraceabilityTest`. | Observé le 2026-11-11 vers 10:51 UTC. 301 tests, 0 échec, 301 réussis. |
| L4 | Keycloak recréé avec le fichier de réglages modifié : le rôle `supervisor` existe ; quatre comptes créés à la main (`reader-test`, `writer-test`, `supervisor-test`, `norole-test`). | Observé le 2026-11-11, entre 18:04 et 18:13 UTC. Journal : `Realm 'traceability' imported`, `started in 125.659s`, ni `WARN` ni `ERROR`. Console : trois rôles du lot (`reader`, `supervisor`, `writer`) dans Realm roles ; `supervisor-test` avec le rôle `supervisor`. |
| L5 | Contenu des jetons (`Show-Token`) : `aud`, `iss`, rôles. | Observé le 2026-11-11. `writer-test` : `writer`, sans `supervisor` ; `supervisor-test` : `supervisor`, sans `writer` ; `reader-test` : `reader` ; `norole-test` : aucun des trois. `aud` = `traceability-api,account` et `iss` = `http://localhost:8180/realms/traceability` partout, durée 300 s. Sans jeton : 401 et `WWW-Authenticate: Bearer`. |
| L6 | Avec `writer-test` : créer ferme, trois stations, leurs fonctions, un lot et trois mouvements (codes `ESSAI-12A-…`) ; puis essayer de corriger (`replace`). | Observé le 2026-11-11 vers 19:02 UTC. Les 13 créations répondent 201 ; le lot `ESSAI-12A-L1` est `SHIPPED` à 460 kg. La correction par le `writer` répond 403 et le lot reste identique. |
| L7 | Avec `supervisor-test` : remplacer la quantité de l'expédition (460 → 455 kg, `MEASUREMENT_ERROR`, avec commentaire). | Observé le 2026-11-11 vers 19:03 UTC. 201 ; le lot affiche `quantityKg` = 455.00, `corrections` = 1, le mouvement 998 à 455,00 avec `correctionCount` = 1. |
| L8 | Dans SSMS (`TraceabilityTest`) : le journal est intact, la correction est une ligne à part, les auteurs sont les vrais comptes. | Observé le 2026-11-11 vers 19:04 UTC. `trace.Movement`, mouvement 998 : 460.00, auteur `writer-test`. `trace.MovementCorrection` : `CorrectionId` 32, `REPLACE`, 455.00, `MEASUREMENT_ERROR`, auteur `supervisor-test`. Les `AuthorId` sont identiques à l'identifiant du compte dans la console de Keycloak, comparés à l'œil pour `writer-test` (`708b7a29-…`) et `supervisor-test` (`239c410c-…`). |
| L9 | Avec `supervisor-test`, neuf appels refusés : ajout de mouvement ; mêmes valeurs ; quantité au-dessus de l'étape précédente ; station sans la fonction ; annulation du tri ; annulation de la réception ; motif `OTHER` sans commentaire ; motif inconnu ; mouvement inexistant. | Observé le 2026-11-11 vers 19:05 UTC. 403, 422, 422, 422, 422, 422, 400, 400, 404, dans cet ordre. Le lot est inchangé (455.00, `corrections` = 1). Les numéros d'erreur ne sont pas relevés ici : les tests automatiques les contrôlent. |
| L10 | Annuler le dernier mouvement valable (l'expédition), puis tenter de le corriger et de l'annuler à nouveau. | Observé le 2026-11-11 vers 19:06 UTC. Annulation : 201 ; le lot revient à `PACKED` à 470,00 kg, `corrections` = 2, le mouvement 998 est annulé (`isCancelled` vrai, `correctionCount` = 2, il garde 455,00). Correction puis seconde annulation : 422 deux fois, le lot est identique. |
| L11 | `reader-test` : lecture, tentative de correction ; `norole-test` : lecture, tentative de correction. | Observé le 2026-11-11 vers 19:06 UTC. `reader-test` : lecture 200, `replace` et `cancel` 403. `norole-test` : lecture 403, `replace` 403. |
| L12 | Verrou : A corrige le mouvement 997 sans valider (transaction ouverte) ; B lance la même correction ; A valide. | Observé le 2026-11-11, entre 19:08 et 19:12 UTC, avec deux fenêtres SSMS (sessions 65 et 56). B est restée en attente (55 s relevées sur la capture, sans erreur) jusqu'à la validation de A, puis a reçu l'erreur 50308 à 19:11:32. Contrôle : une seule correction pour le mouvement 997 (`CorrectionId` 34, auteur `essai-verrou-a`) ; le lot est `PACKED` à 460.00 ; transactions ouvertes : 0 dans A et 0 dans B. |
| L13 | Trois casses volontaires, avec empreintes SHA-256 avant et après : (1) `replace` demande `CanWrite` au lieu de `CanCorrect` ; (2) `cancel` répond 200 au lieu de 201 ; (3) `GetBatch` ne lit plus le 3e tableau. | Observé le 2026-11-11, entre 19:20 et 19:40 UTC. (1) `BatchesController.cs`, ligne 237 : 23 échecs sur 301, dont `A_writer_or_a_reader_cannot_correct` (`writer`) et deux tests d'`AuthorizationTests` ; empreinte `5930BE81…` → `5D9A3EAF…` → `5930BE81…`. (2) même fichier, ligne 322 : 3 échecs (`Created` attendu, `OK` reçu) ; `5930BE81…` → `CD0841D8…` → `5930BE81…`. (3) `TraceabilityDb.cs`, ligne 246 (`if (false)`, avertissement `CS0162`) : 6 échecs, tous dans `CorrectionsTests` ; `BA85EFEB…` → `BE6612DC…` → `BA85EFEB…`. Après chaque remise en état : 301 sur 301. |
| L14 | Depuis `web/` : `npm run lint`, `npm run build`, `npm test`. | Observé le 2026-11-11 vers 19:47 UTC, sur le PC. `npm run lint` : 0 avertissement, 0 erreur (93 fichiers, 116 règles). `npm run build` : réussi en 2,20 s. `npm test` : 31 fichiers, 296 tests réussis, 0 échec. Rejoué le 2026-11-12 vers 10:47 UTC, après le changement du texte du message de l'erreur 50304 (essai de l'interface, voir L26) : `npm run lint` 0 avertissement et 0 erreur (93 fichiers, 116 règles) ; `npm run build` réussi ; `npm test` 31 fichiers, 296 tests réussis, 0 échec. Rejoué le 2026-11-12 vers 11:20 UTC, après la correction du bandeau « prévenez le destinataire » (voir L20 et L27), 1 test ajouté : `npm run lint` 0 avertissement et 0 erreur (93 fichiers, 116 règles) ; `npm run build` réussi (1,06 s). `npm test`, premier lancement : 294 tests réussis et 3 échecs, tous des « Test timed out in 5000ms » (le premier test des fichiers `BatchesPage.test.tsx`, `BatchPage.test.tsx` et `BatchPage.corrections.test.tsx`), aucun échec d'assertion ; la durée était de 156,31 s, avec un démarrage d'environ 9 s par fichier. Outlook et WhatsApp Web étaient ouverts pendant ce lancement ; la lenteur du PC est la cause probable, elle n'est pas prouvée. `npm test`, second lancement (même jour, vers 11:22 UTC) : 31 fichiers, 297 tests réussis, 0 échec, en 99,67 s. |
| L15 | Préparation de l'essai de l'interface : Keycloak démarré avec ses quatre comptes, API lancée sur `TraceabilityTest` avec `Authentication__Authority` et `Authentication__Audience`, interface lancée (`npm run dev`), données `ESSAI-12A` recréées (les exécutions de `dotnet test` les ont effacées). | Observé le 2026-11-12. Keycloak 26.6.2 (conteneur `traceability-keycloak`, sur 127.0.0.1:8180) avec ses quatre comptes ; API lancée sur `TraceabilityTest` avec les variables d'environnement de l'authentification, sur https://localhost:7080 ; interface lancée par `npm run dev` (http://localhost:5173), dans une fenêtre de navigation privée ; deux lots `ESSAI-12A-L1` et `ESSAI-12A-L2`, ferme `ESSAI-12A-F1`, créés par script SQL avec l'auteur fictif « Donnees SQL (essai) » (les exécutions de `dotnet test` avaient effacé les données précédentes). |
| L16 | `supervisor-test` ouvre la page d'un lot : la section « Corriger un mouvement » est là, et le formulaire d'ajout de mouvement n'y est pas. | Observé le 2026-11-12, en `supervisor-test`, sur `ESSAI-12A-L2` : la section « Corriger un mouvement » est affichée et le formulaire « Ajouter un mouvement » n'y est pas. |
| L17 | `writer-test` ouvre la même page : pas de section « Corriger un mouvement », mais le formulaire d'ajout de mouvement (si le lot n'est pas expédié). | Observé le 2026-11-12 vers 11:28 UTC, en `writer-test` (le nom est affiché en haut à droite), sur `ESSAI-12A-L2` (« Trié », 470,00 kg, 2 étapes) : le formulaire « Ajouter un mouvement » est là (type Emballage, quantité 470 déjà remplie, heure du moment) ; il n'y a pas de section « Corriger un mouvement » ; la page a été relue jusqu'en bas. Rien n'a été enregistré. |
| L18 | `reader-test` : ni l'une ni l'autre. | Observé le 2026-11-12 vers 11:29 UTC, en `reader-test` (le nom est affiché en haut à droite), sur `ESSAI-12A-L2` : le lot et son parcours sont affichés ; il n'y a ni « Ajouter un mouvement » ni « Corriger un mouvement » (la page est vide sous le tableau du parcours). Rien n'a été enregistré. |
| L19 | `supervisor-test` remplace la quantité d'un mouvement : « Correction enregistrée. » s'affiche ; la ligne montre la nouvelle valeur, « saisie : … » et l'étiquette « Corrigé » ; l'historique des corrections apparaît avec « Corrigé par supervisor-test », le motif et le commentaire. | Observé le 2026-11-12 vers 10:55 UTC, en `supervisor-test`, sur `ESSAI-12A-L1` (expédition 460 → 455 kg, « Erreur de mesure », commentaire « Balance non tarée »). « Correction enregistrée. » ; l'expédition affiche 455,00 kg avec « saisie : 460,00 kg » et l'étiquette « Corrigé » ; le lot est à 455,00 kg et reste « Expédié » ; l'historique montre la date 12/11/2026 10:55:44 UTC, « Expédition », « Valeurs remplacées », `ESSAI-12A-S3 · 455,00 kg · 10/11/2026 17:05:00 UTC`, le motif, le commentaire et « Corrigé par supervisor-test ». Après l'enregistrement le formulaire repart prérempli avec les nouvelles valeurs. |
| L20 | Sur un lot expédié, après une correction : le message à transmettre au destinataire apparaît avec les bonnes valeurs ; « Copier le message » le copie (le coller dans le Bloc-notes pour le voir). Sur un lot non expédié : pas de message. | Observé, avec un défaut trouvé puis corrigé. Lot expédié (2026-11-12 vers 10:56 UTC) : le bandeau « Ce lot avait été expédié : prévenez le destinataire. » apparaît avec le message (lot `ESSAI-12A-L1`, étape « expédition », « Quantité : 460,00 kg → 455,00 kg », motif « Erreur de mesure (Balance non tarée) ») ; « Copier le message » répond « Message copié. » et le texte collé à la main dans la conversation est identique à celui de l'écran. Lot non expédié : **divergence**. Après l'annulation de l'expédition de `ESSAI-12A-L1` (lot revenu à « Emballé »), la correction de l'emballage (465 → 464 kg, vers 11:03 UTC) a fait apparaître le bandeau jaune « prévenez le destinataire » alors que le lot n'était plus expédié. Cause : l'interface cherchait une expédition dans la liste des mouvements, et une expédition annulée y reste ; elle regarde maintenant le statut du lot au moment de la correction (`SHIPPED`) ; 1 test ajouté (L27). Après la correction du code : voir L27. |
| L21 | `supervisor-test` annule le dernier mouvement : « Mouvement annulé. », ligne barrée avec l'étiquette « Annulé », statut du lot revenu en arrière, mouvement absent de la liste « Mouvement à corriger ». | Observé le 2026-11-12 vers 11:00 UTC, en `supervisor-test`, sur `ESSAI-12A-L1` (annulation de l'expédition, motif « Autre », commentaire « Camion non parti »). « Mouvement annulé. » ; l'expédition est barrée avec l'étiquette « Annulé » ; le lot revient à « Emballé », 465,00 kg ; l'historique a une 2e ligne (12/11/2026 10:59:34 UTC, « Mouvement annulé », nouvelles valeurs « — », motif et commentaire, « Corrigé par supervisor-test »). Le lot avait été expédié : un message au destinataire apparaît aussi après l'annulation (« l'étape « expédition » est annulée, elle n'a pas eu lieu. Motif : Autre (Camion non parti). »), « Message copié. », texte collé identique. Réserve fermée à 11:03 UTC : la liste déroulante « Mouvement à corriger », ouverte, contient 3 entrées (Réception, Tri, Emballage), sans l'expédition annulée. |
| L22 | Un refus de l'API (par exemple une quantité au-dessus de celle de l'étape précédente) s'affiche en français dans l'alerte ; ce qui a été tapé est conservé. | Observé le 2026-11-12, en `supervisor-test`, sur `ESSAI-12A-L2` (même essai que L26 : quantité du Tri remplacée par 501, au-dessus de la réception à 500 kg) : l'API refuse (erreur 50304), l'interface affiche le refus en français dans le bandeau rouge, la valeur tapée reste dans le champ, aucune confirmation n'est affichée, le lot est inchangé. Le texte du message a été changé après le premier essai (voir L26). Confirmé par L28 : aucune correction écrite sur `ESSAI-12A-L2`. |
| L23 | Motif « Autre » sans commentaire : l'erreur s'affiche sous le champ du commentaire. | Observé le 2026-11-12, en `supervisor-test`, sur `ESSAI-12A-L2` : **divergence avec la prévision**. Le motif « Autre » sans commentaire est refusé (erreur 50408 : « Le motif « Autre » demande un commentaire. »), mais le message s'affiche dans le bandeau rouge en haut du formulaire, et non sous le champ du commentaire : l'interface ne place sous un champ que les erreurs de forme (`fieldErrors`) de l'API, et traite les erreurs qui ont un code (`errorCode`) comme des messages du formulaire entier. La prévision de la colonne précédente est donc fausse, le comportement de l'interface est volontaire ; il a été conservé. Les valeurs tapées sont conservées, le lot est inchangé (confirmé par L28). |
| L24 | Les heures de l'historique et du formulaire sont en UTC ; l'heure envoyée à l'API se termine par `Z`. | Observé le 2026-11-12. Les heures de l'historique et du formulaire portent « UTC » sur toutes les captures. Heure envoyée : dans l'onglet Réseau des outils du navigateur, la requête `replace` de la correction de `ESSAI-12A-L1` (emballage, 462 kg, vers 11:36 UTC) a pour corps `{"stationCode":"ESSAI-12A-S2","quantityKg":462,"occurredAt":"2026-11-10T13:40:00Z","reasonCode":"DATA_ENTRY_ERROR","reasonComment":""}` : `occurredAt` se termine par `Z`. L'horloge du PC est à l'heure UTC ; l'affichage seul ne distinguait donc pas un décalage, c'est le corps de la requête qui le prouve. Seul l'onglet « Payload » a été montré (pas les en-têtes, qui contiennent le jeton). |
| L25 | Aucun jeton brut ni mot de passe dans les fichiers du lot : recherche de `eyJ`, de `password` et de `secret` dans les fichiers modifiés ou nouveaux, et dans `identity/traceability-realm.json`. | Observé le 2026-11-12 vers 11:30 UTC, sur les fichiers du dossier du dépôt (les fichiers modifiés ou nouveaux du lot, et `identity/traceability-realm.json`). `eyJ` (casse exacte) : uniquement dans `docs/verification.md`, dans du texte qui décrit cette recherche, jamais dans un autre fichier. `password` et `secret`, sur les lignes ajoutées : une seule, la ligne L25 de ce tableau ; fichiers nouveaux : aucun résultat ; `identity/traceability-realm.json` : aucun résultat pour `password`, `secret`, `credentials` ni `eyJ`. |
| L26 | Le refus de l'erreur 50304 (quantité hors des limites des étapes voisines) : sur `ESSAI-12A-L2`, remplacer la quantité du Tri par 501 (motif « Erreur de saisie »). Le message doit être clair pour tous les cas : il dit ce qui est refusé dans chaque sens. | Observé. Premier essai (2026-11-12, vers 10:38 UTC) avec l'ancien texte : bandeau rouge « La quantité doit rester entre celle de l'étape précédente et celle de l'étape suivante. », quantité 501 conservée dans le champ, lot inchangé ; jugé peu clair à la lecture (on ne sait pas par rapport à quoi, et le dernier mouvement n'a pas d'étape suivante). Le texte est changé en « La quantité ne peut pas dépasser celle de l'étape précédente, ni être inférieure à celle de l'étape suivante. » ; relu dans l'interface le 2026-11-12 vers 10:52 UTC, après rechargement de la page et nouvelle connexion de `supervisor-test` : le bandeau rouge donne exactement ce texte, la quantité 501 reste dans le champ, aucune confirmation n'est affichée, le lot reste à 470,00 kg (Trié) avec le même parcours. |
| L27 | Sur un lot dont l'expédition est annulée (statut « Emballé »), la correction d'un autre mouvement n'affiche pas le message pour le destinataire. | Observé le 2026-11-12 vers 11:26 UTC, en `supervisor-test`, sur `ESSAI-12A-L1` (« Emballé », expédition annulée) : l'emballage passe de 464 à 463 kg (« Erreur de saisie »). « Correction enregistrée. » s'affiche en vert, sans bandeau jaune ; le lot est à 463,00 kg (« Emballé »), l'emballage porte « Corrigé » et « saisie : 465,00 kg », l'expédition reste « Annulé » ; l'historique compte une ligne de plus (12/11/2026 11:26:02 UTC). Même cas couvert par un test (`gives no message for the recipient when the shipment was cancelled before`), qui a réussi aux deux lancements de `npm test` (L14). |
| L28 | Contrôle final dans SQL Server, après tout l'essai : nombre de corrections par lot `ESSAI-12A-%` (jointure `Batch`, `Movement`, `MovementCorrection` sur `TraceabilityTest`). `ESSAI-12A-L1` doit en avoir 5 et `ESSAI-12A-L2` aucune, ce qui prouve que les refus de L22 et L23 n'ont rien écrit. | Observé le 2026-11-12 vers 11:38 UTC, dans SSMS : `ESSAI-12A-L1` = 5 (expédition remplacée, expédition annulée, emballage 464, 463 puis 462) ; `ESSAI-12A-L2` = 0. |
| L29 | Le script `database/901_trial_data_lot12a.sql` recrée les données de l'essai de l'interface : une ferme, trois stations avec leurs fonctions, un lot expédié (460 kg) et un lot trié (470 kg). | Observé le 2026-11-12 vers 11:52 UTC, dans SSMS sur `TraceabilityTest`, avec le préfixe `ESSAI-REJEU` à la place de `ESSAI-12A` (pour ne pas toucher aux lots de l'essai), le fichier n'étant pas sauvegardé avec ce changement. Le script s'exécute sans erreur (« Exécution de requête réussie ») : `ESSAI-REJEU-F1` (ferme), `ESSAI-REJEU-S1`, `-S2` et `-S3` (stations), puis la dernière requête donne `ESSAI-REJEU-L1` `SHIPPED` 460.00 et `ESSAI-REJEU-L2` `SORTED` 470.00. Les noms de la ferme et des stations, la région et l'identifiant de l'auteur sont ceux du script : ils peuvent différer des données créées à la main pendant la séance. Les lots `ESSAI-REJEU` restent dans la base jusqu'au prochain `dotnet test`. |
| L30 | CI : une fois la branche poussée, les trois contrôles `backend`, `frontend` et `docker` sont verts sur la branche, puis sur `main` après la fusion. | Observé le 2026-11-12, sur GitHub (onglet Actions et page de la pull request n° 27, captures). Premier push (commit `8a8dba3`, vers 12:26 UTC) : exécution n° 74. **Tentative 1 : `backend` rouge** après 1 min 6 s, à l'étape Build, sur le SDK 11.0.100 (`dotnet --version` du runner), erreur `Microsoft.NET.Sdk.StaticWebAssets.JSModules.targets(233,3)` dans `Traceability.IntegrationTests.csproj` ; `frontend` et `docker` verts ; aucun test n'a démarré. **Tentative 2 : verte**, sur le SDK 10.0.404, `backend` 1 min 4 s (exécution entière 1 min 10 s). L'exécution n° 73 de `main` (commit `19429fe`, d'avant le lot), relancée : verte sur le SDK 10.0.404, `backend` 57 s. Après l'ajout de `global.json` (commit `b76fbb0`) : exécution n° 75 (`push`), verte en 1 min 2 s (`backend` 58 s, `frontend` 31 s, `docker` 27 s). Pull request n° 27 : exécution n° 76 (`pull_request`, 1 min 17 s) et 6 contrôles réussis sur la page. Après la fusion : exécution n° 77 sur `main` (commit de fusion `7d3e198`, 1 min 6 s), verte. Pourquoi les runners diffèrent, et que `global.json` protège sur une machine qui a le SDK 11 : non prouvé (ADR 0009, note du 2026-11-12). `.github/` n'est pas modifié. |

### 22.3 Ce qui n'est pas essayé

Écrit avant l'essai de l'interface.

- Deux appels HTTP lancés réellement en même temps sur le même lot : le verrou est observé en SQL avec une transaction tenue ouverte à la main (L12), pas par deux requêtes de l'API. Le comportement sans `UPDLOCK` n'est pas essayé : on ne sait pas ce que le verrou apporte en plus de la modification faite par le premier appel.
- `019` et la nouvelle version de `005` et `017` ne sont pas rejoués sur `TraceabilityDev` : la décision d'y toucher, ou non, n'est pas prise. `007` n'est jamais rejoué et `018` reste en essai à blanc (`@keep = N'NO'`).
- La CI : non vue au moment de l'essai de l'interface (la branche n'était pas poussée) ; observée ensuite, voir L30.
- L'interface sur un autre navigateur que celui de l'essai, dans plusieurs onglets, ou avec un jeton qui expire pendant la saisie d'une correction.
- Le copier du message au destinataire dans un vrai navigateur : les tests automatiques utilisent un presse-papiers simulé, seul L20 l'essaie.
- La visibilité du nom de l'auteur d'une correction : tous les rôles qui lisent le voient, comme pour les mouvements ; ce choix sera rediscuté à la fin du lot.
- L'envoi du message au destinataire : l'application n'envoie rien et ne garde aucune trace de la transmission.

### 22.4 Ce qui est prouvé

Écrit le 2026-11-12, après l'essai de l'interface.

- **Le journal n'est jamais modifié** : une correction est une ligne à part dans `trace.MovementCorrection`, avec les vrais comptes comme auteurs (L8).
- **La base** : `003` réussit ses 31 tests, `006` ses 88 tests (81 « OK » et 7 lignes « à vérifier à l'œil », toutes relues) (L1).
- **Les tests automatiques** : 301 tests en C# (L3) et 297 tests pour l'interface (L14). Le premier lancement des tests de l'interface a eu 3 dépassements de temps sur un PC chargé ; le second a réussi sans échec.
- **Les tests détectent les trois casses essayées**, les fichiers étant remis à l'identique (empreintes SHA-256) (L13).
- **Les rôles** : `supervisor` corrige (L7) ; `writer` et `reader` sont refusés (403) sans rien écrire ; `norole` est refusé en lecture (L6, L11).
- **Les refus** : neuf appels refusés avec le code HTTP attendu et le lot inchangé (L9) ; une annulation est définitive (L10).
- **Le verrou** : observé avec deux sessions SQL, la seconde attend la fin de la première (L12).
- **L'interface** : chaque rôle voit ce qu'il doit voir (L16, L17, L18) ; les valeurs corrigées s'affichent avec « saisie : … » et l'historique avec son auteur (L19) ; une annulation s'affiche barrée et le mouvement n'est plus proposé (L21) ; le message pour le destinataire s'affiche et se copie sur un lot expédié, et n'apparaît pas sur un lot dont l'expédition est annulée (L20, L27) ; les refus de l'API s'affichent en français, sans rien écrire dans la base (L22, L23, L26, L28) ; les heures sont en UTC et l'heure envoyée se termine par `Z` (L24) ; aucun jeton ni mot de passe dans les fichiers du lot (L25).
- **Les données de l'essai se recréent** avec `database/901_trial_data_lot12a.sql` (L29).
- **Deux écarts relevés pendant l'essai** : le message pour le destinataire apparaissait à tort sur un lot dont l'expédition était annulée (corrigé, 1 test ajouté, L20 et L27) ; l'erreur 50408 s'affiche en haut du formulaire et non sous le champ du commentaire, ce qui est le comportement voulu de l'interface (L23).
- **La CI est verte** sur la branche (exécutions n° 75 et 76) et sur `main` après la fusion (n° 77) (L30). Une première tentative de la n° 74 avait échoué sur le SDK 11.0.100 ; le même commit a réussi sur le SDK 10.0.404 : l'échec dépend de la machine, pas du code. Elle reconstruit la base avec `002` et ne rejoue pas `019` ; elle n'utilise ni Keycloak ni vrai jeton : elle ne prouve pas ces points.
- **Non prouvé** : tout ce qui figure en 22.3.

### 22.5 Rejouer la vérification

Dans PowerShell et SSMS. Les mots de passe sont tapés dans la console de Keycloak ou dans une saisie masquée, jamais dans un message ni un fichier ; un jeton n'est jamais collé.

**1. Base de données** : `002` pour une base neuve, ou `019` pour une base existante (jusqu'ici seulement sur `TraceabilityTest`) ; rejouer `005` et `017` ; puis `003` et `006`.

**2. Tests automatiques**, API arrêtée et rien d'autre en parallèle : `dotnet test Traceability.slnx` depuis la racine (301 tests attendus), puis `npm run lint`, `npm run build` et `npm test` depuis `web/` (297 tests attendus). Si des tests de l'interface dépassent le temps (« Test timed out »), relancer `npm test` sans autre programme ouvert. `dotnet test` vide `TraceabilityTest` au début : les données de l'essai sont à recréer ensuite.

**3. Keycloak, API et interface** : comme en 20.5, le rôle `supervisor` étant dans `identity/traceability-realm.json` ; créer à la main le compte `supervisor-test` avec ce rôle (et `reader-test`, `writer-test`, `norole-test`). L'API est lancée sur `TraceabilityTest` (`ConnectionStrings__Default` copiée de `ConnectionStrings__Test`, avec `Authentication__Authority` et `Authentication__Audience`), puis l'interface avec `npm run dev`.

**4. Données** : exécuter `database/901_trial_data_lot12a.sql` dans SSMS (il refuse toute base autre que `TraceabilityTest` ; son en-tête dit comment changer le préfixe des codes). Il crée la ferme `ESSAI-12A-F1`, trois stations, le lot `ESSAI-12A-L1` (expédié, 460 kg) et le lot `ESSAI-12A-L2` (trié, 470 kg). Le dernier tableau affiché doit montrer `SHIPPED` 460.00 et `SORTED` 470.00 (L29).

**5. L'essai** (L16 à L28) : dans une fenêtre de navigation privée, se connecter en `supervisor-test`, `writer-test` puis `reader-test`. Un F5 ou une adresse tapée déconnecte : naviguer en cliquant. `ESSAI-12A-L2` ne doit recevoir aucune correction réussie ; les corrections réussies se font sur `ESSAI-12A-L1`. Pour L24, ouvrir les outils du navigateur (F12, onglet Network, filtre vide) avant d'enregistrer la correction, et ne montrer que l'onglet Payload de la requête `replace` (les en-têtes contiennent le jeton).

**6. Contrôle SQL final** (L28) : le nombre de corrections par lot `ESSAI-12A-%` (jointure `Batch`, `Movement`, `MovementCorrection`). Attendu après l'essai décrit ici : 5 pour `ESSAI-12A-L1`, 0 pour `ESSAI-12A-L2`.

**7. Secrets** : `git grep -n --untracked "eyJ"` ne doit montrer que du texte de ce document ; la recherche de `password` et `secret` dans les lignes ajoutées et dans `identity/` ne doit rien montrer de réel.

## 23. Lot 12b : la correction de la fiche du lot

Écrit le 2026-11-16, **avant** l'essai à la main avec de vrais jetons. Les lignes M1 à M3 (base de données, tests en C#, tests de l'interface) ont été observées avant d'être écrites : elles n'ont pas de prédiction préalable, et leur résultat vient des affichages des séances des 2026-11-14 et 2026-11-15. Les lignes M4 à M21 sont écrites avant l'essai : leur colonne « À observer » dit ce qu'on s'attend à voir, et leur résultat reste « Non observé » tant que la ligne n'a pas été vue. Une ligne dont ce qu'on a vu diffère de la prévision sera notée telle quelle, avec la différence. Le lot 12b modifie la base (table `trace.BatchCorrection`, procédure `CorrectBatch`, et les procédures de `005`), l'API, les tests, l'interface et le fichier de réglages de Keycloak ; la CI (`.github/workflows/ci.yml`) n'est pas touchée. Les sections 23.4 « Ce qui est prouvé » et 23.5 « Rejouer la vérification » ont été écrites le 2026-11-16, après l'essai ; la ligne M20 (CI) reste « Non observé » tant que la branche n'est pas poussée. L'ordre des heures des mouvements est le lot 12c : il n'est pas commencé.

### 23.1 Ce qui est essayé

- L'état courant du lot reste dans `trace.Batch` (code, ferme, variété, jour de récolte). Une correction de la fiche ne l'écrase pas en silence : `trace.BatchCorrection` garde, ligne par ligne et sans jamais les modifier, l'ancienne et la nouvelle valeur des quatre champs, le motif, le commentaire, l'auteur (identifiant et nom, lus dans le jeton) et l'heure. `CorrectBatch` met à jour le lot et écrit la ligne dans une seule transaction, avec le même verrou `UPDLOCK` que les autres procédures sur le lot corrigé (ADR 0003).
- Règles : les quatre champs sont obligatoires ; des valeurs identiques aux valeurs actuelles sont refusées (50308) ; un changement de casse seul est accepté ; un lot peut reprendre son propre ancien code ; un code porté par un autre lot est refusé (50202) ; un code qui est l'ancien code d'un autre lot est refusé (50203, un numéro déjà utilisé pour « la station a déjà cette fonction » : chaque formulaire de l'interface donne donc son propre texte) ; ferme inconnue (50101) ; lot inconnu (50100) ; le jour de récolte ne peut pas être après le jour de la réception (50309, aussi à la création d'un lot et quand on déplace la réception avant le jour de récolte). Motifs : seulement `DATA_ENTRY_ERROR` et `OTHER` (50407), commentaire obligatoire pour `OTHER` (50408), 500 caractères au plus (50409, que l'API ne laisse pas atteindre : elle refuse d'abord par une erreur de forme 400 sur `reasonComment`).
- Un lot est lu par son code actuel, sinon par un de ses anciens codes (la réponse porte le code actuel dans `batchCode`). Une écriture (ajout de mouvement, remplacement, annulation, correction de la fiche) faite avec un ancien code est refusée : erreur 50104 (404), dont le message cite le nouveau code.
- L'index unique `UQ_Batch_BatchCode` (codes actuels seulement) départage deux lots corrigés vers le même nouveau code au même instant : une réponse 201 et une réponse 409 (50202). Deux lots qui prennent le même **ancien** code au même instant ne sont protégés par rien.
- Nouveau rôle Keycloak `auditor` : il lit tout, y compris les noms des auteurs, et ne peut ni écrire ni corriger. `supervisor` lit, corrige et voit les noms. `reader` et `writer` lisent, mais reçoivent `authorName` à `null` : **changement de comportement**, ils voyaient ces noms depuis le lot 11. `authorId` n'est jamais renvoyé. La politique `CanSeeAuthors` (`auditor` ou `supervisor`) est évaluée par le contrôleur.
- Route `POST /batches/{batchCode}/correct`, réservée à `supervisor` : corps `newBatchCode`, `farmCode`, `variety`, `harvestDate`, `reasonCode`, `reasonComment` ; réponse 201 sans corps, `Location` vers le nouveau code. `GET /batches/{batchCode}` gagne `sheetCorrections` ; `corrections` reste la liste des corrections de mouvements.
- Interface : pour `supervisor`, la section « Corriger la fiche » (4 champs préremplis, deux motifs seulement) ; pour tous les rôles qui lisent, la section « Corrections de la fiche », qui liste les champs changés ; les colonnes d'auteur disparaissent quand l'API n'envoie aucun nom ; après un changement de code, la page passe à la nouvelle adresse, et elle remplace un ancien code de l'adresse par le code actuel ; si le lot était expédié, un message à copier pour le destinataire (l'application ne l'envoie pas et ne garde aucune trace de l'envoi).
- Scripts : `002` (bases neuves) et `020` (base existante) créent la table, `005` les procédures, `003` (43 tests) et `006` (122 tests) sont étendus, et `902` crée les données de l'essai (sur `TraceabilityTest` seulement ; chaque `dotnet test` les efface).

### 23.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| M1 | Base : `003` (43 tests) et `006` (122 tests) sur `TraceabilityTest` ; sur `TraceabilityDev` : `019`, `020`, `005`, `017`, puis `003` et `008`, nombres de lignes inchangés. | Observé le 2026-11-14 (sans prédiction préalable). `003` 43 sur 43 et `006` 122 sur 122 sur `TraceabilityTest`. Sur `TraceabilityDev` : `019` et `020` créent leur table, `005` affecte 13 lignes et liste 13 procédures, `017` ne fait rien (« already exists »), puis `003` 43 sur 43 (27 s) et `008` 28 sur 28 (22 s), nombres de lignes inchangés. Les durées de `019`, `020` et `005` n'ont pas été relevées. |
| M2 | C# : `dotnet build`, `dotnet test` sur les tests unitaires et sur les tests d'intégration, dont le test de concurrence (deux corrections vers le même code). | Observé le 2026-11-14 (sans prédiction préalable). Build réussi (55,4 s) ; 116 tests unitaires et 240 tests d'intégration, tous réussis, soit 356 (301 avant le lot) ; le test de concurrence a réussi dans la série complète puis trois fois relancé seul, soit 4 passages. |
| M3 | Interface : `npm run lint`, `npm run build`, `npm test` depuis `web/`. | Observé le 2026-11-15 vers 20:35 UTC (sans prédiction préalable). `npm run lint` : 0 avertissement, 0 erreur (97 fichiers, 116 règles). `npm run build` réussi. `npm test` : 33 fichiers, 332 tests réussis, 0 échec (297 avant le lot, 35 ajoutés). |
| M4 | Keycloak recréé avec le fichier de réglages modifié : le journal affiche `Realm 'traceability' imported` sans `WARN` ni `ERROR` ; la console montre quatre rôles (`reader`, `writer`, `supervisor`, `auditor`) ; cinq comptes créés à la main (`reader-test`, `writer-test`, `supervisor-test`, `auditor-test`, `norole-test`), chacun avec son rôle. | Observé le 2026-11-16. Keycloak recréé avec le fichier de réglages : le journal affiche l'import du realm (66,364 s) sans `WARN` ni `ERROR` (relu par Mohamed) ; la console montre quatre rôles (`reader`, `writer`, `supervisor`, `auditor`) ; cinq comptes créés à la main, chacun avec son rôle. |
| M5 | Contenu des jetons (`Show-Token`) : `auditor-test` a le rôle `auditor` et ni `writer` ni `supervisor` ; les quatre autres comptes comme au lot 12a ; `aud` et `iss` corrects ; sans jeton : 401. | Observé le 2026-11-16. Jetons demandés pour les cinq comptes (`Get-Trial`) et décodés (`Show-Token`) : `auditor-test` a le rôle `auditor` et ni `writer` ni `supervisor` ; les quatre autres comptes ont les rôles prévus ; `iss` et `aud` corrects ; lecture sans jeton : 401. Conforme à la prévision. |
| M6 | `902` rejoué dans SSMS sur `TraceabilityTest` : le dernier tableau montre `ESSAI-12B-L1` `SHIPPED` 460 (Roma) et `ESSAI-12B-L2` `SORTED` 470 (Cherry), tous deux de la ferme `ESSAI-12B-F1`, récolte le 2026-11-10. | Observé le 2026-11-16 à 09:18 UTC. `902` rejoué dans SSMS : le dernier tableau a 2 lignes, `ESSAI-12B-L1` `SHIPPED` 460 (Roma) et `ESSAI-12B-L2` `SORTED` 470 (Cherry), ferme `ESSAI-12B-F1`, récolte le 2026-11-10. |
| M7 | API, vrais jetons, lecture de `ESSAI-12B-L1` : avec `reader-test` et `writer-test`, `authorName` vaut `null` partout et aucun `authorId` n'apparaît ; avec `auditor-test` et `supervisor-test`, il vaut « Donnees SQL (essai) » ; avec `norole-test` : 403. | Observé le 2026-11-16. Lecture de `ESSAI-12B-L1` : sans jeton, 401 ; avec `auditor-test` et `supervisor-test`, les noms des auteurs sont donnés ; avec `reader-test` et `writer-test`, `authorName` vaut `null` (vérifié dans le texte brut de la réponse : `"authorName":null` quatre fois, `authorId` zéro fois, car PowerShell affiche `null` et un texte vide de la même façon) ; avec `norole-test` : 403. Conforme à la prévision. |
| M8 | `auditor-test` : lecture 200 ; ajout de mouvement et correction de la fiche : 403. `writer-test` et `reader-test` : correction de la fiche : 403. Le lot reste identique. | Observé le 2026-11-16. `auditor-test` : ajout de mouvement 403 et correction de la fiche 403 ; `writer-test` : correction de la fiche 403 ; `reader-test` : ajout 403 et correction 403. Conforme. Que rien n'a été écrit est confirmé par M18 (aucune ligne en trop). |
| M9 | Interface, `supervisor-test`, page de `ESSAI-12B-L2` : la section « Corriger la fiche » est là avec `ESSAI-12B-L2`, `ESSAI-12B-F1`, `Cherry` et `2026-11-10` dans les champs, et deux motifs seulement (« Erreur de saisie », « Autre ») ; « Corriger un mouvement » aussi ; pas d'« Ajouter un mouvement ». | Observé le 2026-11-16. `supervisor-test`, page de `ESSAI-12B-L2` : « Corriger la fiche » est là avec les valeurs de la fiche dans les champs, « Corriger un mouvement » aussi, et pas « Ajouter un mouvement ». Le champ Motif propose « Erreur de saisie » et « Autre » : les deux choix ont été vus un par un (la liste ouverte n'a pas pu être capturée) ; qu'il n'y en ait pas un troisième est aussi prouvé par un test automatique (la liste vaut `DATA_ENTRY_ERROR`, `OTHER`). Conforme à la prévision. |
| M10 | Interface, `writer-test`, `reader-test` et `auditor-test` : ni « Corriger la fiche » ni « Corriger un mouvement ». Le `writer` garde « Ajouter un mouvement ». | Observé le 2026-11-16, avec une capture par rôle. `writer-test`, `reader-test` et `auditor-test` : ni « Corriger la fiche » ni « Corriger un mouvement » ; le `writer` garde « Ajouter un mouvement ». Conforme à la prévision. |
| M11 | Interface : la colonne « Auteur » (et « Corrigé par » dans les historiques) est visible pour `auditor-test` et `supervisor-test`, absente pour `writer-test` et `reader-test`. | Observé le 2026-11-16. La colonne « Auteur » du tableau des mouvements est visible pour `auditor-test` et `supervisor-test`, absente pour `writer-test` et `reader-test`. Après M12, la colonne « Corrigé par » de la section « Corrections de la fiche » est visible pour le superviseur et absente pour un compte `writer` ou `reader` (`writer-test` ou `reader-test` : le compte regardé n'est pas noté). Conforme à la prévision. |
| M12 | `supervisor-test` change la variété de `ESSAI-12B-L2` (`Cherry` en `Cherry rouge`, « Erreur de saisie ») : « Fiche corrigée. » s'affiche ; la section « Corrections de la fiche » a une ligne avec « Variété : Cherry → Cherry rouge » et « Corrigé par supervisor-test » ; pas de message pour le destinataire (lot « Trié »). | Observé le 2026-11-16. `supervisor-test` change la variété de `ESSAI-12B-L2` de `Cherry` à `Cherry rouge`, motif « Erreur de saisie » : « Fiche corrigée. » s'affiche ; la section « Corrections de la fiche » a une ligne « Variété : Cherry → Cherry rouge » et « Corrigé par supervisor-test » ; pas de message pour le destinataire (lot « Trié »). Conforme à la prévision. |
| M13 | Sur `ESSAI-12B-L1` (expédié), `supervisor-test` change la ferme (`ESSAI-12B-F1` en `ESSAI-12B-F2`, « Autre » avec un commentaire) : le message pour le destinataire apparaît avec « Ferme : ESSAI-12B-F1 → ESSAI-12B-F2 » et le motif ; « Copier le message » répond « Message copié. » et le texte collé dans le Bloc-notes est identique à celui de l'écran. | Observé le 2026-11-16. Sur `ESSAI-12B-L1` (expédié), `supervisor-test` change la ferme de `ESSAI-12B-F1` à `ESSAI-12B-F2` : le message pour le destinataire apparaît avec « Ferme : ESSAI-12B-F1 → ESSAI-12B-F2 » ; le texte copié avec « Copier le message » et collé dans le Bloc-notes est identique à celui de l'écran. **Différence avec la prévision** : le motif choisi a été « Erreur de saisie » sans commentaire (relevé en M18), et non « Autre » avec un commentaire ; le cas « Autre » avec commentaire est essayé en M15. |
| M14 | `supervisor-test` change le code de `ESSAI-12B-L2` en `ESSAI-12B-L2B` : la barre d'adresse montre `/batches/ESSAI-12B-L2B`, le titre est « Lot ESSAI-12B-L2B », « Fiche corrigée. » reste affiché, l'historique a deux lignes dont « Code : ESSAI-12B-L2 → ESSAI-12B-L2B ». | Observé le 2026-11-16. `supervisor-test` change le code de `ESSAI-12B-L2` en `ESSAI-12B-L2B` : la barre d'adresse passe à `/batches/ESSAI-12B-L2B`, le titre est « Lot ESSAI-12B-L2B », « Fiche corrigée. » reste affiché et l'historique a deux lignes, dont « Code : ESSAI-12B-L2 → ESSAI-12B-L2B ». Conforme à la prévision. |
| M15 | Sur la nouvelle adresse, sans recharger la page, une nouvelle correction (variété de retour à `Cherry`, « Autre » avec un commentaire) est acceptée : pas d'erreur 50104. | Observé le 2026-11-16. Sur la nouvelle adresse, sans recharger la page, une nouvelle correction de `ESSAI-12B-L2B` (variété, motif « Autre », commentaire « essai retour vareite ») est acceptée, sans erreur 50104. **Différence avec la prévision** : la variété tapée n'était pas `Cherry` mais `Cherry ` avec un espace à la fin (relevé en M18, confirmé par Mohamed). |
| M16 | Six refus affichés en français, sur `ESSAI-12B-L1`, avec les valeurs tapées conservées et rien d'écrit : code `ESSAI-12B-L2B` (« Un lot porte déjà ce code. ») ; code `ESSAI-12B-L2`, ancien code de L2 (« Ce code est l'ancien code d'un autre lot. ») ; récolte le 2026-11-11 (« La date de récolte ne peut pas être après le jour de la réception. ») ; aucune valeur changée (« Les nouvelles valeurs sont identiques aux valeurs actuelles : rien à corriger. ») ; ferme `ZZ-NOFARM` (« Ferme introuvable. ») ; « Autre » sans commentaire (« Le motif « Autre » demande un commentaire. », dans le bandeau rouge, comme en 22 L23). | Observé le 2026-11-16. Les six refus s'affichent en français avec les messages prévus, mot pour mot : « Un lot porte déjà ce code. », « Ce code est l'ancien code d'un autre lot. », « La date de récolte ne peut pas être après le jour de la réception. », « Les nouvelles valeurs sont identiques aux valeurs actuelles : rien à corriger. », « Ferme introuvable. », « Le motif « Autre » demande un commentaire. » (dans le bandeau rouge). Pour le sixième, les valeurs étant inchangées, la règle du commentaire a répondu avant celle des valeurs identiques. Que rien n'a été écrit est confirmé par M18 ; que les valeurs tapées restent dans le formulaire n'a pas été noté pendant l'essai et n'est couvert que par les tests automatiques (« keeps what was typed »). |
| M17 | API, vrais jetons : lire `ESSAI-12B-L2` (ancien code) répond 200 avec `batchCode` = `ESSAI-12B-L2B` ; ajouter un mouvement avec l'ancien code (`writer-test`) répond 404, erreur 50104, dont le détail cite `ESSAI-12B-L2B` ; rien n'est écrit. | Observé le 2026-11-16. Avec `writer-test` : lecture de `ESSAI-12B-L2` (ancien code) : HTTP 200, `batchCode` = `ESSAI-12B-L2B` ; ajout d'un mouvement avec l'ancien code (480 kg, donc de toute façon impossible) : HTTP 404, erreur 50104, détail « Batch code 'ESSAI-12B-L2' was replaced by 'ESSAI-12B-L2B'. » Conforme à la prévision. Rien n'est écrit (confirmé par M18). |
| M18 | SQL, contrôle final sur `TraceabilityTest` : `trace.BatchCorrection` a 4 lignes pour les lots `ESSAI-12B-%` (`ESSAI-12B-L1` : 1 ; `ESSAI-12B-L2` : 3), auteur `supervisor-test` avec son vrai identifiant (comparé à la console de Keycloak) ; les anciennes valeurs sont conservées ; `trace.Batch` est à jour (code `ESSAI-12B-L2B`, ferme `ESSAI-12B-F2` pour L1) ; les 6 mouvements de `trace.Movement` sont inchangés ; les refus de M16 n'ont rien écrit. | Observé le 2026-11-16 (lecture seule, SSMS). `trace.BatchCorrection` a 4 lignes pour `ESSAI-12B-%` : `ESSAI-12B-L1` 1 (ferme F1 → F2), `ESSAI-12B-L2B` 3 (variété `Cherry` → `Cherry rouge` ; code `ESSAI-12B-L2` → `ESSAI-12B-L2B` ; variété `Cherry rouge` → `Cherry ` avec le motif `OTHER` et le commentaire « essai retour vareite »). Auteur `supervisor-test`, identifiant `2aa7b77f-9cdb-4553-94d1-886e7892a3de`, identique à l'ID de ce compte dans la console de Keycloak ; les anciennes valeurs sont conservées. `trace.Batch` est à jour (L1 ferme F2, `SHIPPED` 460 ; L2B ferme F1, `SORTED` 470). Les 6 mouvements sont inchangés (4 pour L1, 2 pour L2B, tous de « Donnees SQL (essai) »). **Différence avec la prévision** : la variété finale de L2B est `Cherry ` avec un espace à la fin (`LEN` 6, `DATALENGTH`/2 = 7) : ni l'interface, ni l'API, ni la procédure ne retirent les espaces autour d'une variété, la création d'un lot non plus ; noté en « Non prouvé ou ouvert » et laissé hors du lot 12b (décision de Mohamed). |
| M19 | Trois casses volontaires, avec empreintes SHA-256 avant et après (`Get-FileHash -Algorithm SHA256`) : (1) `canSeeAuthors` toujours vrai (`src/Traceability.Api/Controllers/BatchesController.cs`, ligne 155) ; (2) `correct` demande `CanWrite` au lieu de `CanCorrect` (même fichier, ligne 365) ; (3) `hasAuthors` toujours vrai (`web/src/pages/BatchPage.tsx`, ligne 44). Prévision : des tests échouent à chaque casse, dont `The_names_of_the_authors_are_given_to_the_auditor_and_the_supervisor_only` (1), `Only_a_supervisor_may_correct_a_sheet` (2) et `leaves out the columns of the authors when the API sends no name` (3) ; les nombres d'échecs ne sont pas prévus ; après chaque remise en état, l'empreinte revient à celle d'avant et les tests repassent (356 en C#, 332 pour l'interface). | Observé le 2026-11-16. Casse 1 : `BatchesController.cs` passe de `A768348858A2C6916876B9729071AC40A9EA7F19DB8E0797AF7AB6025CE102C3` à `01575DA2980281107B2418A6BA2B53113569735771345F61ED2619EA73480355` ; `dotnet test` : 356 tests, 2 échecs, `The_names_of_the_authors_are_given_to_the_auditor_and_the_supervisor_only` pour `reader` et `writer` (attendu `null`, reçu le nom). Casse 2 : même fichier, `44DE6394BABB8D4697F39CB149C3449182E02298F3AF706CEAD3259CCD973B4C` ; 356 tests, 31 échecs : `Only_a_supervisor_may_correct_a_sheet` pour `writer` (attendu 403, reçu 201), 2 tests d'autorisation de la route `correct`, et 28 autres tests de `SheetCorrectionsTests` où le superviseur, qui n'a pas `CanWrite`, reçoit 403 au lieu de la réponse attendue. Casse 3 : `BatchPage.tsx` passe de `5AD1338DDB6476F2635BC0E68EFDD8174744472FDC07427B9968E467716657FB` à `6854FCCD8EB9F7FE8DB8D580EDECD498C3091563629B901D12567E65BC86BD3B` ; série complète : 332 tests, 3 échecs, `leaves out the columns of the authors when the API sends no name` et deux tests qui ont dépassé leur délai (`sends the home page to the batches`, `opens the batch under its new code…`) ; les deux fichiers concernés relancés seuls, casse en place : 22 tests, un seul échec (le test des colonnes), 21 réussis. Après chaque remise en état, l'empreinte est revenue à celle d'avant et la série complète est repassée (356 tests C#, 332 tests web, 0 échec). Un premier passage après la remise en état de la casse 1 a encore donné 2 échecs : le fichier remis en état gardait une date de modification plus ancienne que le programme compilé, donc la compilation n'a pas été refaite ; après mise à jour de la date, 356 réussis. `git status --short` ne montre ensuite que `docs/verification.md`. Conforme à la prévision (les nombres d'échecs n'étaient pas prévus). |
| M20 | CI : une fois la branche poussée, les trois contrôles `backend`, `frontend` et `docker` sont verts sur la branche, puis sur `main` après la fusion. | Observé le 2026-11-16, après la fusion, dans l'onglet Actions de GitHub. Trois exécutions du workflow CI, toutes vertes : n° 81, push de la branche (commit `56572ba`), 1 min 9 s ; n° 82, pull request n° 29, 1 min 47 s ; n° 83, push sur `main` après la fusion (commit `c5550da`), 1 min 26 s, avec `backend` 1 min 23 s, `frontend` 40 s et `docker` 31 s. Le détail des tâches n'a été relevé que pour la n° 83 ; pour les n° 81 et 82, seule la coche verte du workflow entier est vue. Dans le journal de `backend` de la n° 83, `006` donne `tests_total` 122, `tests_ok` 114 et `tests_by_eye` 8 : `006` a donc tourné sur la base neuve de la CI (recréée par `002`). Les nombres de tests de `dotnet test` et de Vitest dans la CI n'ont pas été relevés. |
| M21 | Aucun jeton brut ni mot de passe dans les fichiers du lot : recherche de `eyJ`, de `password` et de `secret` dans les fichiers modifiés ou nouveaux, et dans `identity/traceability-realm.json`. | Observé le 2026-11-16. Recherche de `eyJ`, de `password` et de `secret` dans les 45 fichiers du lot (les trois commits et ce qui est modifié ou nouveau) : aucun jeton brut (`eyJ` suivi de 8 caractères ou plus : 0 résultat) ; `identity/traceability-realm.json` : aucune occurrence des trois mots ; dans `docs/verification.md`, les lignes avec `eyJ`, `password` ou `secret` sont des phrases ou des commandes (noms de variables, saisies masquées avec `Read-Host … -AsSecureString`, `SQLCMDPASSWORD: ***`), sans aucune valeur ; dans le code, `secret` apparaît dans un commentaire de `Program.cs` (« the API needs no secret ») et dans un texte de test (« secret SQL text »). La recherche sera refaite sur les documents juste avant le commit 4. Rejouée le 2026-11-16 sur les 10 documents du commit 4 une fois écrits (`CLAUDE.md`, `README.md`, les ADR 0015 à 0017, `fonctionnel.md`, `glossaire.md`, `modele-de-donnees.md`, `procedures.md`, `verification.md`) : aucun jeton brut (`eyJ` suivi de 10 caractères ou plus : 0 résultat), aucun mot de passe écrit en clair ; le seul identifiant de compte nouveau est celui de `supervisor-test` (M18). |

### 23.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- **Concurrence.** Deux appels réellement simultanés avec de vrais jetons ne sont pas essayés : le test de concurrence utilise un faux jeton, ne couvre que le cas du code actuel et a été passé 4 fois (M2). Deux lots qui prennent le même **ancien** code au même instant ne sont protégés par aucune contrainte, et ce cas n'est pas testé.
- **Interface.** L'arrivée sur un ancien code tapé dans le navigateur n'est couverte que par un test automatique (taper une adresse déconnecte). Un seul navigateur et un seul onglet sont essayés, sans jeton qui expire pendant la saisie.
- **Base et CI.** `006` sur une base neuve de la CI ne sera connu qu'après le push ; la CI recrée la base avec `002` et ne rejoue pas `020` ; les durées de `019`, `020` et `005` sur `TraceabilityDev` n'ont pas été mesurées.

Ajouté après l'essai, le 2026-11-16.

- **Espace à la fin de la variété.** Une variété tapée avec un espace à la fin est enregistrée telle quelle (`Cherry ` : `LEN` 6, `DATALENGTH`/2 = 7), à la création comme à la correction : ni l'interface, ni l'API, ni les procédures ne retirent les espaces autour des textes. Décidé le 2026-11-16 : hors du lot 12b, à traiter dans un lot à part si on le veut.
- **Deux tests de l'interface lents.** Dans une série complète (206 s sur la machine de l'essai), 2 tests sur 332 ont dépassé leur délai ; ils passent quand on les lance seuls. Cause attribuée à la charge de la machine, non mesurée. Ils pourraient échouer de nouveau, y compris en CI.

### 23.4 Ce qui est prouvé

Écrit le 2026-11-16, après l'essai ; la CI (M20) a été complétée le même jour, après la fusion.

- **Le journal et l'état** : une correction de la fiche est une ligne à part dans `trace.BatchCorrection`, jamais modifiée ; l'état courant est dans `trace.Batch`. Après l'essai : 4 lignes avec l'ancienne et la nouvelle valeur, le vrai compte `supervisor-test` comme auteur (identifiant comparé à la console de Keycloak), et les 6 mouvements inchangés (M18).
- **La base** : `003` réussit ses 43 tests et `006` ses 122 sur `TraceabilityTest` ; sur `TraceabilityDev`, `019`, `020` et `005` sont appliqués, `003` réussit ses 43 tests et `008` ses 28, nombres de lignes inchangés (M1).
- **Les tests automatiques** : 356 tests en C# (M2) et 332 pour l'interface (M3), `npm run lint` et `npm run build` propres ; ils repassent après chaque remise en état (M19).
- **Les tests détectent les trois casses essayées**, les fichiers étant remis à l'identique (empreintes SHA-256) : 2, 31 et 1 échec selon la casse ; les 2 autres échecs de la troisième étaient des dépassements de délai (M19).
- **Les rôles, avec de vrais jetons** : `auditor` lit tout et voit les noms mais ne peut ni ajouter ni corriger ; `supervisor` corrige et voit les noms ; `writer` et `reader` reçoivent `authorName` à `null`, sans `authorId` (vérifié sur le texte brut), et sont refusés en correction (403) ; `norole` est refusé (403) ; sans jeton : 401 (M5, M7, M8).
- **L'interface** : chaque rôle voit ce qu'il doit voir, formulaires et colonnes « Auteur » / « Corrigé par » (M9 à M11) ; une correction s'affiche avec les champs changés, le motif et l'auteur (M12) ; sur un lot expédié, le message pour le destinataire s'affiche et se copie avec un texte identique (M13) ; après un changement de code, la page passe à la nouvelle adresse, garde le message de réussite et accepte une nouvelle correction sans erreur 50104 (M14, M15).
- **Les refus** : six refus affichés en français avec les messages prévus, sans rien écrire (M16, M18).
- **L'ancien code** : une lecture avec un ancien code trouve le lot sous son code actuel (200) ; une écriture est refusée (404, erreur 50104, le détail cite le code actuel) (M17).
- **Aucun jeton ni mot de passe** dans les fichiers du lot, tels qu'ils étaient le 2026-11-16 (M21).
- **Les données de l'essai se recréent** avec `database/902_trial_data_lot12b.sql` (M6).
- **Deux écarts relevés** : le motif choisi en M13 n'était pas celui prévu (sans conséquence pour le lot) ; une variété tapée avec un espace à la fin est enregistrée telle quelle (M15, M18), à la création comme à la correction : hors du lot 12b (23.3).
- **La CI** : verte sur la branche, sur la pull request et sur `main` (M20). `006` a tourné sur la base neuve de la CI et rend 122 tests, dont 114 automatiques et 8 à l'œil. Elle reconstruit la base avec `002` et ne rejoue pas `020` ; elle n'utilise ni Keycloak ni vrai jeton : elle ne prouve pas ces points. Ses nombres de tests C# et d'interface ne sont pas relevés.
- **Non prouvé** : tout ce qui figure en 23.3.

### 23.5 Rejouer la vérification

Dans PowerShell et SSMS. Les mots de passe sont tapés dans la console de Keycloak ou dans une saisie masquée, jamais dans un message ni un fichier ; un jeton n'est jamais collé.

**1. Base de données** : `002` pour une base neuve, ou `019` puis `020` pour une base existante ; rejouer `005` et `017` ; puis `003` et `006`.

**2. Tests automatiques**, API arrêtée et rien d'autre en parallèle : `dotnet test Traceability.slnx` depuis la racine (356 tests attendus), puis `npm run lint`, `npm run build` et `npm test` depuis `web/` (332 tests attendus ; la série dure plus de 3 minutes sur la machine de l'essai). Si des tests de l'interface dépassent le temps (« Test timed out »), relancer ces fichiers seuls, sans autre programme ouvert. `dotnet test` vide `TraceabilityTest` au début : les données de l'essai sont à recréer ensuite.

**3. Keycloak, API et interface** : comme en 20.5 et 22.5, avec le rôle `auditor` de plus dans `identity/traceability-realm.json` (l'import du realm a pris environ une minute) ; créer à la main les cinq comptes `reader-test`, `writer-test`, `supervisor-test`, `auditor-test` et `norole-test`, chacun avec son rôle (`norole-test` sans rôle). L'API est lancée sur `TraceabilityTest`, puis l'interface avec `npm run dev`. `Get-Trial` et `Show-Token` sont ceux de 19.5 ; `Read-Lot` (lecture d'un lot avec le jeton) et `Send-Post` (envoi d'un `POST` avec le jeton) sont de petites fonctions écrites dans la fenêtre PowerShell pour l'essai : elles ne sont pas dans le dépôt.

**4. Données** : exécuter `database/902_trial_data_lot12b.sql` dans SSMS (il refuse toute base autre que `TraceabilityTest` ; son en-tête dit comment changer le préfixe `ESSAI-12B` ; il se rejoue une fois par préfixe). Il crée les fermes `ESSAI-12B-F1` et `ESSAI-12B-F2`, trois stations, le lot `ESSAI-12B-L1` (expédié, 460 kg) et le lot `ESSAI-12B-L2` (trié, 470 kg). Le dernier tableau doit montrer `SHIPPED` 460.00 et `SORTED` 470.00 (M6).

**5. L'essai** (M7 à M17) : dans une fenêtre de navigation privée, se connecter en `supervisor-test`, `writer-test`, `reader-test` puis `auditor-test`. Un F5 ou une adresse tapée déconnecte : naviguer en cliquant. Les corrections réussies se font sur `ESSAI-12B-L1` et `ESSAI-12B-L2`, dans l'ordre de M12 à M15.

**6. Contrôle SQL final** (M18) : lecture seule, les corrections de chaque lot `ESSAI-12B-%` (jointure `Batch`, `BatchCorrection` et `Farm`), l'état de `Batch` et les mouvements. Attendu après l'essai décrit ici : 4 corrections (1 pour `ESSAI-12B-L1`, 3 pour `ESSAI-12B-L2B`) et 6 mouvements.

**7. Casses volontaires** (M19) : relever l'empreinte SHA-256 avant et après (`Get-FileHash -Algorithm SHA256`) ; remettre le fichier **avec une date de modification neuve**, sinon la compilation n'est pas refaite et les tests tournent sur l'ancien programme.

**8. Secrets** (M21) : `git grep -n --untracked "eyJ"` ne doit montrer que du texte de ce document ; la recherche de `password` et `secret` dans les lignes ajoutées et dans `identity/` ne doit rien montrer de réel.

## 24. Lot 12c : l'heure des mouvements

Écrit le 2026-11-20, **avant** l'essai à la main avec de vrais jetons. Les lignes M1 à M5 ont été observées avant d'être écrites : elles n'ont pas de prédiction préalable, et leur résultat vient des séances des 2026-11-16, 2026-11-17 et 2026-11-20. Les lignes M6 à M19 sont écrites avant l'essai : leur colonne « À observer » dit ce qu'on s'attend à voir, et leur résultat reste « Non observé » tant que la ligne n'a pas été vue. Une ligne dont ce qu'on a vu diffère de la prévision sera notée telle quelle, avec la différence. Le lot 12c modifie les procédures de `005`, les tests de `006` (150 tests) et ajoute le script de diagnostic `021` ; l'API (commentaires seulement) ; les tests C# ; deux textes de l'interface et ses tests. Il n'ajoute ni migration, ni table, ni route, et ne touche ni le fichier de réglages de Keycloak ni la CI (`.github/workflows/ci.yml`). Les résultats de M1 à M18 ont été remplis le 2026-11-20, après l'essai, sans modifier les prévisions. La ligne M19 (CI) a été remplie le 2026-11-20 après la fusion, sans modifier la prévision.

### 24.1 Ce qui est essayé

- **Une heure dans le futur est refusée.** `CreateBatch`, `AddMovement` et `ReplaceMovement` refusent une heure qui dépasse de plus de 5 minutes l'horloge de SQL Server (`SYSUTCDATETIME()`, lue au moment du contrôle) : erreur 50310, HTTP 422. Le message cite l'heure refusée et l'heure du serveur. Les 5 minutes sont un choix de conception, pas une valeur mesurée.
- **Une heure hors ordre est refusée.** À l'ajout, l'heure doit être strictement après celle du dernier mouvement valable du lot. Au remplacement, elle doit être strictement après celle du mouvement valable précédent et strictement avant celle du suivant. Une heure égale est refusée. C'est l'erreur 50311 (HTTP 422), un seul numéro pour les deux sens, comme 50304 pour la quantité. Un mouvement « valable » n'est pas annulé et porte la dernière correction appliquée ; les voisins sont trouvés dans l'ordre de `MovementId`.
- **Le remplacement ne contrôle l'heure que si elle change.** Une correction de la quantité ou de la station seule n'est pas bloquée par un vieux désordre : on ne change que ce qu'on corrige. Décision de Mohamed, prise sans délégation.
- **Ce qui ne change pas.** `CancelMovement` n'est pas touchée. Une heure passée reste acceptée (saisie tardive). Les anciennes données ne sont pas modifiées : `021`, en lecture seule, les compte et les liste. L'heure d'origine reste dans `trace.Movement` ; une correction est une ligne de `trace.MovementCorrection` (déjà le cas depuis le lot 12a).
- **L'ordre des contrôles.** Dans `AddMovement` sur un lot expédié, l'erreur 50300 passe avant les contrôles de l'heure. L'heure dans le futur (50310) est contrôlée avant l'ordre (50311).
- **L'API.** `SqlErrorTranslator` traduit déjà toute la famille 503xx en 422 : aucun changement de code. Les tests C# des lots précédents entraient tous les mouvements à la même heure : ils ont été corrigés (`TestData.TimeOfStep` : tri à 08:00, emballage à 09:00, expédition à 10:00), et `MovementTimeTests` ajoute 17 cas.
- **L'interface.** Deux textes dans `web/src/lib/messages.ts` : 50310 (avec le conseil de vérifier l'heure saisie, qui est en UTC, et l'horloge de l'ordinateur) et 50311 (un seul texte pour tous les formulaires). Les formulaires ne changent pas.
- **Scripts.** `005` (les trois procédures), `006` (150 tests, dont 28 nouveaux : 123 à 150), `021` (diagnostic en lecture seule, sur `TraceabilityDev` par défaut).

### 24.2 Liste de contrôle

L'essai se fait sur `TraceabilityTest`, avec les données de `902` rejoué avec `@prefix` = `ESSAI-12C` (changement non enregistré). Ce script crée `ESSAI-12C-L1` (réception 06:30, tri 09:15, emballage 13:40, expédition 17:05, le 2026-11-10 ; expédié, 460 kg) et `ESSAI-12C-L2` (réception 06:30, tri 09:15 ; trié, 470 kg), avec les stations `ESSAI-12C-S1` (réception et tri), `-S2` (emballage) et `-S3` (expédition). Ordre conseillé : M5 à M8, puis **M14 avant M9** (M9 emballe `ESSAI-12C-L2`, après quoi on ne peut plus y ajouter de tri ni d'emballage), puis M9 à M13, M15, M16 et M17 ; chaque `dotnet test` vide `TraceabilityTest` : ne pas en lancer pendant l'essai. Les heures « +10 minutes » se calculent sur l'horloge de l'ordinateur au moment de l'appel.

| N° | À observer | Résultat |
|---|---|---|
| M1 | Base : `005` rejoué sur `TraceabilityTest` (13 procédures listées), puis `006` (150 tests). | Observé le 2026-11-16, avant 22:01 UTC (heure du commit `44846c4` ; l'heure exacte n'a pas été relevée), sans prédiction préalable. `006` : 150 tests, 142 automatiques et 8 à vérifier à l'œil, aucun « ATTENTION », sur deux exécutions. 28 de plus qu'avant le lot (122). |
| M2 | C# : `dotnet test` sur les tests unitaires puis sur les tests d'intégration, API arrêtée. | Observé le 2026-11-17, entre 08:51 et 08:54 UTC (sans prédiction préalable). 118 tests unitaires et 257 tests d'intégration, tous réussis, 0 échec : 375 (356 avant le lot, 19 de plus : 2 pour le traducteur d'erreurs, 17 dans `MovementTimeTests`). Les anciens tests ont été corrigés avant d'être lancés : on n'a jamais vu l'échec qu'on prédisait en lisant le code. |
| M3 | Interface : `npm run lint`, `npm run build`, `npm test` depuis `web/`. | Observé le 2026-11-17 (`npm test` démarré à 09:25:22 UTC, `lint` et `build` juste après), sans prédiction préalable. `lint` : 0 avertissement, 0 erreur (97 fichiers, 116 règles). `build` réussi (`tsc -b`, puis `vite build`). `npm test` : 33 fichiers, 339 tests réussis, 0 échec (332 avant le lot, 7 de plus). |
| M4 | `021` sur `TraceabilityTest` (lecture seule) : compte les mouvements valables hors ordre ou dans le futur. | Observé le 2026-11-16, avant 22:01 UTC, sans prédiction préalable. Résultat `195 75 63 2 1 35` : 195 mouvements valables dans 75 lots, 63 égaux au précédent, 2 avant le précédent, 1 dans le futur, 35 lots avec un problème. La liste montre des lots créés par les tests C# avant leur correction (heures égales) et les lots de `006` (`ZZ-T4`, `ZZ-T10`). Non lancé sur `TraceabilityDev`. |
| M5 | Keycloak 26.6.2 démarré dans Docker (`docker start traceability-keycloak`), les 5 comptes présents dans le realm `traceability`. | Observé le 2026-11-20, sans prédiction préalable. Le conteneur existait (arrêté depuis 2 jours, code de sortie 137). Journal daté du 2026-11-20 08:42:02 : `started in 35.985s`. La console (capture) liste `auditor-test`, `norole-test`, `reader-test`, `supervisor-test` et `writer-test`. Les rôles ne sont pas vus ici : voir M6. |
| M6 | Jetons décodés (`Show-Token`) : `reader-test` a le rôle `reader`, `writer-test` `writer`, `supervisor-test` `supervisor`, `auditor-test` `auditor`, `norole-test` aucun ; `aud` et `iss` corrects ; sans jeton : 401. | Observé le 2026-11-20 (heure non relevée). Jetons décodés avec `Show-Token`, qui n'affiche aucun jeton : chaque compte a le rôle prévu (`reader-test`, `writer-test`, `supervisor-test`, `auditor-test`) ; durée de vie 300 s ; sans jeton, l'API répond 401. **Écart avec la prévision :** pour `norole-test`, « aucun rôle » était imprécis, car tous les comptes portent aussi les rôles par défaut de Keycloak ; il n'a aucun des quatre rôles de l'API. Ce n'est pas un écart du système. |
| M7 | `902` rejoué dans SSMS sur `TraceabilityTest` avec le préfixe `ESSAI-12C` : le dernier tableau montre `ESSAI-12C-L1` `SHIPPED` 460 (Roma) et `ESSAI-12C-L2` `SORTED` 470 (Cherry), ferme `ESSAI-12C-F1`, récolte le 2026-11-10. | Observé le 2026-11-20, fin du script à 09:05:47 UTC. `902` rejoué avec le préfixe `ESSAI-12C` (changé dans SSMS, non enregistré). Les données vues ensuite en M8 et M16 sont celles attendues. |
| M8 | API, vrais jetons, `writer-test`, sur `ESSAI-12C-L2` (trié, dernier tri à 09:15) : un emballage de 465 kg à `2026-11-10T09:15:00Z` (même heure que le tri) donne HTTP 422, errorCode 50311 ; à `2026-11-10T08:00:00Z` (avant le tri) : 422, 50311 ; à +10 minutes : 422, 50310. Après les trois refus, le lot est toujours `SORTED` avec 2 mouvements. | Observé le 2026-11-20, entre 09:05:47 et 09:28 UTC. Sur `ESSAI-12C-L2` : emballage à 09:15 → HTTP 422, 50311 ; à 08:00 → 422, 50311 ; à +10 minutes → 422, 50310. Le lot est resté `SORTED` avec 2 mouvements. |
| M9 | `writer-test` : un emballage de 465 kg de `ESSAI-12C-L2` à `2026-11-10T12:00:00Z` répond 201 ; le lot devient `PACKED` avec 3 mouvements. À faire après M14. | Observé le 2026-11-20, avant 09:28 UTC. HTTP 201. `ESSAI-12C-L2` : `PACKED`, 465 kg, 3 mouvements (06:30, 09:15 et 12:00 le 2026-11-10). |
| M10 | `supervisor-test`, remplacements sur `ESSAI-12C-L1` (expédié), avec la quantité et la station du mouvement : le tri à `13:40` (même heure que l'emballage) donne 422, 50311 ; le tri à `06:30` (même heure que la réception) : 422, 50311 ; la réception à `09:15` (même heure que le tri) : 422, 50311 ; l'expédition à +10 minutes : 422, 50310. Aucune ligne n'est ajoutée à l'historique des corrections. | Observé le 2026-11-20, vers 09:28 UTC. Quatre HTTP 422 : tri à 13:40 → 50311 (« not before the time of the next step ») ; tri à 06:30 → 50311 (« not after the time of the previous step ») ; réception à 09:15 → 50311 ; expédition à +10 minutes (heure envoyée 09:38:25, horloge du serveur 09:28:26) → 50310. `ESSAI-12C-L1` est resté identique : 4 mouvements, 0 correction. |
| M11 | `supervisor-test` remplace le tri de `ESSAI-12C-L1` à `2026-11-10T08:00:00Z` (entre 06:30 et 13:40), même quantité : 201. La lecture montre `occurredAt` à 08:00, `originalOccurredAt` à 09:15, `correctionCount` à 1, et une ligne dans les corrections. | Observé le 2026-11-20, à 09:28:26 UTC. HTTP 201. Tri à 08:00, heure d'origine 09:15, `correctionCount` 1, 1 correction. |
| M12 | `supervisor-test` change seulement la quantité de l'emballage de `ESSAI-12C-L1` (465 en 464) en renvoyant son heure actuelle `13:40` : 201. L'heure ne change pas et n'est pas contrôlée. | Observé le 2026-11-20, à 09:28:26 UTC. HTTP 201. Emballage à 464 kg, toujours à 13:40, 2 corrections au total. **Limite de la preuve :** 13:40 aurait passé le contrôle de toute façon (entre 08:00 et 17:05). M12 montre qu'une correction de la quantité seule passe, pas que l'heure inchangée est exemptée : c'est la casse 3 de M17 qui le prouve (tests 141 et 150). |
| M13 | Interface, `writer-test`, « Nouveau lot » : une réception à +10 minutes (heure tapée en UTC) affiche le texte français de 50310, avec le conseil de vérifier l'heure saisie et l'horloge de l'ordinateur ; les valeurs tapées restent ; le lot n'est pas créé. | Observé le 2026-11-20, avant 09:29 UTC. Réception tapée `20/11/2026 09:35` (UTC), soit plus de 6 minutes d'avance. Le texte rouge de 50310 s'affiche, avec le conseil de vérifier l'heure saisie et l'horloge de l'ordinateur ; les valeurs tapées sont conservées ; la page reste sur « Nouveau lot » ; le lot n'existe pas (voir M16). |
| M14 | Interface, `writer-test`, page de `ESSAI-12C-L2` (avant M9) : un emballage à `2026-11-10 09:15` (même heure que le tri) affiche le texte français de 50311 ; les valeurs tapées restent ; le lot reste « Trié » avec 2 mouvements. | Observé le 2026-11-20 (heure non relevée), en deux essais. **Premier essai :** `11/10/2026` tapé dans un champ jj/mm/aaaa, donc le 11 octobre, avant la réception : le texte de 50311 s'affiche, mais ce n'était pas le cas prévu (même heure que le tri). Écart de saisie, pas du système. **Deuxième essai :** `10/11/2026 09:15` (même heure que le tri) → texte français de 50311 ; valeurs conservées ; lot toujours « Trié » avec 2 mouvements. |
| M15 | Interface, `supervisor-test`, page de `ESSAI-12C-L1` : « Corriger un mouvement » sur l'emballage avec l'heure `2026-11-10 17:05` (même heure que l'expédition) affiche le texte français de 50311 ; les valeurs tapées restent ; la page ne relit pas le lot ; aucune correction n'est ajoutée. | Observé le 2026-11-20, de 09:33 à 09:36 UTC. Correction de l'emballage avec `10/11/2026 17:05:00` (même heure que l'expédition) : texte de 50311 ; tous les champs conservés ; « Parcours » et « Corrections » (2 lignes) inchangés. Avec l'onglet Réseau ouvert et un nouveau clic (même refus) : une requête `POST …/replace` en 422, précédée de sa vérification automatique `OPTIONS` (204, « preflight »), et aucune requête `GET` ensuite : la page n'a pas relu le lot. Les en-têtes des requêtes n'ont pas été ouverts (jeton). |
| M16 | SQL, contrôle final sur `TraceabilityTest`, pour les lots `ESSAI-12C-%` (lecture seule) : `trace.Movement` a 7 lignes (L1 : 4, L2 : 3), avec leurs heures d'origine (L1 : 06:30, 09:15, 13:40, 17:05 ; L2 : 06:30, 09:15, 12:00) ; `trace.MovementCorrection` a 2 lignes (M11 et M12), de `supervisor-test` avec son vrai identifiant (comparé à la console de Keycloak) ; aucun lot n'a été créé par M13. Les refus n'ont rien écrit. | Observé le 2026-11-20, fin à 09:38:16 UTC. `trace.Movement` : 7 lignes, avec leurs heures d'origine (L1 : 06:30, 09:15, 13:40, 17:05, emballage à 465 kg ; L2 : 06:30, 09:15, 12:00). `trace.MovementCorrection` : 2 lignes (n° 293 et 294), `REPLACE`, par `supervisor-test`, `CorrectedAt` 09:28:26. `AuthorId` identique à l'identifiant de `supervisor-test` dans la console de Keycloak (comparé caractère par caractère). `ESSAI-12C-L3` : 0. Les refus n'ont rien écrit. |
| M17 | Trois casses volontaires de `database/005_create_batch_procedures.sql`, avec l'empreinte SHA-256 avant et après (`Get-FileHash -Algorithm SHA256`), chacune suivie de `005` rejoué puis de `006` : (1) retirer le contrôle du futur de `AddMovement` ; (2) retirer le contrôle du voisin suivant dans `ReplaceMovement` ; (3) faire contrôler l'heure à chaque remplacement, même quand elle ne change pas (retirer la condition `@OccurredAt <> @CurrentTime`). Prévision : `006` rend des tests en échec à chaque casse, sur les tests qui visent la règle cassée : le test 125 au moins pour (1), des tests de la plage 130 à 137 pour (2), les tests 141 et 150 pour (3) ; les numéros exacts seront relevés. Une fois `005` remis à l'identique (empreinte) et rejoué, `006` redonne 150 tests, 142 automatiques et 8 à l'œil. | Observé le 2026-11-20, de 09:49 à 10:01 UTC, sur `TraceabilityTest` (`:setvar DbName` changé dans SSMS, non enregistré). Chaque casse change une ligne ; les prévisions ont été écrites avant. Original : `1414e550b10b6d4a0a8698f56f9c40bef75e667276161cf4a26fff2d6e40d56b`. **Casse 1** (`AddMovement` : contrôle du futur retiré, `IF 1 = 0`), `a84dfa46b803ba76b81ad13ed1ed85f01ff15f0a8e1f5bea1398d2196b6f094a` : 4 « ATTENTION », tests 125 et 148 (prévus) ; 126 et 127 en cascade, car le test 125 a accepté un tri sur `ZZ-T1` (erreur 50301) ; le test 128 reste vert. **Casse 2** (`ReplaceMovement` : étape suivante non contrôlée, `IF 1 = 0`), `607352d4ee59847803fb8040fd878c78089d642327b9f8fbb201fb684b08f45d` : 5 « ATTENTION », tests 133 à 136 (prévus) ; 138 en cascade, car le test 136 a déplacé la réception de `ZZ-T3` à 10:00 ; le test 137 reste vert, comme prévu. La plage « 130 à 137 » de la prévision était trop large. **Casse 3** (heure inchangée contrôlée, `IF 1 = 1`), `a911b38ff9a07e1629cbd128914fb046fed73e7920013aa516fb77baafadff3e` : 2 « ATTENTION », tests 141 et 150 (prévus), sans cascade. **Restauration :** empreinte `1414E550…D56B` relevée sous Windows et `git status` sans `005` ; `005` et `006` rejoués : 150 tests, 142 automatiques, 8 à l'œil, aucun « ATTENTION » (fin à 10:01:10 UTC). |
| M18 | Aucun jeton brut ni mot de passe dans les fichiers du lot : recherche de `eyJ`, de `password` et de `secret` dans les fichiers modifiés ou nouveaux, et dans `identity/traceability-realm.json`. Aucun jeton n'a été collé dans la conversation. | Observé le 2026-11-20, vers 10:05 UTC. `eyJ` n'apparaît que dans `docs/verification.md` (texte des instructions de recherche) et dans `web/package-lock.json` (ligne 1130, au milieu d'une empreinte en base64 ; fichier non modifié par le lot). Sur les 1367 lignes ajoutées par rapport à `main`, une seule contient `eyJ`, `password` ou `secret` : la ligne M18 de ce document. `identity/` : aucune correspondance. Aucun jeton n'a été collé dans la conversation. La prévision « aucun fichier » était imprécise, car ce document cite lui-même ces mots. |
| M19 | CI : une fois la branche poussée, `backend`, `frontend` et `docker` sont verts sur la branche, sur la pull request puis sur `main`. La CI recrée la base, rejoue `005` et `006` : `006` doit y rendre 150 tests. | Observé le 2026-11-20, après la fusion, dans l'onglet Actions de GitHub. Trois exécutions du workflow CI, toutes vertes : n° 88, push de la branche (commit `85b74ca`), 2 min 3 s ; n° 89, pull request n° 31, 1 min 35 s ; n° 90, push sur `main` après la fusion (commit `47c008b`), 1 min 54 s. Une autre exécution de la branche, la n° 87 (commit `0bc5943`, 1 min 15 s), est verte aussi : elle porte sur un commit plus ancien, elle n'est pas retenue. Sur la page de la pull request, les six contrôles sont verts : `backend` 1 min (pull_request) et 1 min (push), `docker` 25 s et 30 s, `frontend` 41 s et 30 s. Pour la n° 90, seule la durée du workflow entier est vue. Dans le journal de `backend` de la n° 90, `006` donne `tests_total` 150, `tests_ok` 142 et `tests_by_eye` 8, sans ligne « ATTENTION » : `006` a donc tourné sur la base neuve de la CI, et rend les 150 tests attendus. Les 8 tests à l'œil du journal ont été relus : leurs valeurs sont celles annoncées. Les nombres de tests de `dotnet test` et de Vitest dans la CI n'ont pas été relevés. |

### 24.3 Ce qui n'est pas essayé

Écrit avant l'essai.

- **La limite exacte de 5 minutes.** En SQL (`006`), une heure à +4 minutes est acceptée et une heure à +6 minutes refusée ; par l'API, +2 minutes sont acceptées et +10 minutes refusées. On sait donc que la limite est entre 4 et 6 minutes, pas qu'elle est à 5. Un test à 5 minutes pile dépendrait de quelques centaines de millisecondes entre deux horloges. Le choix de 5 minutes est une décision de conception.
- **Deux appels simultanés** sur le même lot pour les contrôles de l'heure : non essayés (ce que verrouille `UPDLOCK` sur le lot est décrit dans l'ADR 0003, mais on n'a pas observé deux appels simultanés avec ces contrôles).
- **Un vrai décalage d'horloge.** L'interface préremplit l'heure avec celle du navigateur. Un ordinateur dont l'horloge est en avance de plus de 5 minutes sur celle de SQL Server n'est pas essayé ; ici, SQL Server et le navigateur sont sur la même machine.
- **L'heure locale tapée comme si elle était en UTC** n'est pas essayée dans l'interface ; le champ est étiqueté UTC.
- **Un seul navigateur et un seul onglet**, sans jeton qui expire pendant la saisie.
- **Les anciennes données** qui seraient hors ordre ne sont ni corrigées ni signalées par l'API ; `021` les compte (24.4).
- **La CI** : voir M19. Elle n'utilise ni Keycloak ni vrai jeton, et ne rejoue pas `020`.

### 24.4 Ce qui est prouvé

Écrit le 2026-11-20, après l'essai ; la CI (M19) a été complétée le même jour, après la fusion.

- **Les règles de l'heure, dans la base** : `006` rend 150 tests, 142 automatiques et 8 à l'œil, sans « ATTENTION », sur `TraceabilityTest` (M1), et de nouveau après les casses volontaires, `005` remis à l'identique (M17). Puis une dernière fois à 18:43 le 2026-11-20, avec `ListBatches` en version `017` comme dans la CI : 150 / 142 / 8, et les 8 tests à l'œil relus. À +4 minutes l'heure est acceptée, à +6 minutes elle est refusée ; la limite exacte de 5 minutes n'est pas prouvée (24.3).
- **Les tests détectent les trois casses essayées**, les fichiers étant remis à l'identique (empreintes SHA-256) : 4, 5 et 2 « ATTENTION » selon la casse. Les tests en plus de ceux visés (126 et 127 ; 138) sont des cascades expliquées par le test précédent, pas d'autres règles cassées. La casse 3 prouve que l'heure inchangée n'est pas contrôlée, ce que M12 ne distinguait pas (M17).
- **Avec de vrais jetons, par l'API** : une heure égale ou hors ordre est refusée (422, 50311), à l'ajout comme au remplacement ; une heure à +10 minutes est refusée (422, 50310) ; les refus n'écrivent rien. Un tri remplacé entre ses deux voisins (201) et une quantité corrigée avec l'heure actuelle (201) sont acceptés (M8 à M12). Les jetons et les rôles sont ceux prévus, sauf une imprécision de la prévision pour `norole-test` (M6).
- **Le journal** : après tout l'essai, `trace.Movement` a 7 lignes avec leurs heures d'origine, `trace.MovementCorrection` 2 lignes écrites par le vrai compte `supervisor-test` (identifiant comparé à la console de Keycloak), et le lot refusé en M13 n'existe pas (M16).
- **L'interface** : le texte français de 50310 s'affiche à la création d'un lot (M13) et celui de 50311 à l'ajout d'un mouvement (M14) et à la correction (M15), valeurs conservées et rien écrit ; après le refus d'une correction, la page ne relit pas le lot (M15). Le texte de 50310 dans les formulaires d'ajout et de correction n'a pas été vu dans le navigateur : il l'est par les tests automatiques de l'interface.
- **Les tests automatiques** : 375 tests en C# (M2) et 339 pour l'interface, `npm run lint` et `npm run build` propres (M3), observés le 2026-11-17 ; depuis, les fichiers de code du lot n'ont pas changé (aucun nouveau commit, empreinte de `005` identique).
- **Les anciennes données** : `021` les compte sans les modifier. Sur `TraceabilityTest` (M4), il a trouvé des mouvements hors ordre ; sur `TraceabilityDev`, le 2026-11-20 (fin à 18:54:12), il a pris 3 min 12 s : 3 250 000 mouvements valables dans 1 000 000 de lots, aucun hors ordre, résultat 2 vide. `005` (18:47) et `017` (18:48) avaient été rejoués avant ; un contrôle en lecture seule montre les règles du lot 12c dans `AddMovement`, `ReplaceMovement` et `CreateBatch` sur Dev, et `ListBatches` en version `017` sur Dev et sur Test.
- **Aucun jeton ni mot de passe** dans les fichiers du lot, tels qu'ils étaient le 2026-11-20 (M18).
- **Écarts relevés** (aucun n'est un écart du système) : M6 (« aucun rôle » pour `norole-test`), M14 (premier essai à la mauvaise date, format jj/mm/aaaa), M17 (plage de tests trop large pour la casse 2 ; `005` rejoué sans `017` ensuite : `ListBatches` de `TraceabilityTest` est restée en version 005, relevé le 2026-11-20 à 18:37 ; `017` rejoué à 18:41, `006` rejoué à 18:43 : 150 / 142 / 8), M18 (mots cités par ce document lui-même).
- **La CI** : verte sur la branche, sur la pull request et sur `main` (M19). `006` a tourné sur la base neuve de la CI et rend 150 tests, dont 142 automatiques et 8 à l'œil. Elle n'utilise ni Keycloak ni vrai jeton : elle ne prouve pas ces points. Ses nombres de tests C# et d'interface ne sont pas relevés.
- **Non prouvé** : tout ce qui figure en 24.3.

### 24.5 Rejouer la vérification

Dans PowerShell et SSMS. Les mots de passe sont tapés dans une saisie masquée, jamais dans un message ni un fichier ; un jeton n'est jamais collé.

**1. Base de données** : sur une base existante, `019` puis `020` si elles manquent. Rejouer `005` : **le fichier pointe par défaut sur `TraceabilityDev`**, donc mode SQLCMD activé, changer dans SSMS la ligne `:setvar DbName` en `TraceabilityTest`, sans enregistrer. **Puis rejouer `017` (même changement de `:setvar`, API arrêtée)** : `005` remet la version non optimisée de `ListBatches`, et `017` remet la version optimisée. Puis `006` (elle vise `TraceabilityTest` par son `USE`) : 150 tests, 142 automatiques, 8 à l'œil, aucune ligne « ATTENTION ». `021` (lecture seule, même changement de base) compte les anciens mouvements hors ordre.

**2. Tests automatiques**, API arrêtée : `dotnet test Traceability.slnx` depuis la racine (375 tests attendus : 118 + 257 ; `ConnectionStrings__Test` définie), puis `npm run lint`, `npm run build` et `npm test` depuis `web/` (339 tests attendus). `dotnet test` vide `TraceabilityTest` au début : les données de l'essai sont à recréer ensuite.

**3. Keycloak, API et interface** : comme en 23.5 (étape 3), avec les mêmes cinq comptes. L'API est lancée sur `TraceabilityTest` (`ConnectionStrings__Default = $env:ConnectionStrings__Test`), l'interface avec `npm run dev`. `Get-Trial` et `Show-Token` sont ceux de 23.5 ; `Send-Json`, `Show-Batch` et `Replace-Movement` sont de petites fonctions écrites dans la fenêtre PowerShell pour l'essai : elles ne sont pas dans le dépôt. Un jeton vit 300 secondes : en redemander un avant chaque série d'appels.

**4. Données** : `database/902_trial_data_lot12b.sql` dans SSMS, avec le préfixe `ESSAI-12C` (l'en-tête du script dit comment le changer ; on ne l'enregistre pas). Il crée `ESSAI-12C-L1` et `ESSAI-12C-L2` décrits en 24.2.

**5. L'essai** (M6 à M15) : dans l'ordre conseillé en 24.2, avec M14 avant M9. Les dates de l'interface sont en jj/mm/aaaa ; les heures « +10 minutes » se calculent sur l'horloge de l'ordinateur au moment de l'appel.

**6. Contrôle SQL final** (M16) : lecture seule, `trace.Movement` et `trace.MovementCorrection` des lots `ESSAI-12C-%` (jointure avec `trace.Batch` et `trace.Station`), et le nombre de lots `ESSAI-12C-L3`. Attendu après la séquence de 24.2 : 7 mouvements, 2 corrections, aucun lot `ESSAI-12C-L3`.

**7. Casses volontaires** (M17) : une ligne de `005` par casse, avec l'empreinte SHA-256 avant et après (`Get-FileHash -Algorithm SHA256`), puis `005` et `006` rejoués (même changement de `:setvar`, non enregistré) ; `017` est à rejouer après le dernier `005`, pour remettre `ListBatches` en version optimisée. Les trois lignes : dans `AddMovement`, `IF @OccurredAt > DATEADD(MINUTE, 5, @Now)` devient `IF 1 = 0` ; dans `ReplaceMovement`, `IF @OccurredAt >= @NextTime` devient `IF 1 = 0`, puis (casse séparée) `IF @OccurredAt <> @CurrentTime` devient `IF 1 = 1`. Remettre le fichier à l'identique (empreinte `1414e550…d56b`, avec une date de modification neuve), rejouer `005`, `017`, puis `006` : 150 / 142 / 8.

**8. Secrets** (M18) : `git grep -l -I --untracked "eyJ"` ne doit montrer que ce document et `web/package-lock.json` (une empreinte en base64). Sur les lignes ajoutées par rapport à `main` (`git diff main -U0`), `eyJ`, `password` et `secret` ne doivent montrer que des mots de ce document. `git grep -c -i -E "password|secret" -- identity` n'affiche que des nombres, jamais les lignes.

## 25. Lot 13a : la base de recette et ses outils

Écrit le 2026-11-23, **après** l'essai : les lignes de 25.2 sont les résultats relevés pendant la séance du même jour. Les heures sont en UTC. Les scénarios des règles (R01 à R12 et NOMINAL) sont écrits au lot 13b, pas ici.

### 25.1 Ce qui est essayé

- **Une troisième base, `TraceabilityAcceptance`.** Elle est construite avec les scripts existants (`001`, `002`, `004`, `005`, `011`, `017`), le `:setvar DbName` mis sur son nom à l'écran, sans enregistrer. Elle sert aux essais manuels du cahier de recette ; `dotnet test` ne la touche pas (note de l'[ADR 0002](adr/0002-tests-sur-base-reelle.md)).
- **`900_reset_dev_database.sql`** accepte les trois noms (`TraceabilityDev`, `TraceabilityTest`, `TraceabilityAcceptance`) et refuse les autres.
- **Les outils de la recette**, dans [recette-outils.ps1](recette-outils.ps1), en quatre blocs : authentification (`Get-Trial`, `Show-Token`, `Show-Identity`), lecture (`Read-Api`, `Read-Lot`), écriture (`Send-Api`, `New-Farm`, `New-Station`, `Add-Capability`, `New-Lot`, `Add-Movement`) et corrections (`Replace-Movement`, `Cancel-Movement`, `Correct-Lot`). Aucun mot de passe ni jeton n'y est écrit.
- **Le cahier**, [recette.md](recette.md) : principes, comptes de test, préparation d'une séance, outils, `R00-PREPARATION` (données de référence) et `R99-OUTILS` (contrôle de l'outillage).
- **Les documents** : le nettoyage de chiffres périmés (glossaire, README, commentaire de l'en-tête de `006`), les règles de commit et de pull request dans `CLAUDE.md`, la base de recette dans le README, `CLAUDE.md` et l'ADR 0002.

### 25.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| N1 | Nettoyage des docs : différences relues côté Windows ; `006` rejoué sur `TraceabilityTest`. | Observé le 2026-11-23, avant 10:34. `006` : 150 tests, dont 142 automatiques et 8 à l'œil. |
| N2 | `900` à blanc (`@confirm` à `NO`) : un nom hors liste (`TraceabilityFoo`) est refusé ; `TraceabilityDev` et `TraceabilityAcceptance` sont acceptés mais rien n'est supprimé. | Observé le 2026-11-23, avant 10:34. Le nom hors liste donne « not allowed. Nothing done. » ; avec `NO`, « Nothing done. To drop TraceabilityAcceptance, set @confirm to YES and run again. ». |
| N3 | `001` avec `TraceabilityAcceptance`. | Observé le 2026-11-23. Base créée : `French_CI_AS`, `SIMPLE`, `ONLINE`, deux fichiers (données et journal). |
| N4 | `900` pour de bon sur `TraceabilityAcceptance` (`@confirm` à `YES`, non enregistré), puis la liste des bases. | Observé le 2026-11-23, fin à 10:55:50. « Database TraceabilityAcceptance dropped. Run 001, 002, 004, 005, 011 and 017 to rebuild. » ; ensuite, seules `TraceabilityDev` et `TraceabilityTest` restent. |
| N5 | Reconstruction de zéro de `TraceabilityAcceptance` : `001`, `002`, `003`, `004`, `005`, `011`, `017`. | Observé le 2026-11-23. `001` : trois bases listées, 0 table ; `002` (11:04:57) : « Schema trace and 7 tables created. » ; `003` (11:08:02) : 43 tests sur 43, et les 7 tables à 0 ligne avant et après (`unchanged`) ; `004` (11:11:26) : 3 procédures ; `005` (11:17:59) : 10 ; `011` (11:25:58) : 13 ; `017` (11:28:26) : « Index IX_Batch_FarmId created. », `ListBatches` modifiée à 11:28:25. |
| N6 | Contrôle final en lecture seule de la base reconstruite. | Observé le 2026-11-23, vers 11:29. 7 tables, 13 procédures du schéma `trace`, 1 index `IX_Batch_FarmId`. |
| N7 | Variable utilisateur `ConnectionStrings__Acceptance`, créée dans le compte Windows. | Observé le 2026-11-23, vers 11:46. Absente avant ; relue avec `Database=TraceabilityAcceptance` après. |
| N8 | Keycloak relancé (`docker start traceability-keycloak`, conteneur arrêté depuis 3 heures, « Exited (255) ») ; les cinq comptes dans la console. | Observé le 2026-11-23. Premier contrôle juste après : code `000` ; au contrôle suivant, `Up 2 minutes`, port `127.0.0.1:8180->8080/tcp`, realm `200`. La console du realm `traceability` liste `auditor-test`, `norole-test`, `reader-test`, `supervisor-test` et `writer-test`. |
| N9 | API lancée avec `ConnectionStrings__Default` copiée de `ConnectionStrings__Acceptance`. | Observé le 2026-11-23, vers 18:50. La variable relue contient `Database=TraceabilityAcceptance` ; « Now listening on: https://localhost:7080 », « Application started », « Hosting environment: Development », sans erreur. Une première tentative avec la variable vide (fenêtre ouverte avant sa création) a été vue et écartée avant tout lancement. |
| N10 | Outils, bloc authentification : chargement du fichier, `Get-Trial reader-test`, `Show-Token`, `Show-Identity`. | Observé le 2026-11-23, vers 12:13. Aucun message au chargement ; `HTTP 200 Bearer expires_in 299` ; `iss` du realm, `aud` `traceability-api,account`, `azp` `traceability-trial`, durée 300 s, rôle `reader` ; identité `reader-test`. |
| N11 | Outils, bloc lecture : `Read-Api '/farms'`, `Read-Lot 'NOPE-1'`, puis la même lecture sans jeton. | Observé le 2026-11-23, vers 18:52. `HTTP 200` avec une page vide ; `HTTP 404`, `errorCode` 50100 ; `HTTP 401` avec le texte d'aide. |
| N12 | Outils, bloc écriture, `writer-test` : ferme `FERME-NORD`, station `STA-RECEPTION` avec la fonction `RECEPTION`, lot `R99-OUTILS-261123` (100.5 kg), `Read-Lot` ; puis le lot est cherché dans les trois bases (SSMS, lecture seule). | Observé le 2026-11-23, vers 19:10 et 19:12. `HTTP 201` ×4, puis `HTTP 200` : `RECEIVED`, 100.50 kg, `authorName` à `null` pour `writer`. Le lot est dans `TraceabilityAcceptance` (1), pas dans `TraceabilityDev` (0) ni `TraceabilityTest` (0). |
| N13 | Outils, bloc corrections, `supervisor-test`, sur ce lot : `Replace-Movement` (95.5, `MEASUREMENT_ERROR`), `Correct-Lot` (variété `Cherry`), `Cancel-Movement` de la réception, puis `Read-Lot`. | Observé le 2026-11-23, à 20:55. `HTTP 201`, `HTTP 201`, puis `HTTP 422`, `errorCode` 50307 (« The RECEPTION of a batch cannot be cancelled. »). La fiche : `Cherry`, 95.50 kg (original 100.50), une correction du mouvement et une de la fiche, `authorName` visible (`writer-test`) pour `supervisor`. |
| N14 | Fichiers côté Windows : `recette-outils.ps1` (44, 68, 118 puis 143 lignes à chaque bloc) et `recette.md` (85 lignes), sans caractère non ASCII dans le premier. | Observé le 2026-11-23, à chaque commit. |
| N15 | Aucun jeton ni mot de passe dans les fichiers du lot : recherche de `eyJ`, de `password` et de `secret` dans les fichiers modifiés ou nouveaux. | Observé le 2026-11-23, avant le commit des documents. `eyJ` : seulement ce document (le texte qui nomme cette recherche) et `web/package-lock.json` (une empreinte, comme en 24.5). `password` et `secret`, dans les lignes ajoutées par rapport à `main` : des mots dans des commentaires et des noms de paramètres (`recette-outils.ps1`), un renvoi à la section « Secrets » (`CLAUDE.md`), une phrase du README déjà présente et cette ligne ; aucune valeur réelle. |
| N16 | CI : une fois la branche poussée, `backend`, `frontend` et `docker` sont verts sur la branche, sur la pull request puis sur `main`. | Observé le 2026-11-23, après la fusion, dans l'onglet Actions de GitHub. Trois exécutions du workflow CI, toutes vertes : n° 94, push de la branche (commit `25c1772`), 1 min 45 s ; n° 95, pull request n° 33, 1 min 42 s ; n° 96, push sur `main` après la fusion (commit `5eeef54`), 1 min 51 s. Sur la page de la pull request, les six contrôles sont verts et il n'y a pas de conflit ; leurs durées une à une ne sont pas relevées. Dans le journal de `backend` de la n° 96, `006` donne `tests_total` 150, `tests_ok` 142 et `tests_by_eye` 8, sans ligne « ATTENTION » : `006` a donc tourné sur la base neuve de la CI et rend les 150 tests attendus. Les 8 tests à l'œil du journal ont été relus : leurs valeurs sont celles annoncées. Les nombres de tests de `dotnet test` et de Vitest dans la CI n'ont pas été relevés. |

### 25.3 Ce qui n'est pas essayé

Écrit après l'essai.

- **`dotnet test` avec la base de recette présente.** Le code des tests lit `ConnectionStrings__Test` et refuse de nettoyer toute base autre que `TraceabilityTest` (erreur 50099) : c'est ce que dit le code, pas un essai lancé avec `TraceabilityAcceptance` présente.
- **Les accents dans les noms** (ferme, station, variété) : l'essai n'en contient pas, et la console peut afficher les accents de travers sans que ce soit l'API.
- **Le succès de `Cancel-Movement`** : seul son refus (50307) est vu ; il faut un deuxième mouvement.
- **Les comptes `auditor-test` et `norole-test`** : ils existent, mais aucun jeton n'en a été demandé. Les rôles de ces deux comptes ne sont pas relevés dans un jeton.
- **Un mauvais mot de passe** : `Get-Trial` doit afficher seulement `HTTP …`, non essayé.
- **Le canal Interface** : tout est passé par l'API.
- **L'origine des numéros d'identité** (`movementId` 9, `correctionId` 11 et 13) : l'explication probable est que les tests de `003` ne rendent pas leurs numéros après l'annulation (`ROLLBACK`), mais ce n'est pas vérifié.
- **La version de PowerShell** utilisée n'est pas relevée ; le fichier est écrit pour fonctionner avec Windows PowerShell 5.1 comme avec les versions récentes, et il a fonctionné chez toi.
- **Les scénarios des règles** : au lot 13b.
- **Les durées des six contrôles de la pull request, et les nombres de tests de `dotnet test` et de Vitest dans la CI** : non relevés (voir N16).

### 25.4 Ce qui est prouvé

Écrit le 2026-11-23, après l'essai.

- **Le script `900` protège et supprime pour de bon** : il refuse un nom hors liste, accepte les trois noms, et supprime `TraceabilityAcceptance` quand `@confirm` est à `YES` (N2, N4).
- **La base de recette se reconstruit de zéro** avec les scripts du dépôt et a les mêmes objets que les autres : 7 tables, 13 procédures, l'index, les 43 tests de contraintes de `003` réussis et annulés sans laisser de ligne (N5, N6).
- **L'API lancée sur `TraceabilityAcceptance` y écrit, et seulement là** : le lot d'essai est dans cette base et dans aucune autre (N12).
- **Les rôles se comportent comme `Program.cs` les définit**, pour les trois comptes essayés : `reader` lit, `writer` écrit sans voir les noms des auteurs, `supervisor` corrige et voit les noms (N10 à N13).
- **Les quatre blocs d'outils fonctionnent** : authentification, lecture, écriture, corrections (refus 50307 compris), sans jamais afficher le jeton (N10 à N13).
- **La CI** : verte sur la branche, sur la pull request et sur `main` (N16). `006` a tourné sur la base neuve de la CI et rend 150 tests, dont 142 automatiques et 8 à l'œil. La CI n'exécute ni `900`, ni les outils PowerShell, ni Keycloak, ni l'API sur la base de recette : elle ne prouve pas ces points, qui reposent sur N2 à N13.
- **Non prouvé** : tout ce qui figure en 25.3.

### 25.5 Rejouer la vérification

La préparation d'une séance (base, Keycloak, API, fenêtre d'essais) est décrite dans [recette.md](recette.md), section 3 ; les scénarios `R00` et `R99` sont à rejouer dans l'ordre, avec les comptes indiqués. Mêmes règles que partout : les mots de passe se tapent dans la saisie masquée de `Get-Trial`, jamais dans un message ni un fichier, et un jeton n'est jamais collé.

## 26. Lot 13b : les scénarios de la recette

Écrit le 2026-11-25, **après** l'essai : les lignes de 26.2 sont les résultats relevés pendant les séances du 2026-11-23 (lot 13a), du 2026-11-24 et du 2026-11-25. Les heures sont en UTC. Les 138 scénarios de [recette.md](recette.md) (R00, R99, R01 à R12 et NOMINAL) sont joués : aucun n'est en échec et aucun n'est resté « Non essayé ».

### 26.1 Ce qui est essayé

- **Le cahier, joué à la main** sur `TraceabilityAcceptance`, avec l'API lancée sur cette base, de vrais jetons de Keycloak et les cinq comptes de test. Un scénario est une action (un appel, un refus ou une lecture) avec son propre statut, noté d'après ce qui s'est affiché.
- **Trois canaux** : l'API par les outils PowerShell, la base lue dans SSMS en lecture seule (R03-04), et l'interface web (R09-15 et R09-16, R10, NOMINAL), dans Edge en navigation privée, une fenêtre par compte.
- **Un lot par groupe**, nommé `Rxx-GROUPE-aammjj`, avec des heures de la veille et une récolte de l'avant-veille : tout reste dans le passé et dans l'ordre, quelle que soit l'heure de la séance.
- **Deux écarts avec le cahier écrit.** Le groupe NOMINAL a été joué sur le lot `NOM-PARCOURS2-261125` : le code `NOM-PARCOURS-261125` avait servi à un premier essai, créé par erreur de saisie avec l'heure du formulaire (25/11/2026 10:01) au lieu de 24/11/2026 06:00 ; ce lot est resté `RECEIVED` dans la base de recette (écart noté dans [recette.md](recette.md)). Pour R11-16, la ligne du cahier a été corrigée avant l'essai : l'argument de date a reçu des parenthèses.

### 26.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| N1 | R00 et R99 (12 scénarios) : données de référence et outillage. | Observé le 2026-11-23 (R00-01, R00-02, R99) et le 2026-11-24 (R00-03 à R00-08). Fermes et stations créées (201) ; `STA-VIDE` lue sans fonction (200). |
| N2 | R01-ORDRE (8) : l'ordre des statuts. | Observé le 2026-11-24. Les quatre étapes dans l'ordre donnent 201 (`RECEIVED`, `SORTED`, `PACKED`, `SHIPPED`) ; une étape sautée ou mauvaise donne 422, 50301, quatre fois, et le lot ne bouge pas. |
| N3 | R02-QUANTITE (9) : la quantité. | Observé le 2026-11-24. Une quantité à 0 ou négative donne 400, 50401 (trois fois ; à la création, `Read-Lot` donne 404 : rien n'est créé) ; une quantité qui monte donne 422, 50302 (deux fois) ; les autres lignes donnent 201. |
| N4 | R03-JOURNAL (5) : le journal ne se modifie jamais. | Observé le 2026-11-24. Le tri corrigé à 95 kg montre 95.00 (valable) et 90.00 (original). Dans SSMS : `Movement` garde 2 lignes dont le tri à 90.00, `MovementCorrection` 1 ligne. La correction de la fiche (`Roma` vers `Cherry`) garde les deux valeurs. |
| N5 | R04-FIN (6) : la fin de parcours. | Observé le 2026-11-24. Après l'expédition, un cinquième mouvement donne 422, 50300 ; le lot reste `SHIPPED` avec 4 mouvements ; `reader-test` le lit (200, 90.00 kg). |
| N6 | R05-UNICITE (6) : l'unicité des codes. | Observé le 2026-11-24. Une ferme, une station ou un lot qui existe déjà donne 409 (50200, 50201, 50202) ; le lot corrigé vers `-B` (201) garde son ancien code réservé : un nouveau lot qui le prend donne 409, 50203. |
| N7 | R06-FONCTION (6) : la fonction de la station. | Observé le 2026-11-24. Une station sans fonction, ou avec une autre fonction, donne 422, 50303 (à la création et à l'ajout) ; `STA-MIXTE` accepte la réception et le tri (201) ; déclarer deux fois la même fonction donne 409, 50203. |
| N8 | R07-AUTEUR (5) : l'auteur d'un mouvement. | Observé le 2026-11-24. `auditor-test` voit `writer-test` et aucun identifiant d'auteur dans la réponse ; l'identifiant enregistré en base est le `sub` de `writer-test` ; un champ `authorName` ajouté au corps de la demande est ignoré (201, auteur `writer-test`). Rôles du jeton de `auditor-test` : `default-roles-traceability`, `offline_access`, `auditor`, `uma_authorization`. |
| N9 | R08-CORRECTION (19) : les corrections des mouvements. | Observé le 2026-11-24. Refus : 50304 (deux fois), 50303, 50308, 50408, 50307, 50306, 50305. Annuler le dernier mouvement ramène le lot à `SORTED` (92.00 kg) et le mouvement annulé reste visible (`isCancelled`). Annuler l'expédition fait passer le lot de `SHIPPED` à `PACKED` (90.00 kg), le seul cas où un lot expédié bouge. `auditor-test` voit `writer-test` sur les mouvements et `supervisor-test` sur les corrections ; les valeurs d'origine sont intactes. |
| N10 | R09-ROLES (16) : les rôles. | Observé le 2026-11-24. `reader` lit (200, `authorName` à `null`) et ne peut pas écrire (403, « this account is not allowed to do this. ») ; `writer` lit et ne peut pas corriger (403) ; `supervisor` voit les noms et ne peut pas ajouter (403) ; `auditor` voit les mêmes noms, sans ajout ni correction (403) ; `norole-test` (aucun rôle métier dans le jeton) : 403 ; sans jeton : 401. Dans l'interface : `reader` sans colonne « Auteur » ni « Corrigé par » ; `auditor` avec les deux ; ni l'un ni l'autre n'a de formulaire d'écriture (jugé sur capture). |
| N11 | R10-DESTINATAIRE (6) : le message au destinataire d'un lot expédié. | Observé le 2026-11-25, `supervisor-test`. Remplacement 90 à 88 kg : « Correction enregistrée. », encadré « Ce lot avait été expédié : prévenez le destinataire. » avec un message (lot, étape, 90,00 kg vers 88,00 kg, motif), « Copier le message » donne « Message copié. » (Edge, sur localhost) et le texte collé est identique. Correction de la fiche : message propre à la fiche (« Variété : Roma → Cherry »). Remplacement de la quantité par l'API : 201, aucun message dans la réponse. Annulation de l'expédition : encadré « l'étape « expédition » est annulée, elle n'a pas eu lieu », lot repassé à `PACKED`. Correction de la fiche sur ce lot `PACKED` : « Fiche corrigée. », aucun encadré. |
| N12 | R11-FICHE (17) : la correction de la fiche. | Observé le 2026-11-25. Variété, ferme et code corrigés (201, `RECEIVED` et 100.00 kg inchangés) ; lecture par l'ancien code : 200, lot rendu sous le nouveau code ; écriture ou correction avec l'ancien code : 404, 50104 ; code actuel d'un autre lot : 409, 50202 ; ancien code d'un autre lot : 409, 50203 ; reprise de son premier code : 201 ; valeurs identiques : 422, 50308 ; changement de casse seule : 201 ; `MEASUREMENT_ERROR` : 400, 50407 ; `OTHER` sans commentaire : 400, 50408 ; récolte après la réception : 422, 50309 ; récolte le jour de la réception : 201. Lecture finale : 6 corrections de la fiche, auteur `supervisor-test`. |
| N13 | R12-HEURE (14) : l'heure des mouvements. | Observé le 2026-11-25. À +10 minutes : 422, 50310, à la création (lot introuvable ensuite, 404), à l'ajout et au remplacement ; heure égale ou avant la précédente : 422, 50311 ; remplacement du tri à 08:30 (après l'emballage) : 422, 50311, à 07:30 : 201 ; le futur est refusé avant l'ordre (50310) ; une heure sans `Z` : 400 sans `errorCode` ; sur un lot expédié, un nouvel envoi dans le futur donne 422, 50300, pas 50310. |
| N14 | NOMINAL (9) : le parcours complet, dans l'interface avec `writer-test`. | Observé le 2026-11-25, sur `NOM-PARCOURS2-261125`. Ferme et station créées, quatre fonctions ajoutées ; lot de 500 kg, puis tri 470, emballage 465 et expédition 465 : « Reçu », « Trié », « Emballé », « Expédié » ; après l'expédition, le formulaire est remplacé par « Ce lot est expédié : aucun mouvement n'est plus possible. ». `reader-test` lit les 4 mouvements dans l'ordre (identifiants 48 à 51, 465.00 kg), comme dans l'interface. Le filtre « Expédié » et la ferme `NOM-FERME` ne montrent que ce lot. |
| N15 | Aucun jeton ni mot de passe dans les fichiers modifiés : recherche de `eyJ`, de `password` et de `secret`. | Observé le 2026-11-25, avant le commit des documents. Dans les lignes ajoutées par rapport à `origin/main` (README.md, docs/recette.md, docs/verification.md), une seule ligne contient l'un de ces mots : cette ligne N15, qui nomme la recherche. Aucun texte de la forme `eyJ` suivi de dix caractères ou plus dans ces trois fichiers. Aucune commande `DROP`, `TRUNCATE` ni `DELETE` dans les lignes ajoutées. |
| N16 | CI : `backend`, `frontend` et `docker` sur la branche, sur la pull request puis sur `main`. | Observé le 2026-11-25, dans l'onglet Actions de GitHub. Trois exécutions du workflow CI, toutes vertes : n° 100, push de la branche (commit `9231e24`), 1 min 50 s (`backend` 1 min 47 s, `frontend` 33 s, `docker` 24 s) ; n° 101, pull request n° 35, 1 min 35 s (1 min 32 s, 37 s, 24 s) ; n° 102, push sur `main` après la fusion (commit `ea6ee23`), 1 min 29 s (1 min 25 s, 42 s, 24 s). Sur la page de la pull request, les six contrôles sont verts. Dans le journal de `backend` de la n° 102, `006` donne `tests_total` 150, `tests_ok` 142 et `tests_by_eye` 8, sans ligne « ATTENTION » ; les 98 lignes « Refused as expected » et les 44 lignes « Accepted as expected » font bien 142. Les 8 tests à l'œil du journal ont été relus : leurs valeurs sont celles annoncées. À l'étape `Test`, `dotnet test` donne 118 tests réussis pour `Traceability.UnitTests` et 257 pour `Traceability.IntegrationTests`, aucun en échec ni ignoré. Dans le résumé de `frontend` de la n° 102, Vitest donne 33 fichiers et 339 tests réussis. Les journaux des n° 100 et 101 et l'étape `012` ne sont pas relus. La CI ne rejoue aucun scénario de la recette. |

### 26.3 Ce qui n'est pas essayé

Écrit après l'essai.

- **Les droits d'accès à la base** : une personne qui a les droits sur la base pourrait modifier le journal par un accès direct, et la colonne d'auteur ne le signalerait pas. Rien ne se modifie par l'API ni par les procédures (R03) ; les droits seront restreints plus tard.
- **La clé étrangère de la fonction d'une station** : R06 montre le refus par la procédure et l'API, pas un `INSERT` direct dans la table.
- **« Aucun lot n'est supprimé »** : cela repose sur l'absence de route de suppression dans l'API, lue dans le code, sans scénario (R04).
- **L'auteur** : les anciens mouvements d'avant le lot 11 (« Données initiales »), un jeton sans nom d'utilisateur, le nom « du moment de la saisie » (il faudrait renommer un compte) et deux comptes `writer` différents (un seul existe).
- **Les corrections** : le motif de plus de 500 caractères (50409), et une ferme inconnue dans la correction de la fiche (50101).
- **Les rôles** : les routes de lecture des fermes et des stations avec chaque rôle, un rôle donné par un autre moyen que Keycloak, et l'absence de formulaires dans l'interface pour `reader` et `auditor`, jugée sur capture d'écran.
- **Le message au destinataire** : que rien n'est enregistré ni envoyé. On ne constate qu'une absence de trace.
- **L'heure** : la limite exacte de 5 minutes (le cahier prend +10 minutes pour être sûr du refus ; le lot 12c a vu +4 accepté et +6 refusé), deux appels simultanés sur le même lot, et une horloge d'ordinateur en avance.
- **Restés ouverts depuis 25.3** : les accents dans les noms, un mauvais mot de passe dans `Get-Trial`, l'origine des numéros d'identité, la version de PowerShell. Réglés par ce lot : le succès de l'annulation d'un mouvement (R08), les rôles des jetons de `auditor-test` et de `norole-test` (R07, R09) et le canal Interface (R09, R10, NOMINAL).
- **La base de recette garde les lots des essais**, dont `NOM-PARCOURS-261125` (premier essai du groupe NOMINAL, resté `RECEIVED`) ; le cahier ne les supprime pas.
- **Le nom et la région de la ferme `NOM-FERME`** ne sont pas imposés par le cahier : ils ont été choisis pendant l'essai.
- **L'automatisation** : les scénarios se jouent à la main ; rien n'est rejoué par la CI.

### 26.4 Ce qui est prouvé

Écrit le 2026-11-25, après l'essai.

- **Les douze règles de [fonctionnel.md](fonctionnel.md) ont chacune un groupe de scénarios joué et conforme** (R01 à R12), avec de vrais jetons de Keycloak, et le parcours complet fonctionne de bout en bout dans l'interface (NOMINAL).
- **Les refus n'écrivent rien** là où on l'a relevé : après un refus à la création, `Read-Lot` donne 404 (R02-01, R06-01, R12-01).
- **Le journal garde les valeurs d'origine**, lues dans la base (R03-04) et par l'API (R08-19, R09).
- **Les noms des auteurs ne sont montrés qu'à `auditor` et `supervisor`**, par l'API et par l'interface (R07, R08-19, R09, NOM-08) ; `reader`, `writer`, un compte sans rôle (403) et l'absence de jeton (401) sont refusés ou masqués comme prévu (R09).
- **Le message au destinataire** apparaît pour un lot expédié, après un remplacement, une correction de la fiche et une annulation (R10-02, R10-03, R10-05), et n'apparaît pas pour une correction de la fiche faite sur un lot `PACKED` (R10-06).
- **La CI** : verte sur la branche, sur la pull request et sur `main` (N16). `006` rend 150 tests (142 automatiques, 8 à l'œil), `dotnet test` 375 tests (118 et 257), Vitest 339 tests. La CI ne rejoue aucun scénario de la recette : elle ne prouve pas les 138 scénarios.
- **Non prouvé** : tout ce qui figure en 26.3.

### 26.5 Rejouer la vérification

La préparation d'une séance (base, Keycloak, API, fenêtre d'essais, variables de dates) est décrite dans [recette.md](recette.md), section 3. Les groupes se jouent dans l'ordre, un groupe commencé se termine le même jour, avec les comptes indiqués ; seul le suffixe `$s` des lots change d'un jour à l'autre. Mêmes règles que partout : les mots de passe se tapent dans la saisie masquée de `Get-Trial`, jamais dans un message ni un fichier, et un jeton n'est jamais collé.

## 27. Lot 14 : la pile de démonstration Docker Compose

Écrit le 2026-11-26, **après** l'essai : les lignes de 27.2 sont les résultats relevés pendant les essais du 2026-11-26, bloc par bloc, sur les trois commits de la branche `feature/lot-14-compose` (`9eaf066`, `aa81405`, `0cc71fe`). Les heures sont en UTC. Une seule machine : le PC Windows de l'auteur, avec Docker Desktop et Chrome. Rien n'a été essayé ailleurs (voir 27.3).

### 27.1 Ce qui est essayé

- **La pile en six services**, lancée par `docker compose up -d` depuis la racine du dépôt : `sql` (SQL Server 2025), `db-init` (construit `TraceabilityDev` avec les scripts et y ajoute 20 lots de démonstration, `database/022_demo_data.sql`), `keycloak` (26.6.2, `start-dev --import-realm`), `keycloak-init` (crée les quatre comptes et leurs rôles), `api` et `web`.
- **Un essai par bloc** : la base (bloc 1), Keycloak et les comptes (bloc 2), l'API et l'interface (bloc 3), puis un parcours dans Chrome avec deux comptes.
- **Deux comptes dans le navigateur** : `reader-test` (lecture) et `writer-test` (une ferme créée), avec de vrais jetons de Keycloak. Les mots de passe se tapent dans `.env` et dans la fenêtre de connexion, jamais dans un message.
- **Un écart avec le plan** : l'API est publiée sur le port 8081 et non 8080 (P5).
- **Un faux départ** : la première demande de jeton a été lancée avant la fin du démarrage de Keycloak (réponse « HTTP 000 », journal de `keycloak-init` vide) ; il a suffi d'attendre, sans changer les scripts.

### 27.2 Liste de contrôle

| N° | À observer | Résultat |
|---|---|---|
| P1 | `db-init`, premier lancement : la base et les données de démonstration. | Observé le 2026-11-26. La base `TraceabilityDev` est construite, avec 20 lots : `RECEIVED` 5, `SORTED` 5, `PACKED` 6, `SHIPPED` 4 ; 50 mouvements, 3 lignes dans `MovementCorrection` et 2 dans `BatchCorrection`. |
| P2 | `db-init` rejoué : il n'écrase rien. | Observé le 2026-11-26. Au deuxième `up -d` : « TraceabilityDev existe deja et contient des donnees : rien a faire. ». Après `docker compose down`, le `up -d` suivant reconstruit la base (les comptes n'existaient plus après le `down`). |
| P3 | `keycloak-init` : les quatre comptes et leurs rôles. | Observé le 2026-11-26. Quatre lignes « Compte … pret ». Un jeton de `reader-test` : HTTP 200, `expires_in` 300, rôles `reader`, `default-roles-traceability`, `offline_access` et `uma_authorization`. Deuxième passage : quatre fois « existe deja », conteneur `Exited (0)`. |
| P4 | Les durées. | Observé le 2026-11-26. Construction des images : 348,6 s. Keycloak prêt après 83,7 s à un lancement, 164,5 s à un autre (machine occupée par la construction). |
| P5 | Le port 8080. | Observé le 2026-11-26. Docker refuse le port 8080 : il est pris par `httpd.exe` (service `PEMHTTPD-x64`, EDB Postgres, sans rapport avec le projet, laissé en place). Les ports 8081 et 8082 sont libres ; l'API est publiée sur 8081 (deux lignes de `compose.yaml`). |
| P6 | Chrome : connexion et lecture. | Observé le 2026-11-26. L'écran « Connexion » renvoie à la page de Keycloak, `reader-test` se connecte ; la liste montre les 20 lots sur 2 pages, avec les corrections visibles. |
| P7 | Chrome : écriture et lecture par un autre compte. | Observé le 2026-11-26. `writer-test` crée la ferme `FERME-TEST` (2 fermes avant, 3 après). Déconnecté puis reconnecté en `reader-test` : la liste montre 3 fermes, dont `FERME-TEST` ; `reader-test` n'a pas de bouton « Nouvelle ferme ». |
| P8 | Aucun jeton ni mot de passe dans les fichiers modifiés : recherche de `eyJ`, de `password` et de `secret`. | Observé le 2026-11-26, avant le commit des documents. Dans les lignes ajoutées par rapport à `origin/main` (12 fichiers), 21 lignes contiennent `password` ou `secret`, plus cette ligne P8 qui nomme la recherche : ce sont des noms de variables (`MSSQL_SA_PASSWORD`, `KC_BOOTSTRAP_ADMIN_PASSWORD`, `DEMO_USER_PASSWORD`, `SQLCMDPASSWORD`), des références `${...}`, des commentaires et des textes de documentation. `.env.example` contient les trois noms sans valeur, et `git ls-files` ne montre que lui : `.env` n'est pas suivi par git. Aucun texte de la forme `eyJ` suivi de dix caractères ou plus ; la seule ligne qui contient `eyJ` est cette ligne P8. Aucune commande `DROP`, `TRUNCATE` ni `DELETE` dans les lignes ajoutées : hors cette ligne P8, la seule ligne qui contient ces mots est le commentaire « Contains no DROP, TRUNCATE or DELETE. » de `database/022_demo_data.sql`. |
| P9 | CI : `backend`, `frontend` et `docker` sur la branche, sur la pull request puis sur `main`. | Observé le 2026-11-26, dans l'onglet Actions de GitHub, après la fusion. Trois exécutions du workflow CI, toutes vertes : n° 106, push de la branche (commit `3d03217`), 1 min 24 s (`backend` 1 min 20 s, `frontend` 35 s, `docker` 26 s) ; n° 107, pull request n° 37, 1 min 6 s (1 min 2 s, 45 s, 32 s) ; n° 108, push sur `main` après la fusion (commit `cd098a2`), 1 min 21 s (1 min 19 s, 34 s, 36 s). Sur la page de la pull request, les six contrôles sont verts. Dans le journal de `backend` de la n° 108, `006` donne `tests_total` 150, `tests_ok` 142 et `tests_by_eye` 8, sans ligne « ATTENTION » ; les 98 lignes « Refused as expected » et les 44 lignes « Accepted as expected » font bien 142. Les 8 tests à l'œil du journal (30, 32, 33, 38, 41, 86, 87 et 121) ont été relus : leurs valeurs sont celles annoncées. À l'étape `Test`, `dotnet test` donne 118 tests réussis pour `Traceability.UnitTests` et 257 pour `Traceability.IntegrationTests`, aucun en échec ni ignoré. Dans le résumé de `frontend` de la n° 108, Vitest donne 33 fichiers et 339 tests réussis. La CI ne construit ni ne lance `compose.yaml` ni `web/Dockerfile` (la tâche `docker` construit seulement l'image de l'API) et ne rejoue aucun scénario de la recette. |

### 27.3 Ce qui n'est pas essayé

Écrit après l'essai.

- **Linux et macOS**, y compris un Mac à puce Apple : l'image de SQL Server 2025 n'existe qu'en AMD64, l'émulation n'est pas essayée. L'essai de la pile par la CI (Linux, AMD64) est décidé et rattaché au lot 17 ; il ne dira rien du Mac à puce Apple. Un changement de `ci.yml` ne se fait que sur demande explicite et nommée de l'auteur.
- **La pile par la CI** : la CI est verte sur ce lot (P9), mais elle ne construit ni ne lance `compose.yaml` ni `web/Dockerfile` : elle ne dit rien de la pile, ni sous Linux ni ailleurs.
- **Les droits d'accès à la base** : l'API se connecte à SQL Server avec `sa`, le compte administrateur, qui contourne tout garde-fou. Un compte dédié à l'API et l'interdiction de modifier le journal sont au lot 16 ; `db-init` créera ce compte.
- **Le mode de production** : l'API en `Development`, le serveur de développement de Vite, Keycloak en `start-dev`, une base sans volume et du HTTP sans certificat.
- **Une remise à zéro complète** (`docker compose down` puis `up -d`) relevée de bout en bout avec les six services jusqu'à l'interface.
- **Les écritures autres qu'une ferme** : stations, lots, mouvements, corrections.
- **Le refus d'écriture d'un `reader` par l'API dans cette pile** : on a seulement vu le bouton caché dans l'interface.
- **Swagger et la console de Keycloak** : jamais ouverts.
- **Un autre navigateur que Chrome**.
- **Le message d'erreur d'une variable manquante** dans `.env` (`${VAR:?message}`) et **la longueur minimale** de `DEMO_USER_PASSWORD`.
- **La limite de 5 minutes de `keycloak-init`** (60 essais espacés de 5 s) : elle n'a jamais été atteinte, et on ne sait pas si elle suffit sur une machine plus lente.
- **La durée de `keycloak-init`** : environ 160 s à chaque `up -d`, parce que chaque appel de `kcadm` démarre une machine virtuelle Java. Ce n'est pas réduit.

### 27.4 Ce qui est prouvé

Écrit le 2026-11-26, après l'essai.

- **`docker compose up -d` construit et lance la pile** sous Windows avec Docker Desktop : base de démonstration, Keycloak avec ses comptes, API et interface (P1, P3, P4, P6).
- **La connexion dans Chrome lit les 20 lots**, corrections comprises (P6).
- **Le jeton demandé par le navigateur à `localhost:8180` est accepté par l'API**, qui joint Keycloak à `keycloak:8080` (réglages `KC_HOSTNAME` et `KC_HOSTNAME_BACKCHANNEL_DYNAMIC`), sans changer le code de l'API (P6, P7).
- **Une ferme écrite par `writer-test` est lue par `reader-test`** (P7).
- **`db-init` et `keycloak-init` se rejouent sans rien écraser** (P2, P3).
- **La CI est verte** sur la branche, sur la pull request et sur `main` (P9) : `006` rend 150 tests (142 automatiques, 8 à l'œil), `dotnet test` 375 tests (118 et 257), Vitest 339 tests. Le lot ne change aucun test et la CI ne lance pas la pile : cela ne prouve rien de plus sur la pile.
- **Non prouvé** : tout ce qui figure en 27.3.

### 27.5 Rejouer la vérification

Depuis la racine du dépôt, dans PowerShell, Docker Desktop lancé. Les mots de passe se saisissent dans `.env`, jamais dans un message ni dans un fichier versionné, et un jeton n'est jamais collé.

```
Copy-Item .env.example .env
docker compose up -d
docker compose ps -a
docker compose logs keycloak-init
. .\docs\recette-outils.ps1
Get-Trial reader-test
Show-Identity
docker compose down
```

Remplir les trois variables de `.env` avant `up -d`. Attendre `api` et `web` à `Up` et `db-init` et `keycloak-init` à `Exited (0)`, puis se connecter dans le navigateur à `http://localhost:5173`. `docker compose down` efface tout.

### 27.6 Point de départ du lot 15 : les réglages de sécurité de GitHub

Relevé le 2026-11-26 vers 09:52 sur des captures d'écran des réglages du dépôt, avant le lot 15. Ces réglages sont dans GitHub, pas dans les fichiers du dépôt : ils se relisent dans les réglages de sécurité du dépôt et ont pu changer depuis. Le lot 14 n'en modifie aucun.

- **Activés par l'auteur ce jour-là** : le signalement privé des failles (bandeau « Repository settings saved ») et la surveillance du dépôt (« Unwatch » affiché ; l'option cochée dans le menu n'est pas relevée).
- **Actifs** : les avis de sécurité, le graphe des dépendances, les alertes Dependabot, les alertes de malware, l'analyse des secrets (Secret scanning) avec la protection à l'envoi (push protection), et Copilot Autofix, sans effet tant que CodeQL n'est pas configuré.
- **Désactivés** : la soumission automatique des dépendances, les mises à jour de sécurité de Dependabot, les mises à jour groupées, les trois « AI Scan » (dépôt, pull requests, applications d'IA) et la correction agentique (« Agentic autofix »).
- **Non configurés** : les mises à jour de version de Dependabot (pas de `.github/dependabot.yml`), CodeQL (« Set up ») et la politique de sécurité (pas de `SECURITY.md`).
- **Seuils d'échec des contrôles** : « High or higher » pour la sécurité, « Only errors » pour les autres.
- **Tri automatique de Dependabot** : « 1 rule enabled », contenu non lu.
- **Une divergence** : une capture de 09:45 donnait les alertes Dependabot « Disabled », celles de 09:52 « On » ; c'est 09:52 qui est retenu.

À prendre en compte au lot 15 :

- **Le secret côté Dependabot.** GitHub ne transmet pas les secrets de Actions aux exécutions déclenchées par Dependabot : `MSSQL_SA_PASSWORD` devra aussi être créé dans les secrets de Dependabot, sinon `backend` sera rouge sur ses pull requests (c'est l'auteur qui le crée).
- **Les fichiers à faire suivre.** Dependabot devra couvrir `compose.yaml` et `web/Dockerfile`, en plus du `Dockerfile` de l'API (à la racine), de `npm` dans `web/`, de NuGet et des actions GitHub. Le suivi d'un fichier compose reste à vérifier au lot 15.
- **Les tags flottants.** `mssql/server:2025-latest` et `node:22-slim` (ajouté par ce lot) ne sont pas fixés ; Keycloak l'est (26.6.2).

## 28. Lot 15 : hygiène du dépôt et de la chaîne d'approvisionnement

Écrit le 2026-11-27, après les essais, sur les quatre commits de la branche `feature/lot-15-hygiene` (`9c41140`, `d5b6198`, `fa0aee7`, `12a53b8`), fusionnée par la pull request n° 39 (commit de fusion `d65493d`). Les essais datent du 2026-11-26 (licence, `SECURITY.md`, double authentification) et du 2026-11-27 (images, Dependabot, CodeQL, formatage), sur un PC Windows avec Docker Desktop. Les exécutions de la CI, le premier passage de Dependabot et les réglages de GitHub relevés après la fusion sont en Q11 à Q15, ajoutés par la pull request de suivi `docs/lot-15-ci`. Tout ce qui figure en 28.2 a été vu ; ce qui ne l'a pas été est en 28.3.

### 28.1 Ce qui est fait

- **Une licence et une politique de sécurité** : `LICENSE` (MIT, `Copyright (c) 2026 Mohamed Bakkar`) et `SECURITY.md` (le signalement privé de GitHub comme seul canal, ce qu'est le projet, ce qu'on n'y promet pas).
- **Les images de base fixées par tag précis et par empreinte (sha256)** : `Dockerfile` (SDK 10.0.404, ASP.NET 10.0.15), `web/Dockerfile` (`node:22.23.5-slim`), `compose.yaml` (SQL Server `2025-CU10-ubuntu-24.04`, Keycloak 26.6.2) et le conteneur SQL Server de `ci.yml` (changement de `ci.yml` autorisé nommément pour ce lot). Les tags précis ont été trouvés en comparant les empreintes avec celles des images déjà utilisées (`docker buildx imagetools inspect`).
- **Le conteneur `web` ne tourne plus en administrateur** : `USER node` dans `web/Dockerfile`.
- **Les fichiers `.env*` sont exclus des constructions d'images** : ajoutés aux deux `.dockerignore`.
- **Dependabot** : `.github/dependabot.yml` suit NuGet, npm (`/web`), les actions GitHub, les `Dockerfile` et `compose.yaml`, chaque semaine, 3 pull requests ouvertes au plus par entrée, sans regroupement. Un délai de 7 jours avant de proposer une nouvelle version est réglé pour NuGet, npm, Docker et Compose, pas pour les actions GitHub. Dependabot signale qu'il ne peut pas l'appliquer aux images de `mcr.microsoft.com` et de `quay.io` (Q12).
- **Dans GitHub** (hors dépôt) : double authentification du compte, secret `MSSQL_SA_PASSWORD` côté Actions et côté Dependabot, mises à jour de sécurité de Dependabot, CodeQL.

### 28.2 Liste de contrôle

| N° | Point | Résultat |
|---|---|---|
| Q1 | Licence et politique de sécurité | `LICENSE` et `SECURITY.md` sont dans le commit `9c41140`. L'affichage par GitHub est relevé en Q15. |
| Q2 | Les images fixées : la pile se construit et se lance | Oui, sous Windows : l'interface montre les 20 lots sur 2 pages. Au premier lancement, `traceability-sql-1` s'est arrêté (code 1, « SQLPAL fatal error ») ; lancé seul, `sql` démarre, et un nouveau lancement complet a abouti. Cause inconnue. `keycloak-init` a duré 466 s, contre environ 160 s au lot 14 : cause inconnue aussi. |
| Q3 | Le conteneur `web` n'est pas administrateur | `whoami` dans le conteneur répond `node`. |
| Q4 | Le tag précis de SQL Server | La version 17.0.5035.5, celle de l'image essayée, est la mise à jour cumulative CU10 (KB5125471, du 2026-10-22), d'après les notes de version de Microsoft. |
| Q5 | Réglages de sécurité de GitHub | Inchangés depuis 27.6, sauf deux : les mises à jour de sécurité de Dependabot sont activées, CodeQL est activé. Le tri automatique de Dependabot (jusque-là non lu) compte deux règles de GitHub : celle qui écarte les alertes à faible impact sur les dépendances de développement est activée, celle des alertes de malware est désactivée. |
| Q6 | CodeQL | Réglage par défaut : GitHub Actions, C# et JavaScript/TypeScript, requêtes « Default », runner standard, scan à chaque push et pull request vers `main` et une fois par semaine. Le premier scan (workflow « CodeQL Setup » n° 1, sur `main`, commit `34bc2a3`) est vert : 1 min 36 s, dont 40 s pour les actions, 1 min 32 s pour C# et 52 s pour JavaScript/TypeScript. Code scanning : 0 alerte ouverte, 0 fermée. |
| Q7 | Secrets de GitHub | `MSSQL_SA_PASSWORD` existe côté Actions et côté Dependabot. Les valeurs ne sont écrites nulle part dans le dépôt. Un secret montré par erreur sur une capture a été remplacé. |
| Q8 | Double authentification | Activée sur le compte avec une application d'authentification. C'est un réglage du compte, pas du dépôt. |
| Q9 | Formatage C# | `dotnet format Traceability.slnx --verify-no-changes` accepte le fichier `.slnx`, lit les quatre projets et rend le code 0 sans rien modifier. Le dépôt n'a pas de `.editorconfig` : seules les règles par défaut sont vérifiées. |
| Q10 | Aucun jeton ni mot de passe dans les fichiers modifiés : recherche de `eyJ`, de `password` et de `secret` | Dans les lignes ajoutées par rapport à `origin/main` (15 fichiers, dont l'ADR 0019, pas encore suivi par git), 13 lignes contiennent `password` ou `secret`, dont cette ligne Q10 : ce sont des noms de variables (`MSSQL_SA_PASSWORD`), des commentaires et des textes de documentation, sans aucune valeur. Aucun texte de la forme `eyJ` suivi de dix caractères ou plus ; la seule ligne qui contient `eyJ` est cette ligne Q10. Aucune commande `DROP`, `TRUNCATE` ni `DELETE`, hors cette ligne Q10. `.env` n'est pas suivi par git : seul `.env.example` l'est. |
| Q11 | La CI du lot | Quatre exécutions vertes le 2026-11-27 : CI n° 112 (push du commit `12a53b8`, 1 min 17 s), CI n° 113 (pull request n° 39, 1 min 15 s), CI n° 114 (push du commit de fusion `d65493d` sur `main`, 1 min 20 s) et CodeQL n° 3 (sur `main`, 1 min 27 s). La pull request n° 39 a eu 10 contrôles verts : `backend` (1 min), `docker` (28 s), `frontend` (34 à 38 s) et les contrôles CodeQL, qui indiquent « No new alerts ». Les contrôles requis par le ruleset `protect-main` (`backend`, `frontend`, `docker`) sont verts ; les contrôles CodeQL n'en font pas partie. `backend` est vert avec le conteneur SQL Server fixé par empreinte : GitHub accepte `tag@sha256:…` dans `services:`. |
| Q12 | Premier passage de Dependabot | Dix pull requests ouvertes (n° 40 à 49) : 3 NuGet, 3 npm, 3 Docker et 1 Docker Compose, après la fusion, par les exécutions « Dependabot Updates » n° 1 à 5 sur `main`. Dependabot trouve `compose.yaml` et met à jour le tag et l'empreinte ensemble (n° 43, Keycloak). Le contrôle `backend` de ses pull requests passe avec le secret propre à Dependabot : chaque valeur de `MSSQL_SA_PASSWORD` fonctionne dans son contexte, leur égalité n'a pas à être prouvée. Un avertissement sur le délai de 7 jours est affiché sur les pull requests des images `mcr.microsoft.com` (n° 40 et 41) et `quay.io` (n° 43). Pour npm, `oxlint` 1.94.0 (publiée le 2026-11-16) est proposée alors que la 1.95.0 existe depuis le 2026-11-23, et `vitest` 5.1.1 (2026-11-18) alors que la 5.1.2 date du 2026-11-25 : cohérent avec un délai de 7 jours appliqué ; `jsdom` 31.0.1 est la dernière version, ce cas ne prouve rien. Dates lues dans le registre npm le 2026-11-27. |
| Q13 | Dependabot et les actions GitHub | Aucune pull request pour `github_actions`. L'exécution « github_actions in /. - Update n° 1734490215 » (n° 4, 31 s, verte, sur le commit `d65493d`) a lu `ci.yml` : `actions/checkout` 7.0.1, `actions/setup-dotnet` 6.1.0 et `actions/setup-node` 7.1.0 sont déjà aux dernières versions (« No update needed »). Le journal indique un délai de 3 jours pour ces actions, alors que `dependabot.yml` n'en règle aucun : l'origine de cette valeur n'est pas établie. Il contient aussi le message « Failed to parse GITHUB_REGISTRIES_PROXY environment variable » : la variable est vide, le job est vert, la cause n'est pas établie. |
| Q14 | Secrets dans le dépôt et son historique | Secret scanning de GitHub : 0 alerte ouverte, 0 fermée (« No secrets found »). Il repère les secrets de formats connus. Recherche dans les 198 commits de l'historique local (lignes ajoutées seulement, valeurs non affichées) : aucun texte de la forme `eyJ` suivi de dix caractères ou plus, aucune affectation de `password`, `pwd` ou `secret` avec une valeur littérale, sauf la phrase H16 de ce fichier, qui est du texte. `.env` n'a jamais été ajouté à l'historique et `.gitignore` l'exclut (règle `*.env`). `identity/traceability-realm.json` et `src/Traceability.Api/appsettings.Development.json` sont suivis par git ; la recherche n'a rien trouvé dans le second, le contenu du premier n'a pas été relu pour ce lot (constat H16). |
| Q15 | Affichage de la licence et de la politique de sécurité, signalement privé | La page Security policy de GitHub affiche `SECURITY.md` ; la colonne About de la page d'accueil affiche « MIT license » et « Security policy ». Le signalement privé de vulnérabilités est activé (Settings, Advanced Security : le bouton proposé est « Disable »). Pour un visiteur non connecté, la page Advisories affiche le bouton « Report a vulnerability » ; le propriétaire y voit « New draft security advisory ». Aucun avis n'existe (0 en Triage, Draft, Published et Closed). |

### 28.3 Ce qui n'est pas essayé

- **Dependabot, limite de pull requests** : la limite de 3 est-elle par entrée ou par dossier ? Les 10 pull requests vues (3 NuGet, 3 npm, 3 Docker, 1 Compose) sont compatibles avec les deux lectures, rien ne tranche.
- **Dependabot, délai de 7 jours** : l'effet est vu sur npm (Q12). Il n'est pas vérifié pour NuGet (dates de publication non obtenues), ni pour l'image `node` de Docker Hub. L'origine du délai de 3 jours des actions n'est pas établie (Q13).
- **Dependabot, page d'Insights** : l'onglet Dependabot affiche un triangle d'avertissement rouge pour `global.json` et `web/package.json`, orange pour `Dockerfile` et `compose.yaml`, aucun pour `ci.yml`. Le sens et le contenu de ces avertissements ne sont pas relevés. `web/Dockerfile` et les fichiers `.csproj` n'y figurent pas, alors que des pull requests existent pour NuGet et Docker : non expliqué.
- **Alertes de sécurité avec correctif** : aucune alerte n'existe, la création d'une pull request de sécurité n'est pas testable.
- **CodeQL** : « 0 alerte » veut dire que les requêtes par défaut n'ont rien trouvé, pas que le code est sans faille. Copilot Autofix n'a aucun effet tant qu'il n'y a pas d'alerte.
- **Les `.dockerignore`** : l'exclusion de `.env*` n'est pas testée.
- **Le realm Keycloak** : son contenu n'a pas été relu pour ce lot (constat H16, Q14).
- **Le signalement privé d'une faille** : le bouton est vu (Q15), aucun signalement n'a été envoyé de bout en bout.
- **Reporté au lot 17** : une vérification du format C# par la CI (le résultat de `dotnet format` sous Linux n'est pas comparé à celui de Windows), un `.editorconfig`, des analyseurs, un rapport de couverture, `persist-credentials: false` sur les trois `checkout` de `ci.yml`, des fichiers de verrouillage NuGet.
- **Hors de ce lot** : la pile sous Linux (lot 17), les droits d'accès à la base et le compte `sa` (lot 16), le mode de production.

### 28.4 Ce qui est prouvé

- La pile se construit et se lance sous Windows avec les images fixées par tag et empreinte (Q2), avec un arrêt de SQL Server dont la cause est inconnue.
- L'interface web tourne sous un compte non administrateur (Q3).
- CodeQL analyse les trois langages sur `main` et ne signale aucune alerte (Q6).
- `dotnet format` accepte `Traceability.slnx` et ne trouve rien à reformater avec les règles par défaut (Q9).
- Les réglages de Dependabot et ses règles de tri sont ceux de Q5 ; les secrets existent des deux côtés (Q7).
- La CI passe sur la branche, la pull request et `main` avec les images fixées par empreinte, conteneur de service compris (Q11).
- Dependabot trouve `compose.yaml`, met à jour le tag et l'empreinte ensemble, et son secret fonctionne (Q12) ; aucune pull request pour les actions GitHub, qui sont à jour (Q13).
- Secret scanning ne signale rien et l'historique ne contient ni jeton de la forme `eyJ` ni mot de passe littéral (Q14).
- GitHub affiche `SECURITY.md` et la licence, et le signalement privé est ouvert aux visiteurs (Q15).
- Non prouvé : tout ce qui figure en 28.3.

### 28.5 Rejouer la vérification

Depuis la racine du dépôt, dans PowerShell. Un jeton ou un mot de passe n'est jamais collé dans un message.

```
dotnet format Traceability.slnx --verify-no-changes
$LASTEXITCODE
git status --short
docker buildx imagetools inspect quay.io/keycloak/keycloak:26.6.2
docker compose up -d --build
docker compose ps -a
```

`dotnet format` doit rendre le code 0 et `git status` rester vide. `docker buildx imagetools inspect` donne l'empreinte à comparer avec celle de `compose.yaml` (même commande pour chaque image). Pour l'utilisateur du conteneur `web`, lancer `whoami` dans ce conteneur. Dans GitHub : Settings, Advanced Security (Q5), Actions (le workflow « CodeQL ») et Security and quality, Code scanning (les alertes).

Pour retrouver les exécutions de la CI : Actions, champ de recherche (`branch:main` ou le nom d'une branche). Pour le passage de Dependabot : Insights, Dependency graph, onglet Dependabot, « Recent update jobs » de chaque fichier.
