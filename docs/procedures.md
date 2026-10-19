# Procédures stockées

Ce document décrit ce que les 7 procédures du schéma `trace` doivent faire : leurs paramètres, leurs contrôles et leurs erreurs. C'est le contrat sur lequel s'appuieront les scripts, les tests et, plus tard, l'API.

Les règles métier sont dans [fonctionnel.md](fonctionnel.md), le modèle dans [modele-de-donnees.md](modele-de-donnees.md). L'avancement est dans le [README](../README.md) ; les preuves observées sont dans [verification.md](verification.md).

## 1. Conventions

- **Codes lisibles en paramètres** : les procédures reçoivent des codes (`LOT-2026-0001`, `F01`, `SITE-01`) et retrouvent elles-mêmes les numéros techniques. Les codes se comparent sans tenir compte de la casse (classement `French_CI_AS`).
- **Types de mouvement** : acceptés en majuscules ou en minuscules, toujours enregistrés en majuscules (`reception` est enregistré `RECEPTION`).
- **Heures en UTC**, fournies par l'appelant. Elles ne sont pas contrôlées (voir section 5).
- **Erreurs** : `THROW`, avec un numéro par règle, un message en anglais et l'état 1. Les tests vérifient le numéro, jamais le texte du message. Les numéros sont rangés par famille (section 4).
- **Transactions** : chaque procédure d'écriture annule tout en cas d'erreur (`SET XACT_ABORT ON`). `AddMovement` pose un verrou sur la ligne du lot (voir [ADR 0003](adr/0003-verrou-sur-le-lot.md)).
- **Dernier filet** : les procédures contrôlent les cas courants et lèvent leur propre erreur numérotée. Les contraintes du lot 1 (clés, `UNIQUE`, `CHECK`) restent derrière elles.
- **Valeur `NULL`** : un code `NULL` compte comme un code vide (50400), une quantité `NULL` comme une quantité invalide (50401). Les autres paramètres obligatoires à `NULL` ne sont pas contrôlés par les procédures : ils sont refusés par les contraintes `NOT NULL` du lot 1, avec l'erreur SQL Server habituelle.
- **Appels par nom de paramètre** (`@BatchCode = ...`).

## 2. Les 7 procédures

| Procédure | Rôle |
|---|---|
| `trace.CreateFarm` | Crée une ferme. |
| `trace.CreateStation` | Crée une station. |
| `trace.AddStationCapability` | Déclare une fonction pour une station. |
| `trace.CreateBatch` | Crée un lot et son premier mouvement `RECEPTION`. |
| `trace.AddMovement` | Ajoute le mouvement suivant d'un lot et met le lot à jour. |
| `trace.GetBatch` | Donne un lot avec son parcours. |
| `trace.ListBatches` | Liste les lots, par statut et/ou par ferme, une page à la fois. |

Pas de procédure pour lister les fermes et les stations : elles viendront avec l'API (lot 3), si elle en a besoin.

### 2.1 `trace.CreateFarm`

Paramètres : `@Code NVARCHAR(20)`, `@Name NVARCHAR(100)`, `@Region NVARCHAR(100)`.

Contrôles, dans cet ordre :

1. code non vide : sinon 50400 ;
2. code pas déjà pris : sinon 50200.

Résultat : la ligne de la ferme créée (`FarmId`, `Code`, `Name`, `Region`). `Name` et `Region` peuvent être vides (choix du lot 1).

### 2.2 `trace.CreateStation`

Paramètres : `@Code NVARCHAR(20)`, `@Name NVARCHAR(100)`.

Contrôles, dans cet ordre :

1. code non vide : sinon 50400 ;
2. code pas déjà pris : sinon 50201.

Résultat : la ligne de la station créée (`StationId`, `Code`, `Name`).

### 2.3 `trace.AddStationCapability`

Paramètres : `@StationCode NVARCHAR(20)`, `@MovementType NVARCHAR(20)`.

Contrôles, dans cet ordre :

1. type de mouvement connu (`RECEPTION`, `SORTING`, `PACKING`, `SHIPMENT`) : sinon 50402 ;
2. station existante : sinon 50102 ;
3. fonction pas déjà déclarée pour cette station : sinon 50203.

Résultat : aucun.

### 2.4 `trace.CreateBatch`

Crée le lot (statut `RECEIVED`) et son premier mouvement `RECEPTION`, dans une seule transaction.

Paramètres : `@BatchCode NVARCHAR(30)`, `@FarmCode NVARCHAR(20)`, `@Variety NVARCHAR(50)`, `@HarvestDate DATE`, `@QuantityKg DECIMAL(10,2)`, `@StationCode NVARCHAR(20)`, `@OccurredAt DATETIME2`.

Contrôles, dans cet ordre :

1. code du lot non vide : sinon 50400 ;
2. quantité supérieure à 0 : sinon 50401 ;
3. ferme existante : sinon 50101 ;
4. station existante : sinon 50102 ;
5. code du lot pas déjà pris : sinon 50202 ;
6. la station a la fonction `RECEPTION` : sinon 50303.

Résultat : aucun. Si un contrôle échoue, aucun lot et aucun mouvement ne sont créés.

### 2.5 `trace.AddMovement`

Ajoute le mouvement suivant d'un lot et met à jour le lot (statut et quantité) dans la même transaction, sous le verrou de l'[ADR 0003](adr/0003-verrou-sur-le-lot.md).

Paramètres : `@BatchCode NVARCHAR(30)`, `@StationCode NVARCHAR(20)`, `@MovementType NVARCHAR(20)`, `@QuantityKg DECIMAL(10,2)`, `@OccurredAt DATETIME2`.

L'étape suivante dépend du statut du lot :

| Statut du lot | Mouvement attendu | Statut après |
|---|---|---|
| `RECEIVED` | `SORTING` | `SORTED` |
| `SORTED` | `PACKING` | `PACKED` |
| `PACKED` | `SHIPMENT` | `SHIPPED` |
| `SHIPPED` | aucun | |

Contrôles, dans cet ordre (le premier qui échoue donne l'erreur) :

1. quantité supérieure à 0 : sinon 50401 ;
2. type de mouvement connu : sinon 50402 ;
3. lot existant (il est lu et verrouillé ici) : sinon 50100 ;
4. station existante : sinon 50102 ;
5. lot pas déjà `SHIPPED` : sinon 50300 ;
6. le type est bien l'étape suivante : sinon 50301 ;
7. la station a la fonction : sinon 50303 ;
8. la quantité ne dépasse pas la quantité actuelle du lot : sinon 50302. Une quantité égale est acceptée (comme dans l'exemple de [fonctionnel.md](fonctionnel.md)).

Résultat : aucun. Si un contrôle échoue, ni le journal ni le lot ne changent.

### 2.6 `trace.GetBatch`

Paramètre : `@BatchCode NVARCHAR(30)`.

Erreur : lot inexistant, 50100.

Résultat, en deux tableaux :

1. le lot : `BatchCode`, `FarmCode`, `Variety`, `HarvestDate`, `QuantityKg`, `Status` ;
2. son parcours dans l'ordre d'enregistrement (par `MovementId`) : `MovementId`, `MovementType`, `StationCode`, `QuantityKg`, `OccurredAt`.

### 2.7 `trace.ListBatches`

Paramètres : `@Status NVARCHAR(20) = NULL`, `@FarmCode NVARCHAR(20) = NULL`, `@PageNumber INT`, `@PageSize INT`.

Sans filtre (`NULL`), tous les lots sont listés. Les deux filtres se combinent.

Contrôles, dans cet ordre :

1. statut connu (s'il est donné) : sinon 50403 ;
2. ferme existante (si elle est donnée) : sinon 50101 ;
3. numéro de page à partir de 1 et taille de page de 1 à 1 000 : sinon 50404.

Résultat : une page de lots, triés par numéro de lot (`BatchId`), avec `BatchCode`, `FarmCode`, `Variety`, `HarvestDate`, `QuantityKg`, `Status`. Un seul tableau, sans le nombre total de lots.

## 3. Ce qui reste protégé par les contraintes

Les procédures s'ajoutent aux contraintes du lot 1, elles ne les remplacent pas. Par exemple, `FK_Movement_StationCapability` refuse toujours un mouvement dont la station n'a pas la fonction, même si une écriture directe contourne les procédures.

## 4. Les erreurs

Les numéros de 50000 à 50099 sont réservés aux gardes des scripts. Les scripts d'inspection (`003`, `900`) gardent `RAISERROR`, choix du lot 1. Gardes utilisées :

| N° | Sens | Script |
|---|---|---|
| 50001 | Mauvaise base de données | `002`, `007`, `008`, `009`, `010` |
| 50002 | `@TargetLots` hors de 1 à 1 000 000 | `007` |
| 50003 | Contenu inattendu : `007` refuse une base qui contient autre chose qu'un début de son jeu de données ; `008` refuse une base sans lot ; `009` exige le jeu complet de 1 000 000 de lots | `007`, `008`, `009` |
| 50004 | Fermes ou stations de référence différentes de celles attendues | `007` |
| 50005 | Espace disque libre sous la limite `@MinFreeGB` | `007` |
| 50006 | Procédures `GetBatch` ou `ListBatches` introuvables (lancer `004` et `005`) | `009` |

| N° | Famille | Sens | Message (anglais, exemple) | Levée par |
|---|---|---|---|---|
| 50100 | Introuvable | Lot | `Batch 'LOT-1' was not found.` | `AddMovement`, `GetBatch` |
| 50101 | Introuvable | Ferme | `Farm 'F99' was not found.` | `CreateBatch`, `ListBatches` |
| 50102 | Introuvable | Station | `Station 'X' was not found.` | `AddStationCapability`, `CreateBatch`, `AddMovement` |
| 50200 | Existe déjà | Code de ferme | `Farm code 'F01' already exists.` | `CreateFarm` |
| 50201 | Existe déjà | Code de station | `Station code 'SITE-01' already exists.` | `CreateStation` |
| 50202 | Existe déjà | Code de lot | `Batch code 'LOT-1' already exists.` | `CreateBatch` |
| 50203 | Existe déjà | Fonction déjà déclarée | `Station 'SITE-01' already has the function 'SORTING'.` | `AddStationCapability` |
| 50300 | Règle métier | Lot déjà expédié | `Batch 'LOT-1' is already SHIPPED: no new movement.` | `AddMovement` |
| 50301 | Règle métier | Étape sautée ou mauvaise | `Batch 'LOT-1' is RECEIVED: the next movement must be SORTING, not PACKING.` | `AddMovement` |
| 50302 | Règle métier | Quantité qui monte | `Quantity 520.00 is higher than the current quantity 500.00.` | `AddMovement` |
| 50303 | Règle métier | Station sans la fonction | `Station 'SITE-01' does not have the function 'PACKING'.` | `CreateBatch`, `AddMovement` |
| 50400 | Valeur invalide | Code vide | `The code must not be empty.` | `CreateFarm`, `CreateStation`, `CreateBatch` |
| 50401 | Valeur invalide | Quantité à 0 ou négative | `The quantity must be greater than 0.` | `CreateBatch`, `AddMovement` |
| 50402 | Valeur invalide | Type de mouvement inconnu | `Unknown movement type 'LOST'.` | `AddStationCapability`, `AddMovement` |
| 50403 | Valeur invalide | Statut inconnu | `Unknown status 'LOST'.` | `ListBatches` |
| 50404 | Valeur invalide | Page ou taille de page invalide | `Invalid page number or page size.` | `ListBatches` |

Les familles permettront à l'API de répondre sans connaître chaque règle : 501xx introuvable, 502xx existe déjà, 503xx règle métier violée, 504xx valeur invalide.

## 5. Limites connues

- **L'heure d'un mouvement n'est pas contrôlée** : un mouvement peut avoir une heure antérieure au précédent ou située dans le futur. Le parcours est donné dans l'ordre d'enregistrement. Le métier réel dira si une règle est nécessaire.
- **Les corrections ne sont pas gérées.** La règle 3 de [fonctionnel.md](fonctionnel.md) dit de corriger par un nouveau mouvement, mais l'ordre des statuts (50301) et la quantité qui ne monte pas (50302) refusent un mouvement de correction. Une faute de saisie ne peut donc pas être corrigée par les procédures. Question à poser au métier.
- **Deux créations simultanées avec le même code** (`CreateFarm`, `CreateStation`, `CreateBatch`) : le verrou de l'ADR 0003 ne peut pas aider (il n'y a pas encore de ligne). La contrainte d'unicité du lot 1 refuse la seconde, avec l'erreur SQL Server habituelle et non la 50200, la 50201 ou la 50202.
- **Le verrou ne protège que les appels passés par la procédure.** Une écriture directe dans les tables le contourne.
- **Pas de délai d'attente** sur le verrou : un appel attend aussi longtemps que l'autre n'a pas terminé.
- **`GetBatch` lit le lot puis son parcours en deux requêtes**, sans verrou : si un mouvement est ajouté entre les deux, le parcours peut contenir un mouvement que le lot ne reflète pas encore.
- **`AddMovement` appelée dans une transaction de l'appelant** : son `COMMIT` ne valide rien, le verrou et la modification restent jusqu'au `COMMIT` de l'appelant (observé pendant la preuve de l'ADR 0003). En cas d'erreur, la procédure exécute `ROLLBACK` : d'après le code, cela annule aussi le travail de l'appelant (non testé).
- **Pas de modification ni de suppression** de fermes et de stations.
- **`ListBatches`** ne donne pas le nombre total de lots.
- **`ListBatches` : les pages éloignées coûtent cher** (mesuré au lot 2b, sur 1 000 000 de lots inventés, détail dans [mesures.md](mesures.md)). Sans filtre, la page 900 de 1 000 lots lit 9 351 pages de `Batch`, trie 900 048 lignes (avec débordement dans `tempdb`) et lit 1 800 000 fois `Farm`, en 1,6 à 8 secondes selon l'exécution. Avec une ferme de 2 777 lots, la page 20 de 50 lots coûte 3 765 lectures, contre 189 pour la page 1. `RECEIVED`, dont les lots sont les derniers dans l'ordre de `BatchId` dans nos données, coûte 9 351 lectures dès la page 1. Aucun des index essayés (`Batch (Status)`, `Batch (FarmId)`) n'améliore ces cas sans modifier la procédure. Pistes non essayées : forcer un index dans la procédure, un index avec colonnes incluses, une pagination qui ne passe pas par `OFFSET`.
