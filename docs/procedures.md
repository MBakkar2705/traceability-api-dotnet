# Procédures stockées

Ce document décrit ce que les 12 procédures du schéma `trace` doivent faire : leurs paramètres, leurs contrôles et leurs erreurs. C'est le contrat sur lequel s'appuient les scripts, les tests et l'API.

Les règles métier sont dans [fonctionnel.md](fonctionnel.md), le modèle dans [modele-de-donnees.md](modele-de-donnees.md). L'avancement est dans le [README](../README.md) ; les preuves observées sont dans [verification.md](verification.md).

## 1. Conventions

- **Codes lisibles en paramètres** : les procédures reçoivent des codes (`LOT-2026-0001`, `F01`, `SITE-01`) et retrouvent elles-mêmes les numéros techniques. Les codes se comparent sans tenir compte de la casse (classement `French_CI_AS`).
- **Types de mouvement** : acceptés en majuscules ou en minuscules, toujours enregistrés en majuscules (`reception` est enregistré `RECEPTION`).
- **Heures en UTC**, fournies par l'appelant. Elles ne sont pas contrôlées (voir section 5).
- **Erreurs** : `THROW`, avec un numéro par règle, un message en anglais et l'état 1. Les tests vérifient le numéro, jamais le texte du message. Les numéros sont rangés par famille (section 4).
- **Transactions** : chaque procédure d'écriture annule tout en cas d'erreur (`SET XACT_ABORT ON`). `AddMovement` pose un verrou sur la ligne du lot (voir [ADR 0003](adr/0003-verrou-sur-le-lot.md)).
- **Dernier filet** : les procédures contrôlent les cas courants et lèvent leur propre erreur numérotée. Les contraintes du lot 1 (clés, `UNIQUE`, `CHECK`) restent derrière elles.
- **Valeur `NULL`** : un code `NULL` compte comme un code vide (50400), une quantité `NULL` comme une quantité invalide (50401). Les autres paramètres obligatoires à `NULL` ne sont pas contrôlés par les procédures : ils sont refusés par les contraintes `NOT NULL` du lot 1, avec l'erreur SQL Server habituelle.
- **Auteur du mouvement** (lot 11) : `CreateBatch` et `AddMovement` reçoivent `@AuthorId` et `@AuthorName`, lus par l'API dans le jeton validé. Ils sont contrôlés en premier : vides, `NULL` ou espaces seulement, 50405 ; trop longs (plus de 64 caractères pour l'identifiant, plus de 100 pour le nom), 50406. Les paramètres sont plus larges que les colonnes (200 caractères) pour qu'une valeur trop longue arrive jusqu'au contrôle au lieu d'être coupée en silence. Un appel qui ne donne pas ces deux paramètres échoue avec l'erreur SQL Server 201 (paramètre attendu) : l'échec est voulu et bruyant.
- **Corrections** (lot 12a) : `ReplaceMovement` et `CancelMovement` n'écrivent jamais dans `trace.Movement` : elles ajoutent une ligne à `trace.MovementCorrection`. Elles reçoivent l'auteur comme `AddMovement` (mêmes contrôles 50405 et 50406) et prennent le même verrou sur le lot. Voir l'[ADR 0016](adr/0016-correction-des-mouvements.md).
- **Appels par nom de paramètre** (`@BatchCode = ...`).

## 2. Les 12 procédures

| Procédure | Rôle |
|---|---|
| `trace.CreateFarm` | Crée une ferme. |
| `trace.CreateStation` | Crée une station. |
| `trace.AddStationCapability` | Déclare une fonction pour une station. |
| `trace.CreateBatch` | Crée un lot et son premier mouvement `RECEPTION`. |
| `trace.AddMovement` | Ajoute le mouvement suivant d'un lot et met le lot à jour. |
| `trace.GetBatch` | Donne un lot avec son parcours et l'historique de ses corrections. |
| `trace.ListBatches` | Liste les lots, par statut et/ou par ferme, une page à la fois, avec leur nombre total. |
| `trace.ListFarms` | Liste les fermes, une page à la fois, avec leur nombre total. |
| `trace.ListStations` | Liste les stations, une page à la fois, avec leur nombre total. |
| `trace.GetStation` | Donne une station avec ses fonctions. |
| `trace.ReplaceMovement` | Corrige un mouvement : lui donne une nouvelle station, une nouvelle quantité et une nouvelle heure (lot 12a). |
| `trace.CancelMovement` | Dit qu'un mouvement n'a pas eu lieu (lot 12a). |

Les trois dernières (`ListFarms`, `ListStations`, `GetStation`) ont été ajoutées au lot 3a (script `011`), pour que l'API puisse lister les fermes et les stations et lire une station avec ses fonctions.

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

Paramètres : `@BatchCode NVARCHAR(30)`, `@FarmCode NVARCHAR(20)`, `@Variety NVARCHAR(50)`, `@HarvestDate DATE`, `@QuantityKg DECIMAL(10,2)`, `@StationCode NVARCHAR(20)`, `@OccurredAt DATETIME2`, `@AuthorId NVARCHAR(200)`, `@AuthorName NVARCHAR(200)`. L'auteur est enregistré avec le premier mouvement.

Contrôles, dans cet ordre :

1. auteur donné (identifiant et nom non vides) : sinon 50405 ;
2. auteur assez court pour les colonnes : sinon 50406 ;
3. code du lot non vide : sinon 50400 ;
4. quantité supérieure à 0 : sinon 50401 ;
5. ferme existante : sinon 50101 ;
6. station existante : sinon 50102 ;
7. code du lot pas déjà pris : sinon 50202 ;
8. la station a la fonction `RECEPTION` : sinon 50303.

Résultat : aucun. Si un contrôle échoue, aucun lot et aucun mouvement ne sont créés.

### 2.5 `trace.AddMovement`

Ajoute le mouvement suivant d'un lot et met à jour le lot (statut et quantité) dans la même transaction, sous le verrou de l'[ADR 0003](adr/0003-verrou-sur-le-lot.md).

Paramètres : `@BatchCode NVARCHAR(30)`, `@StationCode NVARCHAR(20)`, `@MovementType NVARCHAR(20)`, `@QuantityKg DECIMAL(10,2)`, `@OccurredAt DATETIME2`, `@AuthorId NVARCHAR(200)`, `@AuthorName NVARCHAR(200)`.

L'étape suivante dépend du statut du lot :

| Statut du lot | Mouvement attendu | Statut après |
|---|---|---|
| `RECEIVED` | `SORTING` | `SORTED` |
| `SORTED` | `PACKING` | `PACKED` |
| `PACKED` | `SHIPMENT` | `SHIPPED` |
| `SHIPPED` | aucun | |

Contrôles, dans cet ordre (le premier qui échoue donne l'erreur) :

1. auteur donné (identifiant et nom non vides) : sinon 50405 ;
2. auteur assez court pour les colonnes : sinon 50406 ;
3. quantité supérieure à 0 : sinon 50401 ;
4. type de mouvement connu : sinon 50402 ;
5. lot existant (il est lu et verrouillé ici) : sinon 50100 ;
6. station existante : sinon 50102 ;
7. lot pas déjà `SHIPPED` : sinon 50300 ;
8. le type est bien l'étape suivante : sinon 50301 ;
9. la station a la fonction : sinon 50303 ;
10. la quantité ne dépasse pas la quantité actuelle du lot : sinon 50302. Une quantité égale est acceptée (comme dans l'exemple de [fonctionnel.md](fonctionnel.md)).

Résultat : aucun. Si un contrôle échoue, ni le journal ni le lot ne changent.

### 2.6 `trace.GetBatch`

Paramètre : `@BatchCode NVARCHAR(30)`.

Erreur : lot inexistant, 50100.

Résultat, en trois tableaux (le troisième depuis le lot 12a) :

1. le lot : `BatchCode`, `FarmCode`, `Variety`, `HarvestDate`, `QuantityKg`, `Status` ;
2. son parcours dans l'ordre d'enregistrement (par `MovementId`), mouvements annulés compris : `MovementId`, `MovementType`, `StationCode`, `QuantityKg`, `OccurredAt`, `AuthorName`, puis `IsCancelled`, `CorrectionCount` et les valeurs d'origine (`OriginalStationCode`, `OriginalQuantityKg`, `OriginalOccurredAt`). `StationCode`, `QuantityKg` et `OccurredAt` sont les valeurs **valables** (la dernière correction appliquée) ; les colonnes `Original…` sont les valeurs saisies. Le nom de l'auteur est celui de la saisie ; son identifiant n'est jamais renvoyé ;
3. les corrections des mouvements du lot, dans l'ordre où elles ont été faites (par `CorrectionId`) : `CorrectionId`, `MovementId`, `Kind`, `MovementType`, `StationCode`, `QuantityKg`, `OccurredAt`, `ReasonCode`, `ReasonComment`, `AuthorName`, `CorrectedAt`. Ce tableau est vide si rien n'a été corrigé.

### 2.7 `trace.ListBatches`

Paramètres : `@Status NVARCHAR(20) = NULL`, `@FarmCode NVARCHAR(20) = NULL`, `@PageNumber INT`, `@PageSize INT`.

Sans filtre (`NULL`), tous les lots sont listés. Les deux filtres se combinent. Depuis le lot 5, la procédure de `005` est remplacée par celle de `017` (même contrat ; la page est découpée avant la jointure et le total est refait à chaque appel : voir l'[ADR 0008](adr/0008-listbatches-page-avant-jointure-total-recompile.md)).

Contrôles, dans cet ordre :

1. statut connu (s'il est donné) : sinon 50403 ;
2. ferme existante (si elle est donnée) : sinon 50101 ;
3. numéro de page à partir de 1 et taille de page de 1 à 1 000 : sinon 50404.

Résultat, en deux tableaux :

1. une page de lots, triés par numéro de lot (`BatchId`) : `BatchCode`, `FarmCode`, `Variety`, `HarvestDate`, `QuantityKg`, `Status` ;
2. le nombre total de lots qui correspondent aux filtres : une ligne, une colonne, `TotalCount`.

Le total est lu par une requête séparée de la page, sans verrou, avec les mêmes filtres (statut et ferme). Il a été ajouté au lot 3a, pour que les trois listes aient la même forme.

### 2.8 `trace.ListFarms`

Paramètres : `@PageNumber INT`, `@PageSize INT`.

Contrôle : numéro de page à partir de 1 et taille de page de 1 à 1 000 (un paramètre `NULL` est invalide) : sinon 50404.

Résultat, en deux tableaux :

1. une page de fermes, par ordre de création (`FarmId`) : `Code`, `Name`, `Region` ;
2. le nombre total de fermes : une ligne, une colonne, `TotalCount`.

Une page au-delà de la fin donne un premier tableau vide ; le total ne change pas. Le total est lu par une requête séparée de la page, sans verrou (voir section 5).

### 2.9 `trace.ListStations`

Paramètres : `@PageNumber INT`, `@PageSize INT`.

Contrôle : le même que `ListFarms` (50404).

Résultat, en deux tableaux :

1. une page de stations, par ordre de création (`StationId`) : `Code`, `Name` ;
2. le nombre total de stations : une ligne, une colonne, `TotalCount`.

### 2.10 `trace.GetStation`

Paramètre : `@StationCode NVARCHAR(20)`.

Erreur : station inexistante, 50102. Un code `NULL` ne trouve aucune station : même erreur.

Résultat, en deux tableaux :

1. la station : `Code`, `Name` ;
2. ses fonctions : `MovementType`, dans l'ordre du cycle de vie (`RECEPTION`, `SORTING`, `PACKING`, `SHIPMENT`). Ce tableau est vide si la station n'a encore aucune fonction.

### 2.11 `trace.ReplaceMovement`

Corrige un mouvement : lui donne une nouvelle station, une nouvelle quantité et une nouvelle heure. Le type du mouvement ne change pas. `trace.Movement` n'est pas modifié : une ligne `REPLACE` est ajoutée à `trace.MovementCorrection`, sous le verrou de l'[ADR 0003](adr/0003-verrou-sur-le-lot.md). Tout mouvement qui n'est pas annulé peut être corrigé, y compris dans un lot `SHIPPED`. Si c'est le dernier mouvement valable, la quantité du lot suit ; le statut du lot ne change jamais ici.

Paramètres : `@BatchCode NVARCHAR(30)`, `@MovementId BIGINT`, `@StationCode NVARCHAR(20)`, `@QuantityKg DECIMAL(10,2)`, `@OccurredAt DATETIME2`, `@ReasonCode NVARCHAR(50)`, `@ReasonComment NVARCHAR(2000)`, `@AuthorId NVARCHAR(200)`, `@AuthorName NVARCHAR(200)`.

Contrôles, dans cet ordre (le premier qui échoue donne l'erreur) :

1. auteur donné : sinon 50405 ; auteur assez court : sinon 50406 ;
2. quantité supérieure à 0 : sinon 50401 ;
3. motif connu (`DATA_ENTRY_ERROR`, `MEASUREMENT_ERROR`, `OTHER`) : sinon 50407 ;
4. commentaire d'au plus 500 caractères : sinon 50409 ; commentaire non vide pour `OTHER` : sinon 50408 ;
5. lot existant : sinon 50100 ; station existante : sinon 50102 ;
6. le mouvement appartient à ce lot : sinon 50103 ;
7. le mouvement n'est pas annulé : sinon 50305 ;
8. la station a la fonction du mouvement : sinon 50303 ;
9. la quantité est entre celle de l'étape valable précédente (maximum) et celle de l'étape valable suivante (minimum) : sinon 50304. L'égalité est acceptée. La réception n'a pas d'étape précédente, la dernière étape n'a pas d'étape suivante ;
10. les valeurs ne sont pas toutes identiques aux valeurs valables actuelles (station, quantité et heure) : sinon 50308.

Résultat : aucun. Si un contrôle échoue, rien ne change. L'heure n'est pas contrôlée (voir section 5).

### 2.12 `trace.CancelMovement`

Dit qu'un mouvement n'a pas eu lieu : une ligne `CANCEL` est ajoutée à `trace.MovementCorrection`, avec les valeurs de la version qu'elle annule. Le lot revient au statut et à la quantité de l'étape d'avant (annuler l'expédition d'un lot `SHIPPED` le ramène à `PACKED`). Une annulation est définitive.

Paramètres : `@BatchCode NVARCHAR(30)`, `@MovementId BIGINT`, `@ReasonCode NVARCHAR(50)`, `@ReasonComment NVARCHAR(2000)`, `@AuthorId NVARCHAR(200)`, `@AuthorName NVARCHAR(200)`.

Contrôles, dans cet ordre : auteur (50405, 50406), motif (50407), commentaire (50409, 50408), lot existant (50100), mouvement du lot (50103), mouvement pas déjà annulé (50305), pas la réception (50307), dernier mouvement valable du lot (50306).

Résultat : aucun. Si un contrôle échoue, rien ne change.

## 3. Ce qui reste protégé par les contraintes

Les procédures s'ajoutent aux contraintes du lot 1, elles ne les remplacent pas. Par exemple, `FK_Movement_StationCapability` refuse toujours un mouvement dont la station n'a pas la fonction, même si une écriture directe contourne les procédures.

## 4. Les erreurs

Les numéros de 50000 à 50099 sont réservés aux gardes des scripts. Les scripts `003`, `004`, `005`, `006`, `011`, `012`, `017` et `900` gardent `RAISERROR` (choix du lot 1 pour `003` et `900`). Gardes utilisées :

| N° | Sens | Script |
|---|---|---|
| 50001 | Mauvaise base de données | `002`, `007`, `008`, `009`, `010`, `013`, `014`, `015`, `016` |
| 50002 | `@TargetLots` hors de 1 à 1 000 000 | `007` |
| 50003 | Contenu inattendu : `007` refuse une base qui contient autre chose qu'un début de son jeu de données ; `008` refuse une base sans lot ; `009` et `013` à `016` exigent le jeu complet de 1 000 000 de lots | `007`, `008`, `009`, `013` à `016` |
| 50004 | Fermes ou stations de référence différentes de celles attendues | `007` |
| 50005 | Espace disque libre sous la limite `@MinFreeGB` | `007` |
| 50006 | Procédures introuvables : `009` cherche `GetBatch` et `ListBatches` (lancer `004` et `005`) ; `013` à `016` signalent « procédure introuvable » (lancer `005`) | `009`, `013` à `016` |
| 50007 | Une transaction est déjà ouverte dans la fenêtre | `016` |
| 50008 | Ferme `F001` ou station ayant la fonction `RECEPTION` absente | `016` |

| N° | Famille | Sens | Message (anglais, exemple) | Levée par |
|---|---|---|---|---|
| 50100 | Introuvable | Lot | `Batch 'LOT-1' was not found.` | `AddMovement`, `GetBatch`, `ReplaceMovement`, `CancelMovement` |
| 50101 | Introuvable | Ferme | `Farm 'F99' was not found.` | `CreateBatch`, `ListBatches` |
| 50102 | Introuvable | Station | `Station 'X' was not found.` | `AddStationCapability`, `CreateBatch`, `AddMovement`, `GetStation`, `ReplaceMovement` |
| 50103 | Introuvable | Mouvement qui n'est pas dans ce lot | `Movement 12 was not found in batch 'LOT-1'.` | `ReplaceMovement`, `CancelMovement` |
| 50200 | Existe déjà | Code de ferme | `Farm code 'F01' already exists.` | `CreateFarm` |
| 50201 | Existe déjà | Code de station | `Station code 'SITE-01' already exists.` | `CreateStation` |
| 50202 | Existe déjà | Code de lot | `Batch code 'LOT-1' already exists.` | `CreateBatch` |
| 50203 | Existe déjà | Fonction déjà déclarée | `Station 'SITE-01' already has the function 'SORTING'.` | `AddStationCapability` |
| 50300 | Règle métier | Lot déjà expédié | `Batch 'LOT-1' is already SHIPPED: no new movement.` | `AddMovement` |
| 50301 | Règle métier | Étape sautée ou mauvaise | `Batch 'LOT-1' is RECEIVED: the next movement must be SORTING, not PACKING.` | `AddMovement` |
| 50302 | Règle métier | Quantité qui monte | `Quantity 520.00 is higher than the current quantity 500.00.` | `AddMovement` |
| 50303 | Règle métier | Station sans la fonction | `Station 'SITE-01' does not have the function 'PACKING'.` | `CreateBatch`, `AddMovement`, `ReplaceMovement` |
| 50304 | Règle métier | Quantité corrigée hors des étapes voisines | `Quantity 501.00 is higher than the quantity of the previous step (500.00).` | `ReplaceMovement` |
| 50305 | Règle métier | Mouvement annulé : plus de correction | `Movement 12 is cancelled: it can no longer be corrected.` | `ReplaceMovement`, `CancelMovement` |
| 50306 | Règle métier | Annulation d'un mouvement qui n'est pas le dernier valable | `Only the last valid movement of a batch can be cancelled.` | `CancelMovement` |
| 50307 | Règle métier | Annulation de la réception | `The RECEPTION of a batch cannot be cancelled.` | `CancelMovement` |
| 50308 | Règle métier | Valeurs identiques : rien à corriger | `The new values are the same as the current ones: nothing to correct.` | `ReplaceMovement` |
| 50400 | Valeur invalide | Code vide | `The code must not be empty.` | `CreateFarm`, `CreateStation`, `CreateBatch` |
| 50401 | Valeur invalide | Quantité à 0 ou négative | `The quantity must be greater than 0.` | `CreateBatch`, `AddMovement`, `ReplaceMovement` |
| 50402 | Valeur invalide | Type de mouvement inconnu | `Unknown movement type 'LOST'.` | `AddStationCapability`, `AddMovement` |
| 50403 | Valeur invalide | Statut inconnu | `Unknown status 'LOST'.` | `ListBatches` |
| 50404 | Valeur invalide | Page ou taille de page invalide | `Invalid page number or page size.` | `ListBatches`, `ListFarms`, `ListStations` |
| 50405 | Valeur invalide | Auteur vide | `The author must not be empty.` | `CreateBatch`, `AddMovement`, `ReplaceMovement`, `CancelMovement` |
| 50406 | Valeur invalide | Identifiant ou nom de l'auteur trop long | `The author identifier or name is too long.` | `CreateBatch`, `AddMovement`, `ReplaceMovement`, `CancelMovement` |
| 50407 | Valeur invalide | Motif de correction inconnu | `Unknown reason code 'X'.` | `ReplaceMovement`, `CancelMovement` |
| 50408 | Valeur invalide | Motif `OTHER` sans commentaire | `The reason OTHER needs a comment.` | `ReplaceMovement`, `CancelMovement` |
| 50409 | Valeur invalide | Commentaire de plus de 500 caractères | `The comment is too long (500 characters at most).` | `ReplaceMovement`, `CancelMovement` |

Les familles permettront à l'API de répondre sans connaître chaque règle : 501xx introuvable, 502xx existe déjà, 503xx règle métier violée, 504xx valeur invalide.

## 5. Limites connues

- **L'heure d'un mouvement n'est pas contrôlée** : un mouvement peut avoir une heure antérieure au précédent ou située dans le futur. Le parcours est donné dans l'ordre d'enregistrement. Le métier réel dira si une règle est nécessaire.
- **Corrections** (lot 12a) : l'heure d'une version corrigée n'est pas contrôlée non plus. Seul le dernier mouvement valable peut être annulé, jamais la réception : un mouvement du milieu ne s'annule pas. Le verrou des corrections n'est essayé qu'avec deux sessions SQL et une transaction tenue ouverte à la main, pas avec deux appels HTTP lancés en même temps (voir [verification.md](verification.md), section 22.3).
- **Deux créations simultanées avec le même code** (`CreateFarm`, `CreateStation`, `CreateBatch`) : le verrou de l'ADR 0003 ne peut pas aider (il n'y a pas encore de ligne). La contrainte d'unicité du lot 1 refuse la seconde, avec l'erreur SQL Server habituelle et non la 50200, la 50201 ou la 50202.
- **Le verrou ne protège que les appels passés par la procédure.** Une écriture directe dans les tables le contourne.
- **Pas de délai d'attente** sur le verrou : un appel attend aussi longtemps que l'autre n'a pas terminé.
- **`GetBatch` lit le lot, son parcours puis ses corrections en trois requêtes**, sans verrou : si un mouvement est ajouté ou corrigé entre les lectures, les tableaux peuvent ne pas correspondre.
- **`AddMovement` appelée dans une transaction de l'appelant** : son `COMMIT` ne valide rien, le verrou et la modification restent jusqu'au `COMMIT` de l'appelant (observé pendant la preuve de l'ADR 0003). En cas d'erreur, la procédure exécute `ROLLBACK` : d'après le code, cela annule aussi le travail de l'appelant (non testé).
- **L'auteur est pris tel quel**, pour les mouvements comme pour les corrections. Les procédures contrôlent qu'il est donné et qu'il tient dans les colonnes (50405, 50406), pas qu'il correspond à un compte réel : un appel direct à une procédure peut enregistrer n'importe quel auteur. C'est l'API qui le lit dans le jeton validé.
- **Pas de modification ni de suppression** de fermes et de stations.
- **`ListFarms`, `ListStations`, `ListBatches` et `GetStation` lisent en deux requêtes, sans verrou** (la page puis le total, la station puis ses fonctions) : si une ligne est ajoutée entre les deux lectures, les deux tableaux peuvent ne pas correspondre. Même principe que `GetBatch`.
- **`ListFarms` et `ListStations` ne sont pas mesurées** sur un grand volume : `TraceabilityDev` ne compte que 200 fermes et 30 stations. Le coût de leur tri et de leur total n'est pas connu.
- **Le total de `ListBatches` (mesuré aux lots 3a et 5)**, sur 1 000 000 de lots inventés ; détail dans [mesures.md](mesures.md), sections 4.3 et 7 à 9.6, et dans l'[ADR 0008](adr/0008-listbatches-page-avant-jointure-total-recompile.md). Avant le lot 5, il lisait 10 574 pages de `Batch` à chaque appel, quel que soit le filtre. Depuis `017`, son plan est refait à chaque appel (`OPTION (RECOMPILE)`) et il peut utiliser l'index `IX_Batch_FarmId` : 1 737 lectures sans filtre, 47 pour la ferme `F001` (25 000 lots) et 8 pour `F021` (2 777 lots). Le filtre par statut n'est pas amélioré : 10 574 lectures pour `RECEIVED`, aucun index sur `Status`. Coût mesuré : 13,57 Mo d'index et environ 0,12 ms de plus par lot créé (dans SSMS).
- **`ListBatches` : les pages éloignées** (mesuré aux lots 2b et 5, sur 1 000 000 de lots inventés ; détail dans [mesures.md](mesures.md) et dans l'[ADR 0008](adr/0008-listbatches-page-avant-jointure-total-recompile.md)). Avant `017`, la dernière page triait un million de lignes avec un déversement dans `tempdb` : de 7,9 s à 146 s dans SSMS, et 3 échecs sur 3 par l'API au début de la séance du 2026-10-23. Depuis `017`, la page est découpée dans `Batch` seule avant la jointure avec `Farm` : sans filtre, la dernière page (66 667 de 15 lignes) lit 10 424 pages de `Batch` et 20 de `Farm`, sans tri, en 277 à 298 ms pour l'appel entier dans SSMS (5 exécutions) et de 0,45 à 1,59 s par l'API (10 appels). La pagination par `OFFSET` reste linéaire : plus la page est lointaine, plus le nombre de pages lues augmente (toute la table pour la dernière page). `RECEIVED`, dont les lots sont les derniers dans l'ordre de `BatchId` dans nos données, coûte encore 9 351 lectures dès la page 1. Pistes non essayées : un index sur `Status` ; une pagination qui ne passe pas par `OFFSET` (reprendre après le dernier numéro de lot vu), qui changerait le contrat de l'API.
