# ADR 0004 : index simple sur les mouvements par lot

Statut : **Accepté** (2026-10-19)

## Contexte

`GetBatch` renvoie le parcours d'un lot : ses mouvements, retrouvés par `BatchId` dans la table `Movement`. Au lot 2b, sur 1 000 000 de lots inventés et 3 250 000 mouvements, cette recherche n'avait aucun index sur `BatchId` : SQL Server lisait toute la table (25 412 lectures logiques pour retrouver 4 mouvements). Les mesures sont dans [mesures.md](../mesures.md).

Un index sur `Movement (BatchId)` est donc nécessaire. Reste à choisir sa forme : simple, ou « couvrant » (avec les colonnes demandées en plus).

## Décision

- Créer `IX_Movement_BatchId` sur `Movement (BatchId)`, sans colonnes incluses (script `database/010_create_indexes.sql`).
- Garder cet index simple, et ne pas créer la variante couvrante (`IX_Movement_BatchId_Covering`, avec `MovementType`, `StationId`, `QuantityKg` et `OccurredAt` en colonnes incluses), qui a été testée puis supprimée.

## Alternatives écartées

- **Aucun index.** 25 412 lectures logiques par appel de `GetBatch` pour le parcours d'un lot, avec un parcours de toute la table `Movement`.
- **Index couvrant.** 3 lectures logiques au lieu de 15, et plus de *Key Lookup* dans le plan. Mais 184,88 Mo au lieu de 56,72 Mo (3,3 fois plus), presque la taille de la table `Movement` elle-même (194,92 Mo). Il gagne 12 lectures sur une recherche qui en fait déjà 15, au prix d'un index beaucoup plus gros, qui doit aussi stocker quatre colonnes de plus à chaque nouveau mouvement.

## Conséquences

Positives :

- Le parcours d'un lot passe de 25 412 à 15 lectures logiques sur `Movement` (mesuré), avec un *Seek* et sans étape de tri.
- L'index reste modeste : 56,72 Mo, soit environ 29 % de la taille de la clé primaire de `Movement`.

Négatives :

- Pour chacun des mouvements trouvés, SQL Server retourne lire la ligne dans la table (*Key Lookup*) : 15 lectures au lieu de 3 pour ce lot de 4 mouvements.
- Tout index ralentit les écritures, puisqu'il faut le tenir à jour. Ce coût n'a pas été mesuré.
- Le choix repose sur des données inventées et une seule machine. Si `GetBatch` devenait l'appel dominant et très fréquent, la variante couvrante pourrait redevenir intéressante : à reconsidérer avec une nouvelle mesure.

## Notes

- 2026-10-19 : décision validée après mesure. Observé : lectures logiques (25 412 sans index, 15 avec l'index simple, 3 avec la variante couvrante), plans (*Scan*, puis *Seek* avec *Key Lookup*, puis *Seek* seul), taille de chaque index (voir [mesures.md](../mesures.md)). Non observé : le coût en écriture, la charge.
