# Vérification

Ce document garde les preuves observées : la base de données (lot 1, sections 1 à 5), les procédures stockées (lot 2a, section 6) et les données volumineuses, les index et les mesures (lot 2b, section 7), puis les procédures de lecture pour l'API (lot 3a, section 8), l'API des fermes et des stations (lot 3b, section 9), l'API des lots (lot 3c, section 10), l'interface web de lecture (lot 4a, section 11), l'interface web d'écriture (lot 4b, section 12), l'optimisation de la liste des lots (lot 5, section 13), l'intégration continue (lot 6, section 14), SQL Server en conteneur (lot 7, section 15), l'API en conteneur (lot 8, section 16) et la CI complétée (lot 9, section 17). Le modèle est décrit dans [modele-de-donnees.md](modele-de-donnees.md) ; l'avancement du projet est dans le [README](../README.md).

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
| J23 | Casse volontaire de l'interface, sur une copie de `web/` hors du dépôt : `canWrite` (`web/src/auth/roles.ts`) renvoie toujours vrai. Les tests de l'interface doivent échouer ; relever le nombre. | Observé le 2026-11-09, sur une copie de `web/` installée avec `npm ci` (Node 22.23.4, sous Linux : pas sur le PC de Mohamed) ; le dépôt n'est pas touché. Avant la casse : 27 fichiers, 248 tests passés. Avec `canWrite` toujours vrai : `Test Files  3 failed | 24 passed (27)`, `Tests  19 failed | 229 passed (248)` ; échecs dans `App.auth.test.tsx` (16), `WriterOnly.test.tsx` (2) et `roles.test.ts` (1), dont « is false for a reader, for another role and for no role ». Fichier remis à l'identique (comparé avec `diff`). |
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
- Les casses volontaires de l'interface (J23 et J24) sont faites sur une copie de `web/` sous Linux, pas sur le PC de Mohamed ; la casse de la règle CORS (J3) est faite dans le dépôt, avec contrôle de l'empreinte.
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
