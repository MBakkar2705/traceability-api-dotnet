# Mesures de recherche et index (lot 2b)

Ce document garde la trace des **hypothèses** posées avant de mesurer, puis des **mesures** avant et après chaque index.

Règle de travail : les hypothèses (section 3) sont écrites et enregistrées dans Git **avant** la moindre mesure. L'historique Git montre cet ordre. Aucune hypothèse n'est modifiée après coup : si une mesure la contredit, on l'écrit dans la section 4, on ne réécrit pas la section 3.

Date des hypothèses : 2026-10-19.

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

À remplir au fil des mesures. Pour chaque recherche : avant, index ajouté, après, décision.

| Recherche | Avant : lectures logiques | Avant : plan | Index ajouté | Après : lectures logiques | Après : plan | Hypothèse confirmée ? | Décision |
|---|---|---|---|---|---|---|---|
| R1. Lot par code | à mesurer | à mesurer | — | — | — | — | — |
| R2. Parcours d'un lot | à mesurer | à mesurer | | | | | |
| R3. Lots d'une grande ferme | à mesurer | à mesurer | | | | | |
| R3. Lots d'une petite ferme | à mesurer | à mesurer | | | | | |
| R4. Statut `SHIPPED` | à mesurer | à mesurer | | | | | |
| R4. Statut `RECEIVED` | à mesurer | à mesurer | | | | | |
| R5. Page 900 de 1 000 | à mesurer | à mesurer | — | — | — | — | — |
| R6. Plan réutilisé | à observer | à observer | — | — | — | — | — |

## 5. Limites de ces mesures

- Données inventées, générées par des formules fixes : la répartition (statuts selon le numéro, fermes régulières) est plus régulière que dans une vraie exploitation.
- Une seule machine, un seul niveau de cache : les temps sont indicatifs, les lectures logiques sont la mesure de référence.
- Le résultat s'énonce « mesuré sur 1 million de lots inventés », pas « valable en production ».
- Les index ne sont mesurés que sur les recherches listées ci-dessus. Leur effet sur la vitesse des écritures (`CreateBatch`, `AddMovement`) n'est pas mesuré, sauf si une section ajoutée plus tard le dit.
