# Vérification (lots 1, 2a, 2b, 3a, 3b, 3c, 4a, 4b, 5 et 6)

Ce document garde les preuves observées : la base de données (lot 1, sections 1 à 5), les procédures stockées (lot 2a, section 6) et les données volumineuses, les index et les mesures (lot 2b, section 7), puis les procédures de lecture pour l'API (lot 3a, section 8), l'API des fermes et des stations (lot 3b, section 9), l'API des lots (lot 3c, section 10), l'interface web de lecture (lot 4a, section 11), l'interface web d'écriture (lot 4b, section 12), l'optimisation de la liste des lots (lot 5, section 13) et l'intégration continue (lot 6, section 14). Le modèle est décrit dans [modele-de-donnees.md](modele-de-donnees.md) ; l'avancement du projet est dans le [README](../README.md).

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
- **Données** : `TraceabilityDev` a été relue au début de la session (200 fermes, 30 stations, 40 fonctions, 1 000 000 de lots, 3 250 000 mouvements) et n'a pas été recomptée à la fin ; rien n'y a été écrit volontairement. `TraceabilityTest` était vide au début de la session et est vidée par les tests.
- **Reportés de la section 9.3** : CORS non configuré et aucun frontend ; chaîne de connexion lue à la première utilisation ; .NET 10 sur Windows 11 22H2 ; les deux garde-fous des tests jamais déclenchés (50099 et refus de démarrer de la fixture) ; aucune mesure de charge côté API.

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
- **Non prévus au plan, décidés pendant le lot, après avoir vu la page** : les boutons « Début » et « Fin », un thème de couleurs chaudes défini à un seul endroit (`src/index.css`), et un fond d'écran de dessins (fruits, légumes, caisses, cartons) tracés en SVG.
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
- **La cause des échecs** : une attente de mémoire est plausible (vue pendant un échec, à 9,7 s ; pas lue jusqu'à la coupure à 30 s), et la mémoire de la machine l'est aussi (une seule observation, sans essai témoin : l'arrêt d'Edge a coïncidé avec un budget qui passe de 5 à 1 017 Mo).
- **La demande de mémoire du nouveau plan** : non lue. On suppose qu'elle est petite faute de tri.
- **Le coût en écriture** : mesuré seulement par `CreateBatch` dans SSMS, deux mesures séparées de 27 minutes et non alternées ; pas dans l'application, pas sous charge.
- **Le filtre par statut** : pas amélioré (10 574 lectures pour le total, 9 351 pour la page 1 de `RECEIVED`) ; aucun index sur `Status` n'a été essayé.
- **La dernière page lit toujours toute la table** (10 424 pages) : la pagination par `OFFSET` reste linéaire ; la pagination par clé n'est pas essayée.
- **Autres écritures du total et de la page** : les variantes par branches `IF` et le SQL dynamique ne sont pas mesurés ; les coûts avec filtre ne sont mesurés que pour la page 1 (les lignes des pages avec filtre ont été comparées, pas leur coût).
- **L'interface web** n'a pas été essayée dans le navigateur avec la nouvelle procédure (le bouton « Fin » n'a été exercé que par l'API).
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

Écrit le 2026-10-26 après observation. Aucune hypothèse n'avait été écrite avant pour le déclenchement par pull request : ce qui suit est un constat, pas une hypothèse confirmée après coup. Statuts et durées des exécutions : page publique « Actions » du dépôt ; détail des étapes : journaux du run n° 7 copiés par Mohamed.

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
- **L'authentification Windows** : la CI ne prouve que l'authentification SQL. Le chemin utilisé en local (authentification Windows) n'est pas couvert.
- **La migration d'`ubuntu-latest`** (annoncée vers Ubuntu 26 à partir du 2026-10-19) : le runner est fixé à `ubuntu-24.04`, mais la différence n'a pas été observée.
- **L'étiquette `2025-latest`** : elle se déplace avec le temps ; seule l'image des exécutions relevées (digest au 14.5) est connue. Une version plus récente du moteur peut changer un résultat.
- **Une pull request venant d'un fork** : selon la documentation de GitHub (« secrets are not passed to the runner when a workflow is triggered from a forked repository »), le secret ne serait pas transmis et la tâche `backend` échouerait. Non essayé.
- **Une CI exigée avant fusion** : une règle `protect-main` l'exige depuis le 2026-10-26 (constat en 14.10). Qu'elle empêche de fusionner une CI rouge est observé : voir 14.11 (hypothèses) et 14.12 (résultats).
- **L'application lancée à la main contre le SQL Server de la CI** : la CI ne lance que les tests ; l'API y démarre à l'intérieur des tests d'intégration. Ni `dotnet run`, ni Swagger UI, ni l'interface (Vite) n'ont été essayés contre un SQL Server en conteneur. Aucun Dockerfile n'existe dans le dépôt.
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

  Résultat observé : le hash `13f2078…` suivi de ses deux parents. Ce hash est celui relevé le 2026-10-26 : je n'ai pas vérifié à quel moment GitHub recalcule la fusion, ni si « Re-run all jobs » reteste le même commit de fusion ou un nouveau.
- Pour comparer avec la machine de développement : `dotnet test Traceability.slnx` (résumé attendu `total : 163; échec : 0; réussi : 163`) et, dans `web/`, `npm run lint`, `npm run build`, `npm test`.

### 14.10 Protection de `main` : constat

Observé le 2026-10-26 sur GitHub, par captures d'écran de Mohamed. Décision et alternatives : [ADR 0010](adr/0010-protection-de-main-par-ruleset.md).

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

1. Mohamed crée la branche jetable `test/ci-red-check` à partir de `feature/lot-6-ci`, une fois les commits de la documentation poussés.
2. Une seule ligne change : dans `src/Traceability.Api/Errors/SqlErrorTranslator.cs`, la ligne qui traduit la famille d'erreurs 502xx passe de 409 à 400. C'est le même défaut que la « casse volontaire » du lot 3b (section 9.2).
3. Mohamed commite et pousse, puis ouvre une pull request de cette branche vers `main`, **pas en brouillon** : le message « Draft pull requests cannot be merged » masquerait l'effet de la règle. Cette pull request affichera aussi les commits de `feature/lot-6-ci`, puisque la branche en part.
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

Observé le 2026-10-26 entre 20:59 et 21:12 (heure locale = UTC), par les captures d'écran et les journaux copiés par Mohamed. Les hypothèses E1 à E3 sont écrites en 14.11 (commit `2edf254`), avant l'essai ; elles ne sont pas modifiées.

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
