# Mesures de recherche et index (lots 2b et 3a)

Ce document garde la trace des **hypothèses** posées avant de mesurer, puis des **mesures** avant et après chaque index.

Règle de travail : les hypothèses (section 3) sont écrites et enregistrées dans Git **avant** la moindre mesure. L'historique Git montre cet ordre. Aucune hypothèse n'est modifiée après coup : si une mesure la contredit, on l'écrit dans la section 4, on ne réécrit pas la section 3.

Date des hypothèses : 2026-10-19.

Exception : la section 4.3 (le total de `ListBatches`, lot 3a, 2026-10-20) a été mesurée sans hypothèse chiffrée écrite et enregistrée avant. C'est un écart avec la règle ci-dessus : la mesure voulait chiffrer un coût, pas tester une hypothèse.

## 1. Ce qui a été observé sur les données (fait, pas hypothèse)

Jeu de données : 1 000 000 de lots inventés et 3 250 000 mouvements dans `TraceabilityDev`, générés par `database/007_generate_volume_data.sql`. Le contrôle `database/008_check_volume_data.sql` a donné 28 contrôles sur 28 réussis.

Tailles observées par le script 008 (1 page = 8 Ko, donc 1 Mo ≈ 128 pages) :

| Structure | Taille observée | Pages (calcul) | Lignes par page (calcul) |
|---|---|---|---|
| `Batch`, clé primaire (table elle-même, triée par `BatchId`) | 81,44 Mo | ≈ 10 424 | ≈ 96 |
| `Batch`, index unique `UQ_Batch_BatchCode` | 58,51 Mo | ≈ 7 489 | non calculé |
| `Movement`, clé primaire (table elle-même, triée par `MovementId`) | 194,92 Mo | ≈ 24 950 | ≈ 130 |

Il n'existe aucun autre index que ceux-là (voir `docs/modele-de-donnees.md`).

Répartition des données qui compte pour les mesures :

- Les statuts suivent le numéro du lot : lots 1 à 600 000 `SHIPPED`, 600 001 à 750 000 `PACKED`, 750 001 à 900 000 `SORTED`, 900 001 à 1 000 000 `RECEIVED`. Les lots `RECEIVED` sont donc les **derniers** dans l'ordre de `BatchId`.
- 20 grandes fermes (`F001` à `F020`) ont 25 000 lots chacune. 180 petites fermes (`F021` à `F200`) en ont 2 777 ou 2 778 chacune. Les lots d'une ferme sont répartis régulièrement dans toute la plage des numéros.

## 2. Comment on mesure

Pour chaque recherche, avec `SET STATISTICS IO ON` et `SET STATISTICS TIME ON`, plus le plan d'exécution réel (Ctrl+M dans SSMS) :

- **Lectures logiques** (`logical reads`) : nombre de pages de 8 Ko lues en mémoire. C'est la mesure principale : elle ne change pas d'une exécution à l'autre.
- **Temps** (`elapsed time`) : indicatif seulement. On exécute plusieurs fois et on note l'ordre de grandeur, pas une valeur exacte.
- **Plan** : on note le type d'accès à chaque table. *Scan* = lecture d'une grande partie de la structure. *Seek* = descente directe vers les lignes cherchées.

Les mesures sont faites sur une seule machine (SQL Server 2025 Developer, environ 8 Go de RAM), avec des données inventées. Elles servent à comparer « avant » et « après » dans les mêmes conditions. Elles ne disent rien d'un autre volume ni d'une autre machine.

## 3. Hypothèses (non vérifiées)

Toutes les hypothèses ci-dessous sont **non vérifiées** au moment de leur écriture. Les ordres de grandeur sont calculés à partir des tailles de la section 1.

### R1. Un lot par son code (début de `trace.GetBatch`, et `trace.AddMovement`)

Requête : `WHERE BatchCode = @BatchCode` sur `Batch`.

Hypothèse : l'accès se fait par *Seek* sur `UQ_Batch_BatchCode`, avec quelques pages seulement (quelques unités, très loin des 10 424 pages de la table). Aucun index à ajouter.

### R2. Le parcours d'un lot (deuxième requête de `trace.GetBatch`)

Requête : `WHERE m.BatchId = @BatchId ORDER BY m.MovementId` sur `Movement`.

Hypothèse : aucun index ne commence par `BatchId` sur `Movement`. Le plan fait un *Scan* de toute la table, soit ≈ 24 950 pages lues pour retrouver 1 à 4 mouvements.

Index candidat : `Movement (BatchId)`. Hypothèse après index : *Seek* sur le nouvel index, quelques pages (unités), et pas d'étape de tri, parce que dans un index non unique SQL Server ajoute la clé primaire (`MovementId`) à la suite de `BatchId`, ce qui donnerait déjà l'ordre voulu. **À vérifier dans le plan.**

Variante à comparer si les lectures le justifient : index « couvrant », qui contient aussi les colonnes demandées (`StationId`, `MovementType`, `QuantityKg`, `OccurredAt`), pour éviter une lecture dans la table par mouvement trouvé. Pour 1 à 4 mouvements, le gain attendu est faible (quelques pages) ; l'index couvrant est plus gros. C'est le seul point qui pourrait devenir un ADR 0004, et seulement si les mesures montrent une différence réelle.

### R3. Les lots d'une ferme (`trace.ListBatches` avec `@FarmCode`)

Requête : `WHERE b.FarmId = @FarmId ORDER BY b.BatchId`, page de 50 lots.

Hypothèse sans index : le plan lit la table dans l'ordre de `BatchId` et s'arrête quand la page est pleine (pas de lecture complète).

- Grande ferme (`F001`) : 1 lot sur 40 lui appartient. Page 1 : environ 2 000 lignes lues, soit ≈ 21 pages.
- Petite ferme (`F021`) : 1 lot sur 360 environ. Page 1 : environ 18 000 lignes lues, soit ≈ 190 pages.
- Plus la page demandée est loin, plus le nombre de pages lues augmente.

Index candidat : `Batch (FarmId)`. Hypothèse après index : *Seek* sur `FarmId`, ordre `BatchId` déjà fourni par l'index (clé primaire ajoutée automatiquement), donc quelques pages pour la page 1 quelle que soit la ferme, plus des lectures dans la table pour récupérer les autres colonnes (une par lot de la page, 50 au maximum). **À vérifier dans le plan.**

### R4. Les lots d'un statut (`trace.ListBatches` avec `@Status`)

Requête : `WHERE b.Status = @Status ORDER BY b.BatchId`, page de 50 lots.

Hypothèse sans index : le coût dépend fortement du statut, à cause de la façon dont les données ont été générées.

- `SHIPPED`, page 1 : les 50 premiers lots sont `SHIPPED`, donc moins d'une page à lire.
- `RECEIVED`, page 1 : le premier lot `RECEIVED` est le numéro 900 001, donc ≈ 900 000 lignes à passer avant d'en trouver un, soit ≈ 9 380 pages.

Index candidat : `Batch (Status)`. Hypothèse après index : très utile pour `RECEIVED` (de ≈ 9 380 pages à quelques dizaines), sans effet utile pour `SHIPPED` (déjà bon sans index). Un index sur une colonne à seulement 4 valeurs est à justifier par cette mesure, pas par principe.

### R5. Une page lointaine, sans filtre

Requête : sans `@Status` ni `@FarmCode`, page 900 de 1 000 lignes (saut de 899 000 lignes).

Hypothèse : le coût vient du saut, pas du filtre : ≈ 9 370 pages lues. Aucun index ne règle cela, parce que `OFFSET` oblige à compter les lignes sautées. Ce cas servira de limite connue de la pagination par `OFFSET`, à noter dans la documentation, pas à « corriger » avec un index.

### R6. Un plan réutilisé pour des valeurs très différentes (`trace.ListBatches`)

Dans la procédure, `@Status` est un paramètre. `@FarmId`, lui, est une variable locale calculée à partir de `@FarmCode`.

Hypothèse : le plan est compilé à la première exécution après création ou recompilation, puis réutilisé. Pour `@Status`, la première valeur utilisée peut donc décider du plan des appels suivants. Pour `@FarmId`, l'estimation du nombre de lignes est la même quelle que soit la ferme, donc la même pour une grande et une petite ferme. Conséquence possible : un plan bien adapté à l'un des deux cas et moins bon pour l'autre.

Observation prévue : comparer lignes estimées et lignes réelles dans le plan, avec un ordre d'appels différent, et `EXEC sp_recompile 'trace.ListBatches'` entre les deux séries pour repartir d'un plan neuf.

### R7. Ce qui n'a pas de candidat

Aucune procédure du lot 2a ne cherche des mouvements par station ou par type de mouvement, ni des lots par date de récolte ou par variété. On n'ajoute donc aucun index pour ces colonnes : il coûterait de l'espace et ralentirait les écritures sans servir à une recherche existante.

## 4. Mesures

### 4.1 Avant (aucun nouvel index), 2026-10-19

Conditions : script `database/009_measure_searches.sql` exécuté une seule fois dans SSMS sur 1 000 000 de lots, avec le plan d'exécution réel. C'est une **première exécution** : l'onglet Messages montre des lectures physiques (lecture sur disque), donc les temps sont gonflés par rapport à une exécution avec les données déjà en mémoire. Les lectures logiques sont la mesure de référence.

Avant cette mesure, les procédures de `database/004` et `database/005` n'existaient pas dans `TraceabilityDev` (la requête sur `sys.procedures` a renvoyé 0 ligne). Elles y ont été créées avec 004 puis 005, sans toucher aux données.

| Cas | Table (lectures logiques) | Plan observé | Temps écoulé |
|---|---|---|---|
| R1 : lot par code | `Batch` : 3 | *Seek* sur `UQ_Batch_BatchCode`, 1 ligne sur 1 | environ 1 ms |
| R2 : mouvements d'un lot | `Movement` : **25 412** (5 analyses) ; `Station` : 8 | *Scan* de l'index cluster de `Movement` (96 % du coût), 4 lignes trouvées, plan parallèle ; pas d'étape de tri | 236 ms |
| R3 : grande ferme `F001` | `Batch` : 26 ; `Farm` : 100 | plan non examiné | 6 ms |
| R3 : petite ferme `F021` | `Batch` : 189 ; `Farm` : 100 | *Scan* de la clé primaire de `Batch` dans l'ordre, 50 lignes, puis `Top` ; jointure avec `Farm` par boucles imbriquées | environ 40 ms |
| R4 : statut `SHIPPED` | `Batch` : 4 ; `Farm` : 100 | plan non examiné | moins de 1 ms |
| R4 : statut `RECEIVED` | `Batch` : **9 351** ; `Farm` : 100 | *Scan* de la clé primaire de `Batch` dans l'ordre, 50 lignes sur 50, puis 50 *Seek* sur `Farm` | 625 ms |
| R5 : page 900 de 1 000 | `Batch` : 9 351 ; `Farm` : **1 800 000** | *Scan* de `Batch` (1 000 000 de lignes) et de `Farm` (200), jointure, **tri de 900 048 lignes avec débordement dans `tempdb`** (10 523 pages écrites et relues), puis 1 000 lignes | 1 615 ms (1re exécution), 8 s (2e exécution, avec plan réel) |
| R6 : plan réutilisé | non fait | | |

Index absents proposés par SQL Server dans les plans (suggestions de SQL Server, pas des preuves) :
- plan de R2 : `Movement (BatchId)`, impact annoncé 99,79 ; les colonnes incluses n'ont pas été lues en entier ;
- plan de R5 : `Batch (FarmId)` avec `BatchCode`, `Variety`, `HarvestDate`, `QuantityKg`, `Status` en colonnes incluses, impact annoncé 40,146 ;
- plan de R4 `RECEIVED` : aucune suggestion dans le texte du plan.

Écart avec les hypothèses de la section 3 :

| Hypothèse | Résultat |
|---|---|
| R1 | conforme : *Seek*, 3 lectures sur `Batch` |
| R2 | conforme : *Scan* de toute la table. 25 412 lectures observées contre environ 24 950 prévues ; l'écart d'environ 2 % n'est pas expliqué |
| R3 | conforme : 189 lectures pour `F021` (prévu environ 190), 26 pour `F001` (prévu environ 21). Le plan de `F001` n'a pas été examiné |
| R4 `RECEIVED` | conforme : 9 351 lectures (prévu environ 9 380) |
| R4 `SHIPPED` | direction juste, chiffre faux : 4 lectures observées alors que l'hypothèse disait moins d'une page. La cause n'a pas été examinée |
| R5 | **incomplète** : les 9 351 lectures de `Batch` sont conformes, mais le plan n'est pas une lecture ordonnée avec arrêt : il joint, trie 900 048 lignes avec débordement dans `tempdb`, et la table `Farm` coûte 1 800 000 lectures, ce qui n'était pas prévu. Cause de ce chiffre : non établie |

Les 100 lectures sur `Farm` de R3 et R4 correspondent aux 50 *Seek* observés dans le plan, à 2 lectures chacun. Cette explication ne vaut pas pour R5.

### 4.2 Après chaque index

Un index à la fois : index créé, mesure « après » avec le même script, hypothèse confirmée ou non, décision.

#### Index 1 : `IX_Movement_BatchId` sur `Movement (BatchId)`, sans colonnes incluses (2026-10-19)

Créé par `database/010_create_indexes.sql`. Mesuré avec le bloc R2 de `database/009_measure_searches.sql` (plan réel actif), puis la partie C de `database/008_check_volume_data.sql`.

| Mesure | Avant | Après |
|---|---|---|
| `Movement`, lectures logiques (R2) | 25 412 (5 analyses) | **15** (1 analyse) |
| Plan de la requête sur `Movement` | *Scan* de l'index cluster (96 % du coût), plan parallèle, pas de tri | *Seek* sur `IX_Movement_BatchId` (23 %), puis *Key Lookup* sur la clé primaire (52 %), 4 lignes ; plan non parallèle ; **pas d'étape de tri** |
| `Batch`, `Farm`, `Station` (R1 et le reste de `GetBatch`) | 3 ; 2 ; 8 | 3 ; 2 ; 8 (inchangé) |
| Taille de l'index | n/a | 56,72 Mo utilisés (environ 7 260 pages), soit environ 29 % de la taille de la clé primaire de `Movement` (194,92 Mo) |
| Taille utilisée de la base (somme des index et tables) | 334,98 Mo | 391,70 Mo (+17 %) |

Les 28 contrôles de `008` restent à 28 sur 28 après la création de l'index.

Hypothèse R2 :
- *Seek* sur le nouvel index : **confirmée**.
- Pas d'étape de tri, l'ordre venant de l'index : **confirmée** (observée dans le plan).
- « Quelques pages (unités) » : **à nuancer** : 15 lectures observées, au-dessus de « unités ».
- Variante couvrante : non encore testée. Le plan montre un *Key Lookup* (52 % du coût, 4 lectures dans la table, une par mouvement trouvé) que seule la variante couvrante supprimerait.

Non mesuré : le coût de l'index sur les écritures (`CreateBatch`, `AddMovement`). Les temps de l'exécution « après » ne sont pas comparés à ceux d'avant (compilation et plan affiché inclus).

Décision (provisoire) : l'index est gardé. À comparer ensuite avec la variante couvrante, avant toute autre conclusion.

| Index | Recherche | Lectures avant | Lectures après | Plan après | Taille | Hypothèse confirmée ? | Décision |
|---|---|---|---|---|---|---|---|
| `IX_Movement_BatchId` | R2 | 25 412 | 15 | *Seek* + *Key Lookup*, sans tri | 56,72 Mo | oui, avec la nuance sur « unités » | gardé, variante couvrante à comparer |

#### Variante couvrante de l'index 1 (comparaison, 2026-10-19)

Pour décider entre un index simple et un index « couvrant » (qui contient aussi les colonnes demandées), la variante couvrante a été créée à côté de l'index simple, dans une fenêtre SSMS jetable, non sauvegardée :

```sql
CREATE NONCLUSTERED INDEX IX_Movement_BatchId_Covering
    ON trace.Movement (BatchId)
    INCLUDE (MovementType, StationId, QuantityKg, OccurredAt);
```

Avec les deux index présents, le bloc R2 de `009` a été relancé. L'infobulle de l'opérateur « Recherche d'index » du plan donne comme objet `[Movement].[IX_Movement_BatchId_Covering]` : SQL Server a utilisé la variante couvrante, et le *Key Lookup* a disparu.

| | Index simple | Variante couvrante |
|---|---|---|
| `Movement`, lectures logiques (R2) | 15 | 3 |
| *Key Lookup* dans le plan | oui (52 % du coût) | non |
| Taille | 56,72 Mo (7 260 pages) | 184,88 Mo (23 664 pages) |
| Taille de la clé primaire de `Movement`, pour comparaison | 194,92 Mo | 194,92 Mo |

Écart : 12 lectures de moins avec la variante couvrante, pour 128,16 Mo de plus (3,3 fois la taille de l'index simple).

Décision : on garde l'index simple et on abandonne la variante couvrante. Elle a été supprimée avec `DROP INDEX IX_Movement_BatchId_Covering ON trace.Movement;` ; la liste des index restants sur `Movement` a été vérifiée : `IX_Movement_BatchId` et `PK_Movement`. Raisons et alternatives : [ADR 0004](adr/0004-index-simple-sur-mouvement-par-lot.md).

Non mesuré : le coût en écriture des deux variantes (`AddMovement`, `CreateBatch`). Le choix repose sur la taille et sur les lectures de R2 seulement.

#### Index 2 : `IX_Batch_Status` sur `Batch (Status)`, essai abandonné (2026-10-19)

Index simple, sans colonnes incluses. Il a été créé par une version locale de `database/010_create_indexes.sql`, qui n'a pas été commitée. Décision de départ, fixée avant la mesure : garder l'index si `RECEIVED` baisse nettement dans la procédure et que `SHIPPED` ne se dégrade pas de façon notable ; sinon le supprimer.

Mesure « après » avec le script `database/009_measure_searches.sql` (lectures logiques sur `Batch`) :

| Cas | Avant | Après |
|---|---|---|
| R4 `RECEIVED` | 9 351 | **9 351** |
| R4 `SHIPPED` | 4 | 4 |
| R3 `F001`, `F021` | 26 ; 189 | 26 ; 189 |
| R1 + R2 (`GetBatch`) | 3 ; 15 sur `Movement` | 3 ; 15 sur `Movement` |

Le plan de `RECEIVED` après l'index est identique à celui d'avant : *Scan* de la clé primaire de `Batch`, 50 lignes, puis 50 *Seek* sur `Farm`. Il n'utilise pas `IX_Batch_Status`, et le texte du plan ne contient pas de ligne « Index absent ».

Trois essais pour comprendre, dans une fenêtre SSMS jetable, avec `RECEIVED`, page 1 de 50 :

| Essai | Lectures sur `Batch` |
|---|---|
| `sp_recompile` sur `trace.ListBatches`, puis un premier appel avec `RECEIVED` | 9 351 |
| A : même recherche sans la condition `@Status IS NULL OR …`, écrite directement en `SELECT` | 9 351 |
| B : même recherche, avec `WITH (INDEX (IX_Batch_Status))` | **241** |

- L'hypothèse « SQL Server réutilise un vieux plan » est écartée (essai `sp_recompile`). Observé avant cet essai : 0 ms de compilation pour les appels `SHIPPED` et `RECEIVED`.
- L'hypothèse « la condition facultative empêche d'utiliser l'index » est écartée (essai A).
- L'index fonctionne : forcé, il ramène `RECEIVED` de 9 351 à 241 lectures (essai B). Mais SQL Server ne le choisit pas de lui-même.
- Explication probable, **non prouvée** (les estimations de lignes du plan n'ont pas été examinées) : SQL Server suppose les lots `RECEIVED` répartis au hasard dans la table et croit donc trouver 50 lots vite en lisant dans l'ordre, alors que dans nos données ils sont tous à la fin.

Hypothèse R4 de la section 3 (« l'index aide beaucoup `RECEIVED` ») : **non confirmée** dans la procédure telle qu'elle est écrite. Elle n'est vraie que si l'index est forcé.

Décision : l'index est abandonné, avec `DROP INDEX IX_Batch_Status ON trace.Batch;`. Index restants sur `Batch`, vérifiés : `PK_Batch` et `UQ_Batch_BatchCode`. La taille de `IX_Batch_Status` n'a pas été mesurée.

Non testé : forcer l'index dans la procédure (fragile, et cela modifierait une procédure du lot 2a) ; un index plus gros avec colonnes incluses sur `Status`.

#### Index 3 : `IX_Batch_FarmId` sur `Batch (FarmId)`, essai abandonné (2026-10-19)

Index simple, sans colonnes incluses, créé et supprimé dans une fenêtre SSMS jetable (non commité). Règle de décision fixée et acceptée avant la mesure : garder l'index si les pages lointaines baissent d'au moins un facteur 10 **et** que la page 1 reste sous environ 300 lectures ; sinon le supprimer.

Mesure par `trace.ListBatches`, 50 lots par page, après `sp_recompile` (lectures logiques sur `Batch`) :

| Cas | Avant | Après (procédure) | Index forcé |
|---|---|---|---|
| `F001` page 1 | 26 | 26 | non mesuré |
| `F001` page 20 | 422 | 422 | non mesuré |
| `F021` page 1 | 189 | 189 | 368 |
| `F021` page 20 | 3 765 | 3 765 | 5 034 |

Observé :
- Après la création de l'index, les quatre mesures sont identiques : SQL Server n'utilise pas l'index dans la procédure.
- Forcé (`WITH (INDEX (IX_Batch_FarmId))`, en `SELECT` direct, avec `OFFSET 0` puis `OFFSET 950`), l'index fait **pire** : 368 contre 189 pour la page 1, 5 034 contre 3 765 pour la page 20 de `F021`.
- Sans index, la page 20 de `F021` coûte environ 20 fois la page 1 (3 765 contre 189 lectures) : l'hypothèse « plus la page est lointaine, plus de pages sont lues » est confirmée.
- Les lectures sur `Farm` suivent 2 lectures par lot parcouru, sauts compris : 100 pour 50 lots (page 1), 2 000 pour 1 000 lots (page 20).

Explication probable, **non prouvée** (les plans des requêtes forcées n'ont pas été examinés) : pour chaque lot trouvé, SQL Server doit retourner lire la ligne dans la table, et ces allers-retours coûtent plus cher que de parcourir directement la table dans l'ordre de `BatchId`.

Hypothèse R3 de la section 3 (`Batch (FarmId)` donne quelques pages pour la page 1) : **non confirmée**, l'index n'est pas utilisé dans la procédure et, forcé, il fait pire.

Décision : l'index est abandonné, avec `DROP INDEX IX_Batch_FarmId ON trace.Batch;`. Index restants sur `Batch`, vérifiés : `PK_Batch` et `UQ_Batch_BatchCode`. Non testé : un index avec colonnes incluses sur `FarmId` (SQL Server en avait suggéré un dans le plan de R5, avec `BatchCode`, `Variety`, `HarvestDate`, `QuantityKg` et `Status`).

#### R6 : ce qui a été observé

R6 (un plan réutilisé pour des valeurs très différentes) n'a pas été testée comme prévue. Observations partielles :
- Après `sp_recompile` sur `trace.ListBatches`, un premier appel avec `RECEIVED` donne les mêmes 9 351 lectures qu'avant : la réutilisation d'un ancien plan n'explique pas le coût de `RECEIVED`.
- Les plans de `F001` et de `F021` n'ont pas été comparés : on ne sait pas s'ils ont la même forme. Les lectures de `F001` (26) et de `F021` (189) sont cohérentes avec le même parcours dans l'ordre.

Conclusion : R6 reste **non conclue**.

### 4.3 Le total de `ListBatches` (lot 3a), 2026-10-20

Conditions : script `database/009_measure_searches.sql` exécuté une seule fois dans SSMS sur `TraceabilityDev` (1 000 000 de lots, `IX_Movement_BatchId` présent), avec le plan d'exécution réel (Ctrl+M). Depuis le lot 3a, `ListBatches` renvoie deux tableaux (la page, puis `TotalCount` avec les mêmes filtres) : chaque appel affiche donc deux séries de lectures. Les lectures physiques sont nulles, sauf une lecture anticipée de 537 pages pour la ferme `F001` : les temps ci-dessous sont indicatifs. `009` n'a pas été modifié.

| Cas | Page : `Batch` | Page : `Farm` | Total : `Batch` | Temps de la page | Temps du total | Temps de l'appel |
|---|---|---|---|---|---|---|
| R3 : grande ferme `F001` | 26 | 100 | 10 574 | 174 ms | 203 ms | 391 ms |
| R3 : petite ferme `F021` | 189 | 100 | 10 574 | 189 ms | 164 ms | 354 ms |
| R4 : statut `SHIPPED` | 4 | 100 | 10 574 | 62 ms | 243 ms | 306 ms |
| R4 : statut `RECEIVED` | 9 351 | 100 | 10 574 | 521 ms | 222 ms | 744 ms |
| R5 : page 900 de 1 000, sans filtre | 9 351 | 1 800 000 | 10 574 | 1 659 ms | 276 ms | 1 936 ms |

Ce qui est observé :
- Les lectures de la **page** sont celles du lot 2b : 26, 189, 4 et 9 351 sur `Batch`, 100 sur `Farm`, et 1 800 000 sur `Farm` pour la page 900.
- Le **total** lit 10 574 pages de `Batch`, en 5 analyses, dans les 5 cas : le filtre (ferme ou statut) ne change pas le nombre de lectures.
- Par rapport à la page : pour `F021`, 10 574 lectures contre 289 (189 sur `Batch` et 100 sur `Farm`), soit environ 37 fois ; pour `RECEIVED`, environ 112 % de plus que les 9 451 lectures de la page ; pour la page 900, environ 0,6 % de plus que ses 1 809 351 lectures.

Ce qui n'est pas établi :
- Pourquoi le total lit 10 574 pages. La table `Batch` occupe environ 10 424 pages de 8 Ko (81,44 Mo, voir [verification.md](verification.md), section 7.2) : l'explication la plus simple est une lecture de toute la table, mais le plan du total n'a pas été examiné, donc ce n'est pas prouvé.
- Si le plan est parallèle : les 5 analyses ressemblent à celles de R2 avant l'index, et le temps UC dépasse parfois le temps écoulé, mais cela n'est pas vérifié.
- Pourquoi les temps de la page diffèrent de ceux de la section 4.1 (par exemple 189 ms pour `F021` contre environ 40 ms). Les lectures sont les mêmes ; le cache et la première exécution ne sont pas comparables d'une mesure à l'autre.

Décision : le total est gardé tel quel dans `ListBatches`, pour que les trois listes aient la même forme. Son optimisation (index, autre manière de compter) est prévue dans un lot à part, avec la méthode des sections 3 et 4 : hypothèses écrites avant, mesures avant et après.

## 5. Limites de ces mesures

- Données inventées, générées par des formules fixes : la répartition (statuts selon le numéro, fermes régulières) est plus régulière que dans une vraie exploitation.
- Une seule machine, un seul niveau de cache : les temps sont indicatifs, les lectures logiques sont la mesure de référence. La mesure « avant » est une première exécution.
- Plans non examinés : R3 `F001` et R4 `SHIPPED`, ainsi que ceux des requêtes forcées. R6 reste non conclue.
- Le résultat s'énonce « mesuré sur 1 million de lots inventés », pas « valable en production ».
- Les index ne sont mesurés que sur les recherches listées ci-dessus. Leur effet sur la vitesse des écritures (`CreateBatch`, `AddMovement`) n'est pas mesuré, sauf si une section ajoutée plus tard le dit.
- Le total de `ListBatches` (section 4.3) n'a été mesuré qu'une fois, sans hypothèse écrite avant, sans examiner son plan, et aucun index n'a été essayé pour lui.

## 6. Lot 5 : le total des listes et le bouton « Fin » (hypothèses, 2026-10-23)

Même règle qu'à la section 3 : les hypothèses ci-dessous sont écrites et enregistrées dans Git **avant** la moindre mesure du lot 5. Aucune n'est modifiée après coup : si une mesure la contredit, on l'écrit dans une section ultérieure. Toutes sont **non vérifiées** au moment de leur écriture. Les tailles sont des calculs approximatifs, comparés ensuite aux tailles mesurées.

### 6.1 Ce qui est observé avant les mesures (faits, pas hypothèses)

- **Le total de `ListBatches`** lit 10 574 pages de `Batch` en 5 analyses, quel que soit le filtre (section 4.3). Son plan n'a jamais été examiné et aucun index n'a été essayé pour lui. `PK_Batch` occupe environ 10 424 pages et `UQ_Batch_BatchCode` environ 7 489 (section 1).
- **La procédure** (`database/005_create_batch_procedures.sql`) : la page est lue avec `JOIN Farm`, `ORDER BY b.BatchId` et `OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS` ; le total est un `COUNT(*)` sur `Batch` avec les mêmes filtres, écrits `(@Status IS NULL OR b.Status = @Status)` et `(@FarmId IS NULL OR b.FarmId = @FarmId)`.
- **L'API** (`src/Traceability.Data/TraceabilityDb.cs`) : `ListBatchesAsync` appelle la procédure comme procédure stockée, avec `@Status` et `@FarmCode` en `NVARCHAR`, `@PageNumber` et `@PageSize` en `INT`, lit les lignes de la page puis le total dans la même commande, et ne fixe aucun `CommandTimeout` (30 s par défaut du pilote).
- **« Fin »** ([verification.md](verification.md), section 11 et 11.3) : l'interface affiche 15 lots par page ; sur 1 000 000 de lots, « Fin » est la page 66 667 (999 990 lots sautés). Par l'API : 8,88 s, 11,73 s, 9,72 s, 1,90 s et trois échecs (dépassement de délai SQL, dont un mesuré à 30,15 s). Dans SSMS, la durée de la procédure entière (page et total ensemble) est de 335 ms (page 1000), 662 ms (page 10 000), 1 274 ms (page 30 000) et 2 744 ms (page 66 667). Pendant une réussite de 9,72 s, la requête de l'API avait un plan parallèle à 4 fils et un temps de processeur environ 14 fois supérieur à celui mesuré dans SSMS pour la même page. La cause n'est pas trouvée.
- **R5** (section 4.1) : le plan d'une page lointaine (page 900 de 1 000 lignes) trie 900 048 lignes avec débordement dans `tempdb` et lit 1 800 000 pages de `Farm`. La cause de ce chiffre n'a jamais été établie.

### 6.2 Méthode

- Mesure de référence : lectures logiques (`SET STATISTICS IO ON`) et plan d'exécution réel (Ctrl+M), comme à la section 2. Les temps restent indicatifs.
- **Mesures répétées** : 5 exécutions par cas, toutes les valeurs sont notées (pas seulement une moyenne), parce que l'incident à expliquer est irrégulier (de 1,90 s à plus de 30 s).
- Mesures dans SSMS, sur `TraceabilityDev`, en lecture seule. Un index d'essai est créé dans une fenêtre SSMS jetable, non enregistrée, puis supprimé (comme pour les index 2 et 3). Avant une série dont on veut un plan neuf : `EXEC sp_recompile 'trace.ListBatches';`.
- Le plan réellement utilisé par l'API est lu dans le cache de plans de SQL Server, après un appel de l'API, par une requête en lecture seule. Une lecture de `sys.dm_exec_procedure_stats` avait renvoyé 0 ligne au lot 4a ([verification.md](verification.md), section 11.3) : cette lecture peut échouer.

### 6.3 Hypothèses

**T1. Le plan du total sans filtre.**
- Hypothèse : le total lit toute la clé primaire `PK_Batch` (analyse parallèle), soit environ 10 424 pages (10 574 observées ; l'écart de 150 pages n'est pas expliqué), même si `UQ_Batch_BatchCode` est plus petit (environ 7 489 pages).
- Vérification : plan réel de la seconde requête de `EXEC trace.ListBatches` sans filtre.
- Fausse si : le plan lit un autre index, ou n'est pas un parcours complet.

**T2. Un index pour le total filtré.**
- Hypothèse : un index simple sur `Batch (FarmId)` ou sur `Batch (Status)` ramène le total filtré de 10 574 lectures à quelques dizaines ou centaines, parce qu'un `COUNT(*)` n'a pas besoin de lire la table (contrairement à la page, où chaque ligne trouvée oblige à retourner dans la table : section 4.2, index 2 et 3).
- Calcul approximatif : environ 15 à 17 octets par ligne d'index sur `FarmId` (environ 476 lignes par page, environ 2 100 pages en tout) donne environ 53 pages pour `F001` (25 000 lots) et environ 6 pages pour `F021` (2 777 lots). Environ 31 octets par ligne d'index sur `Status` (environ 260 lignes par page) donne environ 385 pages pour les 100 000 lots `RECEIVED`.
- Vérification : créer l'index d'essai, puis mesurer le total filtré par `EXEC` de la procédure, après `sp_recompile`, dans les mêmes conditions que la mesure « avant ».
- Fausse si : SQL Server n'utilise pas l'index sans qu'on le force (comme `IX_Batch_Status` pour la page, section 4.2), ou si le total filtré reste au-dessus de 1 000 lectures. Si l'index n'est pas utilisé, un point à examiner : la condition `(@FarmId IS NULL OR …)` peut empêcher l'accès direct par l'index ; l'essai A de la section 4.2 l'avait écarté pour la page, pas pour le total.
- Non prédit : le total sans filtre avec ces index (cela dépend de T1).

**F1. Le plan gardé en mémoire pour l'API dépend du premier appel.**
- Hypothèse : SQL Server construit le plan avec les valeurs du premier appel, ici le nombre de lignes sautées par `OFFSET`, puis le réutilise. Un plan construit pour une page proche du début (peu de lignes sautées) est mauvais pour la dernière page. C'est le mécanisme de R6 (section 3, resté non conclu), appliqué à `@PageNumber` au lieu de `@Status` et `@FarmId`.
- Vérification, par l'API (`GET /batches?pageNumber=…&pageSize=15`, sans filtre) : 3 essais de « Fin » (page 66 667) par série, avec `EXEC sp_recompile 'trace.ListBatches';` avant chaque série. Série A : le premier appel après `sp_recompile` est la page 66 667. Série B : le premier appel après `sp_recompile` est la page 1.
- Prévision : série A, les 3 essais durent 4 s ou moins (environ 1,5 fois les 2,7 s de SSMS) ; série B, au moins un des 3 essais dure plus de 8 s (un échec par dépassement de délai compte comme plus de 8 s).
- Fausse si : la série A a un essai de plus de 4 s, ou si la série B a ses 3 essais à 4 s ou moins.

**F2. Le plan de la dernière page.**
- Hypothèse : dans SSMS, avec les réglages par défaut, le plan de la page 66 667 (15 lignes par page) a la forme de R5 : tri d'environ 1 000 000 de lignes avec débordement dans `tempdb`, et environ 2 000 000 de lectures sur `Farm` (2 par ligne traitée, comme les 1 800 000 lectures de R5 pour 900 048 lignes).
- Vérification : plan réel et `STATISTICS IO` de `EXEC trace.ListBatches @PageNumber = 66667, @PageSize = 15`, 5 exécutions.
- Fausse si : le plan est une lecture ordonnée qui s'arrête à la fin de la page, ou si les lectures sur `Farm` sont très inférieures à 2 000 000.

### 6.4 Règle de décision pour un index (fixée avant la mesure)

Un index d'essai est gardé seulement si les trois conditions sont réunies : SQL Server l'utilise sans qu'on le force ; le total filtré visé passe sous 1 000 lectures ; sa taille est mesurée et notée. Sinon il est supprimé (`DROP INDEX`) et l'essai est noté comme abandonné. Le coût en écriture n'est pas mesuré (section 5).

### 6.5 Hors de ces hypothèses

- Pas d'hypothèse sur une réécriture du total ni sur un autre type de pagination : à décider après l'examen des plans, et seulement avec accord, car cela changerait une procédure ou le contrat de l'API.
- L'API et l'interface ne sont pas modifiées par ce lot à ce stade.
- La lenteur propre à `OFFSET` n'est pas supposée corrigeable par un index (section 3, R5).

## 7. Lot 5 : mesures « avant » (2026-10-23)

Conditions : script `database/013_measure_lot5.sql` exécuté dans SSMS sur `TraceabilityDev` (1 000 000 de lots), pages de 15 lignes, appels par `EXEC trace.ListBatches` (page et total ensemble). Partie A : une exécution par cas, avec le plan d'exécution réel. Partie B : 5 exécutions de suite, sans plan, avec la durée de chaque exécution. Les lectures logiques sont la mesure de référence ; les temps sont indicatifs. Pendant les mesures, VS Code, Edge, Chrome et le Bloc-notes étaient ouverts ; ils n'ont ni été fermés ni examinés. Les sections 1 à 6 ne sont pas modifiées.

### 7.1 Partie A : un appel par cas

| Cas | Page : `Batch` | Page : `Farm` | Total : `Batch` | Temps : page, total, appel entier |
|---|---|---|---|---|
| A1 : sans filtre, page 1 | 3 | 30 | 10 574 (5 analyses) | 473 ms, 2 048 ms, 2 565 ms |
| A2a : ferme `F001`, page 1 | 9 | 30 | 10 574 (5 analyses) | 301 ms, 296 ms, 628 ms |
| A2b : ferme `F021`, page 1 | 58 | 30 | 10 574 (5 analyses) | 322 ms, 301 ms, 661 ms |
| A2c : statut `RECEIVED`, page 1 | 9 351 | 30 | 10 574 (5 analyses) | 614 ms, 365 ms, 1 010 ms |
| A3 : sans filtre, page 66 667 | 10 574 (5 analyses) | 2 | 10 574 (5 analyses) | 17 332 ms, 452 ms, 17 810 ms |

Remarques sur ce tableau :
- A1 a été exécuté à froid : le total a lu 761 pages sur disque et 10 448 en lecture anticipée. Les autres cas ont lu peu ou pas de pages sur disque pour le total, ce qui explique en partie le temps de 2 048 ms de A1.
- A3 : temps de processeur de 3 842 ms pour la page (17 332 ms écoulées), 141 ms pour le total (452 ms) et 3 998 ms pour l'appel entier (17 810 ms). Le plan d'exécution était actif.
- A3 a aussi lu 10 539 pages de zone de travail (`Worktable`, en lecture anticipée).

### 7.2 Plans observés

- **Total, dans les quatre cas** : *Scan* parallèle de `PK_Batch` (4 fils), puis agrégations et regroupement des flux. Lignes retournées par l'analyse : 1 000 000 sans filtre (A1), 25 000 pour `F001` (A2a), 2 778 pour `F021` (A2b), 100 000 pour `RECEIVED` (A2c). SQL Server estime 331 677 lignes pour `F001` et pour `F021` : la même estimation pour deux fermes de tailles différentes.
- **Page 1 et pages proches du début (A1, A2)** : lecture de `PK_Batch` dans l'ordre, arrêt à 15 lignes, puis une recherche dans `Farm` par ligne (2 lectures par ligne, 30 pour 15 lignes). Pour `RECEIVED`, la lecture de `Batch` passe devant environ 900 000 lots avant d'en trouver 15 (9 351 lectures).
- **Dernière page (A3)** : plan parallèle. Lecture de `PK_Batch` (1 000 000 de lignes), lecture de `Farm` par `UQ_Farm_Code` (200 lignes), jointure interne (nom de l'opérateur tronqué à l'écran), **tri de 1 000 000 de lignes par `BatchId`**, regroupement des flux, puis 10 lignes. Estimation de SQL Server pour le tri : 331 677 lignes (réel : 1 000 000). Avertissement lu dans l'infobulle de l'opérateur de tri : le tri a utilisé `tempdb` pour déverser les données (niveau de déversement 1, 4 fils) ; il a écrit 10 530 pages dans `tempdb` et en a relu 10 530, avec 89 632 Ko de mémoire allouée et 75 624 Ko utilisés. Index absent proposé par SQL Server : `Batch (FarmId)` avec `BatchCode`, `Variety`, `HarvestDate`, `QuantityKg` et `Status` en colonnes incluses, impact annoncé 40,146 (le même que celui du cas R5, section 4.1).

### 7.3 Partie B : 5 exécutions de suite

Dernière page (B1), temps écoulé de l'appel entier : 10 380 ms, 20 005 ms, 7 928 ms, 121 832 ms et 146 313 ms (306 458 ms en tout). À chaque exécution : `Batch` 10 574 lectures logiques pour la page et 10 574 pour le total, `Farm` 2, zone de travail d'environ 10 530 pages (de 10 530 à 10 536). Les lectures logiques sont identiques d'une exécution à l'autre ; la durée varie dans un rapport d'environ 18.

Première page (B2), temps écoulé de l'appel entier : 218 ms, 120 ms, 262 ms, 200 ms et 248 ms. À chaque exécution : page `Batch` 3 et `Farm` 30, total 10 574 lectures logiques. Le total a lu sur disque, à chaque exécution, un nombre de pages non nul : 351, 94, 406, 614 et 470.

### 7.4 Écart avec les hypothèses de la section 6

| Hypothèse | Résultat |
|---|---|
| T1 | **conforme** : *Scan* parallèle de `PK_Batch`, 10 574 lectures dans les quatre cas, et `UQ_Batch_BatchCode`, plus petit, n'est pas utilisé. L'écart de 150 pages avec les 10 424 pages de la table reste non expliqué |
| T2 | mesure « avant » faite : 10 574 lectures pour `F001`, `F021` et `RECEIVED`, contre environ 53, 6 et 385 attendues avec un index. L'essai d'index n'est pas fait |
| F1 | non testée |
| F2 | **en partie conforme** : le tri d'environ 1 000 000 de lignes et le déversement dans `tempdb` sont observés. **Contredite** pour les lectures sur `Farm` : 2, et non environ 2 000 000. Le plan observé lit `Farm` une seule fois (200 lignes), ce n'est pas celui de R5 (1 800 000 lectures sur `Farm`) |

### 7.5 Observations non expliquées

- La même page (66 667) a duré de 7 928 ms à 146 313 ms en B1, avec des lectures logiques identiques. Les 2,2 à 2,7 s notées pour SSMS dans [verification.md](verification.md), section 11.3 (avec 0,9 s de processeur), ne sont pas retrouvées : le plan de ces essais n'est pas noté, et la différence n'est pas expliquée.
- En A3, le temps écoulé (17 332 ms) est très supérieur au temps de processeur (3 842 ms) : l'exécution a passé du temps à attendre. Ce que l'exécution attendait n'a pas été examiné.
- En B2, le total lit des pages sur disque à chaque exécution, alors que les mêmes pages viennent d'être lues. Non examiné.
- La partie A a été faite avec le plan réel actif, la partie B sans : les durées de A3 (17 332 ms) et de B1 ne sont pas strictement comparables.

### 7.6 Ce qui n'est pas encore fait

Le test de l'ordre des appels (F1), la lecture du plan réellement utilisé par l'API (partie C du script), l'essai d'un index pour le total (T2), la décision, et le coût en écriture d'un index (section 5).

## 8. Lot 5 : la dernière page sans parallélisme (hypothèse G1, 2026-10-23)

Cette hypothèse est écrite **après** les mesures « avant » de la section 7. Elle vient de ces mesures et ne fait pas partie des hypothèses de la section 6, écrites avant toute mesure du lot. Elle est enregistrée dans Git avant le test qu'elle prévoit et n'est pas modifiée après coup : le résultat s'ajoute dans cette même section, sous 8.4.

### 8.1 Ce qui la motive (faits, section 7)

- La page demandée est triée par `BatchId`, qui est l'ordre de `PK_Batch` (section 1 : la table elle-même, triée par `BatchId`).
- Pour la page 66 667, le plan observé (A3) est parallèle (4 fils) : lecture de `PK_Batch` en parallèle, puis tri de 1 000 000 de lignes par `BatchId`, avec déversement de 10 530 pages dans `tempdb` (section 7.2).
- La même page a duré de 7 928 ms à 146 313 ms en B1, avec les mêmes lectures logiques (section 7.3). Les 2,2 à 2,7 s notées pour SSMS dans [verification.md](verification.md), section 11.3, venaient d'un plan non noté (section 7.5).
- Raisonnement, non vérifié : une lecture parallèle ne livre pas les lignes dans l'ordre de la clé, ce qui obligerait à trier. Un plan sans parallélisme pourrait lire `PK_Batch` dans l'ordre et se passer du tri.

### 8.2 Hypothèse G1

- **Hypothèse :** avec `OPTION (MAXDOP 1)`, le plan de la page 66 667 n'a plus d'opérateur de tri, donc plus de déversement dans `tempdb`. Sur 5 exécutions, chacune dure 4 s ou moins et la plus lente dure au plus 2 fois la plus rapide.
- **D'où viennent les chiffres :** 4 s est environ 1,5 fois les 2,7 s notées dans `verification.md`, section 11.3. Le rapport de 2 est volontairement serré par rapport aux 18 observés en B1.
- **Lectures de `Batch` pour la page :** environ 10 400 à 10 600, comme en A3, parce que sauter 999 990 lignes oblige à lire presque toute la table. Le gain attendu est dans le tri et la durée, pas dans les lectures.
- **Non prédit :** les lectures sur `Farm`. Le plan de A3 en fait 2 ; un plan sans tri pourrait en faire beaucoup plus (le cas R5, section 4.1, en avait 1 800 000).
- **Fausse si :** une des 5 exécutions de la variante sans parallélisme dépasse 4 s, ou si le plan garde un tri qui déverse dans `tempdb`, ou si la plus lente dure plus de 2 fois la plus rapide.

### 8.3 Méthode

- Script `database/014_measure_lot5_trials.sql`, en lecture seule. La procédure et l'API ne sont pas modifiées : la requête de la page de `ListBatches` est rejouée par `sys.sp_executesql`, avec le même texte, les mêmes types de paramètres et `@FarmId` en variable locale, comme dans la procédure. Seule l'option `OPTION (MAXDOP 1)` distingue les deux variantes.
- **Contrôle d'abord :** la variante par défaut doit montrer le plan de A3 (parallèle, tri qui déverse dans `tempdb`). Sinon le test ne dit rien sur la procédure.
- Bloc G1a : le plan réel de chaque variante (une exécution chacune, Ctrl+M actif).
- Bloc G1b : 5 paires d'exécutions, sans plan, les deux variantes alternées, pour les comparer dans la même période, puisque la durée de la même page varie dans le temps (section 7.3).

### 8.4 Résultat (2026-10-23)

Conditions : script `database/014_measure_lot5_trials.sql` exécuté dans SSMS sur `TraceabilityDev`. Bloc G1a avec le plan réel actif, une exécution de chaque variante. Bloc G1b sans plan (Ctrl+M désactivé selon la consigne), 5 paires d'exécutions alternées. Aucune autre requête n'a été lancée pendant les mesures (indication de la personne qui les a faites).

**G1a : un appel de chaque variante, page 66 667**

| | Variante par défaut (contrôle) | `OPTION (MAXDOP 1)` |
|---|---|---|
| `Batch` : lectures logiques | 10 574 (5 analyses) | 10 424 (1 analyse) |
| `Farm` : lectures logiques | 2 | 2 |
| Zone de travail (`Worktable`, lecture anticipée) | 10 538 | 10 496 |
| Temps de processeur / temps écoulé | 3 906 ms / 120 414 ms | 796 ms / 2 232 ms |
| Plan | parallèle, tri de 1 000 000 de lignes (estimé : 331 677), avertissement sur le tri ; durée de l'opérateur de tête 8,372 s, du tri 1,227 s | aucun opérateur de parallélisme, tri de 1 000 000 de lignes (estimé : 331 677) ; durée de l'opérateur de tête 1,843 s, du tri 1,805 s |
| Index absent proposé | `Batch (FarmId)` avec colonnes incluses, impact 40,146 | même forme, impact 29,5993 |

Le contrôle a le plan de A3 (section 7.2) : le test porte donc bien sur la forme de plan de la procédure. Infobulle du tri de la variante `MAXDOP 1` : l'opérateur a utilisé `tempdb` pour déverser les données (niveau de déversement 1, 1 fil) ; le tri a écrit 10 496 pages dans `tempdb` et en a relu 10 496, avec 88 104 Ko de mémoire allouée et 88 104 Ko utilisés. L'infobulle du tri de la variante par défaut n'a pas été relue dans ce bloc (elle l'avait été pour A3, section 7.2).

**G1b : 5 paires, temps écoulé de l'exécution, en ms**

| Paire | Par défaut | `MAXDOP 1` |
|---|---|---|
| 1 | 8 972 | 1 556 |
| 2 | 7 967 | 1 397 |
| 3 | 8 708 | 1 474 |
| 4 | 7 716 | 1 625 |
| 5 | 8 827 | 1 591 |

À chaque exécution par défaut : `Batch` 10 574 lectures logiques (5 analyses), `Farm` 2, zone de travail de 10 530 à 10 532 pages. À chaque exécution `MAXDOP 1` : `Batch` 10 424 (1 analyse), `Farm` 2, zone de travail de 10 496 à 10 497 pages. Dans chaque paire, la variante par défaut est 4,7 à 5,9 fois plus lente que la variante `MAXDOP 1`.

**Verdict sur G1** (règles de la section 8.2)

| Critère | Résultat |
|---|---|
| Chaque durée de la variante `MAXDOP 1` à 4 s ou moins | **confirmé** : 1 397 à 1 625 ms en G1b, 2 232 ms en G1a |
| La plus lente au plus 2 fois la plus rapide | **confirmé** : 1 625 ms contre 1 397 ms |
| Lectures de `Batch` d'environ 10 400 à 10 600 | **confirmé** : 10 424 |
| Plus d'opérateur de tri, plus de déversement dans `tempdb` | **infirmé** : le tri est resté, avec 10 496 pages déversées |
| Lectures sur `Farm` (non prédites) | 2 |

La règle « fausse si le plan garde un tri qui déverse dans `tempdb` » est remplie : **G1 est fausse telle qu'elle a été énoncée**. Elle est conforme sur la durée et la régularité de la variante sans parallélisme.

**Observations non expliquées**

- Sans parallélisme, la même page est 4,7 à 5,9 fois plus rapide, alors que le tri qui déverse dans `tempdb` est resté : la cause n'est pas établie.
- Pour la variante par défaut, la durée affichée dans le plan et la durée mesurée diffèrent beaucoup : 8,372 s dans le plan contre 120,4 s mesurées en G1a, et 9,170 s contre 17,3 s en A3. Pour `MAXDOP 1`, 1,843 s contre 2,2 s. Ce que l'exécution fait pendant la différence n'a pas été examiné.
- L'irrégularité n'a pas été reproduite en G1b : les cinq exécutions par défaut ont duré de 7,7 s à 9,0 s, alors que B1 (runs 4 et 5) et G1a ont donné 121,8 s, 146,3 s et 120,4 s pour la même page. Cause inconnue.
- `Batch` est lu en 10 424 pages sans parallélisme (la taille de la table, section 1) et en 10 574 pages avec le plan parallèle : les 150 pages en plus coïncident avec le plan parallèle, sans que la cause soit examinée.

**Ce qui n'est pas fait.** Rien n'a été mesuré par l'API. La procédure et l'API ne sont pas modifiées, et aucune décision n'est prise : adopter `OPTION (MAXDOP 1)` reviendrait à modifier `ListBatches`, avec ses tests, et demanderait de comparer les alternatives. Prochain essai : le plan réellement utilisé par l'API (section 9.1).
