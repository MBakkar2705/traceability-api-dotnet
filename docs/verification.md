# Vérification (lots 1, 2a, 2b, 3a et 3b)

Ce document garde les preuves observées : la base de données (lot 1, sections 1 à 5), les procédures stockées (lot 2a, section 6) et les données volumineuses, les index et les mesures (lot 2b, section 7), puis les procédures de lecture pour l'API (lot 3a, section 8) et l'API des fermes et des stations (lot 3b, section 9). Le modèle est décrit dans [modele-de-donnees.md](modele-de-donnees.md) ; l'avancement du projet est dans le [README](../README.md).

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

### 8.4 Rejouer la vérification

- Prérequis : `TraceabilityTest` avec `001`, `002`, `004` et `005` (voir le README), puis `011` (mode SQLCMD actif, nom de la base réglé par `:setvar DbName`).
- Exécuter `006_check_procedures.sql` (résumé attendu `38 / 34 / 4`), puis `012_check_list_procedures.sql` (résumé attendu `16 / 10 / 6`), chacun dans une nouvelle fenêtre SSMS.
- Les tests à l'œil : avant chacun des tests 32, 33 et 38 de `006` et des tests de contenu de `012`, le script affiche dans la grille une ligne « Test N » qui dit ce qu'il faut voir, puis les tableaux de la procédure. Les tableaux s'empilent dans l'onglet Résultats : agrandir le volet et faire défiler.
- Pour la mesure : `009_measure_searches.sql` sur `TraceabilityDev` (1 000 000 de lots), plan d'exécution réel actif (Ctrl+M), puis copier le contenu de l'onglet Messages.
- Si SSMS affiche des erreurs rouges « Impossible de trouver la procédure stockée » alors que les procédures existent, actualiser le cache de l'IntelliSense (Ctrl+Maj+R) : le compteur d'erreurs est retombé à 0, observé aux lots 2a et 3a.

## 9. Lot 3b : API pour les fermes et les stations

Observé le 2026-10-20 sous Windows 11, avec le SDK .NET 10.0.402 (exécution 10.0.13), SQL Server 2025 (instance locale 17.0) et xUnit 2.9.3. Les tests d'intégration tournent sur la base `TraceabilityTest`. Les essais à la main (section 9.2), en lecture seule, ont été faits sur `TraceabilityDev`. Les routes sont décrites dans le [README](../README.md), les erreurs des procédures dans [procedures.md](procedures.md). Les données de test sont inventées.

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
- **Deux requêtes qui créent le même code au même moment** : l'erreur 2627 n'est prouvée que par un `INSERT` direct, car les procédures vérifient le code avant d'insérer.
- **L'erreur 500** : elle n'est testée qu'en unitaire (U2). Aucune panne SQL n'a traversé l'API, et l'écriture de la vraie erreur dans le journal du serveur n'a pas été observée.
- **Longueurs** : un code trop long est refusé par l'API (testé en unitaire), mais pas par un test HTTP. La longueur du nom et de la région (100) n'est contrôlée ni par l'API ni par un test : le comportement avec un texte plus long n'est pas observé.
- **Cas non testés par HTTP** : une page au-delà de la fin pour les stations ; les tailles de page 1 et 1 000 ; la casse des codes.
- **Swagger UI** : il ne documente ni les erreurs possibles ni des descriptions des routes (prévu au lot 3c), et affiche « integer | string ($int32) » comme type de `pageNumber` et `pageSize`, sans que j'en aie cherché la cause.
- **CORS** : non configuré, aucun frontend n'a été essayé.
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
- Pour voir un test échouer : dans `src/Traceability.Api/Errors/SqlErrorTranslator.cs`, passer le 409 de la famille 502xx à 400, lancer `dotnet test Traceability.slnx` (4 échecs unitaires, 3 d'intégration), puis rétablir la ligne.

## 10. Lot 3c : API pour les lots

Observé le 2026-10-21 sous Windows 11, avec le SDK .NET 10.0.402 (exécution 10.0.13), SQL Server 2025 (instance locale 17.0) et xUnit 2.9.3. Les tests d'intégration tournent sur la base `TraceabilityTest`. Les routes sont décrites dans le [README](../README.md), les erreurs des procédures dans [procedures.md](procedures.md). Les données de test sont inventées. Mohamed indique que sa machine est réglée sur UTC : je ne l'ai pas vérifié autrement que par un résultat de test (voir 10.2, casse volontaire).

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
- **Tailles des colonnes (non prévu)** : `FieldLimits`, `RequireText` et `RequireQuantity` ont été ajoutés après que des tests d'observation ont montré des valeurs coupées, arrondies ou refusées par SqlClient (voir 10.2). Décidé avec Mohamed : on corrige dans ce lot. Le type de mouvement et le filtre de statut (20 caractères) sont protégés de la même façon.
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
- **Swagger UI** (regardé par Mohamed dans Edge, avec l'API lancée sur `TraceabilityDev`, sans cliquer sur « Execute ») : les 10 routes s'affichent avec leur résumé, sous 3 titres (Batches 4, Farms 2, Stations 4) ; `POST /batches` montre ses 5 réponses (201, 400, 404, 409, 422) avec nos descriptions et les `errorCode`, et le schéma `CreateBatchRequest` affiche la description de chaque champ ; `GET /batches` montre le texte `remarks`, les 4 paramètres avec leur description et les valeurs par défaut 1 et 20.
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
- **Données** : `TraceabilityDev` a été relue au début de la session (200 fermes, 30 stations, 40 fonctions, 1 000 000 de lots, 3 250 000 mouvements) et n'a pas été recomptée à la fin ; rien n'y a été écrit volontairement. `TraceabilityTest` était vide au début de la session et est vidée par les tests.
- **Machine en UTC** : indiqué par Mohamed, non vérifié autrement.
- **Reportés de la section 9.3** : CORS non configuré et aucun frontend ; chaîne de connexion lue à la première utilisation ; .NET 10 sur Windows 11 22H2 ; les deux garde-fous des tests jamais déclenchés (50099 et refus de démarrer de la fixture) ; aucune mesure de charge côté API.

### 10.4 Rejouer la vérification

- Prérequis : le README, section « API (lots 3b et 3c) ».
- `dotnet build Traceability.slnx`, puis `dotnet test Traceability.slnx` : résumé attendu `total : 154; échec : 0; réussi : 154`. **Attention** : les tests d'intégration exécutent 5 `DELETE` sans `WHERE` sur `TraceabilityTest` (jamais sur `TraceabilityDev`).
- Swagger UI : `dotnet run --project src/Traceability.Api --launch-profile https`, puis `https://localhost:7080/swagger`. L'API lit `TraceabilityDev` : ne pas cliquer sur « Execute » pour les routes `POST` (elles écriraient dans la base) ni pour `GET /batches` (le total est lent sur un million de lots).
- Pour voir un test échouer : dans `src/Traceability.Api/Validation/FieldErrors.cs`, remplacer `FieldLimits.QuantityDecimals))` par `FieldLimits.QuantityDecimals + 5))` dans `RequireQuantity`, lancer `dotnet test Traceability.slnx` (3 échecs : 1 unitaire et 2 d'intégration), puis rétablir la ligne.
