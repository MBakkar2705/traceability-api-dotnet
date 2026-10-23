# ADR 0008 : `ListBatches` : page découpée avant la jointure, total refait à chaque appel, index sur la ferme

Statut : **Accepté** (2026-10-23)

## Contexte

La liste des lots (`trace.ListBatches`) a deux défauts mesurés au lot 5, sur 1 000 000 de lots inventés. Les mesures, avec leurs hypothèses écrites avant et leurs résultats, sont dans [mesures.md](../mesures.md), sections 6 à 9.6.

- **Le total** relit toute la table `Batch` : 10 574 lectures logiques, quel que soit le filtre. Le plan est construit une fois pour tous les appels, avec ou sans filtre, et ne peut donc pas utiliser un index sur la ferme (explication cohérente avec les mesures T3 et D1, non démontrée séparément).
- **La dernière page** (le bouton « Fin » de l'interface : page 66 667 de 15 lignes) joint `Batch` et `Farm`, puis trie un million de lignes par numéro de lot, avec un déversement dans `tempdb` et une demande d'environ 93 Mo de mémoire. Dans SSMS, la même page a duré de 7,9 s à 146 s pour les mêmes lectures de pages. Par l'API, les trois premiers appels de la séance du 2026-10-23 ont échoué après environ 30 s (délai du pilote SQL, erreur -2 lue dans le journal pour le premier). Une requête de ce type a été vue en attente de mémoire (`RESOURCE_SEMAPHORE`, 0 Ko accordé) pendant plusieurs minutes quand le budget de mémoire des requêtes de SQL Server était de 5 Mo. Les échecs n'ont pas pu être reproduits à volonté.

## Décision

Dans `database/017_optimize_list_batches.sql` :

- **La page est découpée dans `Batch` seule, avant la jointure avec `Farm`** : `SELECT … FROM (SELECT … ORDER BY BatchId OFFSET … FETCH …) AS p JOIN Farm …`, avec un `ORDER BY` extérieur. SQL Server lit `PK_Batch` dans l'ordre et n'a plus rien à trier. Le contrat ne change pas : mêmes colonnes, mêmes lignes, même ordre (vérifié sur 6 cas).
- **Le total est écrit avec `OPTION (RECOMPILE)`** : son plan est construit pour les filtres de l'appel et peut utiliser l'index.
- **L'index `IX_Batch_FarmId` sur `Batch (FarmId)` est créé** (13,57 Mo).

## Alternatives écartées

- **Ne rien changer.** Le total lit 10 574 pages à chaque appel ; la dernière page dure de 7,9 s à 146 s dans SSMS et a échoué par l'API.
- **`OPTION (MAXDOP 1)` sur la requête de la page.** Dans SSMS, la même page durait de 1,4 à 1,6 s au lieu de 7,7 à 9,0 s (5 paires), mais le tri d'un million de lignes et son déversement restaient, avec la même demande de mémoire (environ 88 Mo). Non testée par l'API. La page découpée avant la jointure supprime le tri : de 178 à 349 ms dans les mêmes conditions (5 paires).
- **Plusieurs variantes du total selon les filtres (branches `IF`), ou du SQL dynamique.** Non mesurées. Écartées pour la quantité de code à écrire et à tester, face à `OPTION (RECOMPILE)` dont le coût mesuré est faible (environ 4 ms par appel).
- **La pagination par clé** (reprendre après le dernier numéro de lot vu, au lieu d'un numéro de page). Elle supprimerait la lecture linéaire des pages lointaines, mais elle changerait le contrat de l'API et de l'interface : hors du périmètre de ce lot.
- **Un index sur `Status`.** Non essayé : le filtre par statut reste à 10 574 lectures pour le total.

## Conséquences

Positives (mesurées dans SSMS sur `TraceabilityDev`, sauf la dernière ligne ; [mesures.md](../mesures.md), sections 9.4 à 9.6) :

- Total sans filtre : de 10 574 à 1 737 lectures (un index lu sans parallélisme) ; par ferme : 47 lectures pour `F001` et 8 pour `F021`.
- Dernière page : de 7,9–146 s à 277–298 ms (5 exécutions), avec 10 424 lectures de `Batch` et aucune zone de travail.
- Page 1 : 4 lectures de `Batch`. Le plan de la page reste efficace quand il a été construit pour la dernière page, alors que l'ancien plan lisait alors 10 574 pages pour la page 1.
- Par l'API : 10 appels de « Fin » de 0,45 à 1,59 s (moyenne 0,65 s), tous réussis, avec un budget de mémoire des requêtes de 5 Mo.

Négatives :

- L'écriture d'un lot coûte un peu plus : `CreateBatch` environ 0,12 ms plus lent par appel et 118 octets de journal en plus (+74 % de durée et +19 % de journal sur 500 appels, dans SSMS, deux mesures séparées de 27 minutes).
- 13,57 Mo d'index de plus.
- Le plan du total est refait à chaque appel (environ 4 ms par appel, mesuré avec l'index).
- Le filtre par statut n'est pas amélioré.
- La dernière page lit toujours toute la table (10 424 pages) : la pagination par numéro de page reste linéaire.
- La correction des échecs de « Fin » n'est pas prouvée : ils ne se reproduisaient pas à volonté, et l'absence d'échec dans les 10 appels est cohérente avec la correction sans la démontrer.
- Une seule machine (8 Go de RAM, plus de 90 % de mémoire utilisée pendant la séance) et des données inventées.

## Notes

- 2026-10-23 : décision validée après mesure. Observé : lectures logiques et plans (« avant » : sections 7 à 9.5 de [mesures.md](../mesures.md) ; « après » : 9.6), durées de 5 exécutions, 10 appels par l'API, lignes identiques sur 6 cas, 163 tests C# réussis et `006` à 38 / 34 / 4 sur `TraceabilityTest`. Non observé : le coût en écriture dans l'application (mesuré seulement par `CreateBatch` dans SSMS), les échecs de « Fin » reproduits à volonté, la demande de mémoire du nouveau plan, d'autres machines, d'autres volumes.
- 2026-10-23 : correction d'unité. La demande de mémoire de la variante `OPTION (MAXDOP 1)`, citée plus haut comme « environ 88 Mo », est de 88 104 Ko, soit environ 86 Mo (1 Mo = 1 024 Ko, comme pour les 95 296 Ko, soit environ 93 Mo, du plan parallèle). Les valeurs en kilo-octets sont dans [mesures.md](../mesures.md), sections 8.4 et 9.1.
