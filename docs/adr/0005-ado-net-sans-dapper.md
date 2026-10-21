# ADR 0005 : accès aux données en ADO.NET, sans Dapper

Statut : **Accepté** (2026-10-20)

## Contexte

Les règles métier sont dans des procédures stockées (voir [ADR 0001](0001-procedures-stockees.md)), que l'API appelle. L'ADR 0001 laissait ouvert le choix de la bibliothèque d'accès : ADO.NET (`Microsoft.Data.SqlClient`) ou Dapper. Il fallait le trancher au lot 3b, avant d'écrire le code qui appelle les procédures.

Ce que l'API demande à cette couche est limité : appeler une procédure par son nom avec des paramètres, lire un ou deux tableaux de résultat, et laisser remonter les erreurs SQL, dont le numéro sert à choisir le code HTTP. Les procédures d'écriture renvoient au plus une ligne ; `ListFarms`, `ListStations` et `GetStation` renvoient deux tableaux.

## Décision

- L'API appelle les procédures avec ADO.NET seul (`Microsoft.Data.SqlClient`), sans Dapper.
- L'accès est regroupé dans une seule classe, `TraceabilityDb` (projet `Traceability.Data`) : une méthode par procédure, qui ouvre une connexion, envoie les paramètres, lit les tableaux avec `NextResultAsync` et referme la connexion.
- Cette classe ne rattrape aucune erreur SQL : l'API lit le numéro et le message de l'exception pour choisir la réponse HTTP.

Raison du choix : ADO.NET laisse voir plus de code ; idéal pour un projet d'apprentissage.

## Alternatives écartées

- **Dapper.** Une petite bibliothèque au-dessus d'ADO.NET, qui simplifie la lecture des résultats. Elle réduirait le code de lecture, mais elle ajoute une dépendance et cache ce qu'ADO.NET montre : les paramètres, la lecture des tableaux, les erreurs. Elle n'a pas été essayée dans ce projet.
- **Entity Framework Core.** Déjà écarté pour les règles métier par l'ADR 0001.

## Conséquences

Positives :

- Une seule dépendance d'accès à SQL Server : `Microsoft.Data.SqlClient` (version 7.1.1 au moment de la décision).
- Chaque appel est écrit en entier : les paramètres, leur type, la lecture des colonnes par leur nom.
- Les erreurs SQL arrivent intactes jusqu'à l'API : le numéro levé par `THROW` est lisible dans `SqlException.Number` (observé pour 7 numéros, voir [verification.md](../verification.md), section 9).

Négatives :

- Du code répétitif : ouvrir une connexion, créer les paramètres, lire les colonnes. La classe fait environ 185 lignes pour les 6 procédures du lot 3b, et elle grossira avec les 4 procédures des lots (lot 3c).
- Rien n'est automatique : pas de correspondance entre colonnes et classes. Une faute de nom de colonne ne se voit qu'à l'exécution (les tests d'intégration la verraient).
- Le choix n'a pas été comparé à Dapper, ni sur du code ni sur des mesures : on ne sait pas ce que Dapper aurait changé.

## Notes

- 2026-10-20 : décision prise avant l'écriture du code du lot 3b. Observé : les 6 procédures des fermes et des stations sont appelées par `TraceabilityDb`, et les 30 tests d'intégration du lot 3b passent, sur `TraceabilityTest` (voir [verification.md](../verification.md), section 9). Non observé : la vitesse, le comportement sous charge, et ce que donnerait Dapper.
- 2026-10-21 : lot 3c. `TraceabilityDb` appelle maintenant les 10 procédures (309 lignes, contre environ 185 pour les 6 du lot 3b : la croissance annoncée dans les conséquences négatives). Observé : une quantité de `100000000` a fait lever à SqlClient une `ArgumentException` (« Valeur du paramètre '100000000.00' hors limites ») avant tout envoi à SQL Server, donc une exception qui n'est pas une `SqlException` et que la classe ne traduit pas ; l'API vérifie maintenant la forme des quantités avant l'appel. Non observé : la vitesse, le comportement sous charge, et ce que donnerait Dapper.
