# ADR 0003 : verrou sur le lot pour deux mouvements simultanés

Statut : **Accepté** (2026-10-18)

## Contexte

`AddMovement` lit l'état du lot (statut et quantité), vérifie les règles métier, puis ajoute un mouvement et met le lot à jour. Si deux appels arrivent en même temps sur le même lot, chacun peut lire l'état d'avant l'autre : par défaut, SQL Server n'empêche pas deux lectures simultanées.

Exemple : un lot est `RECEIVED` avec 500.00 kg. Deux appels `SORTING` (470.00 kg et 480.00 kg) lisent tous les deux « `RECEIVED` », trouvent que tout est en règle et ajoutent chacun un mouvement. Le journal contient alors deux `SORTING` pour le même lot, et le lot garde la quantité de celui qui écrit en dernier. Aucune contrainte du lot 1 ne l'empêche, et chaque appel, pris seul, respecte les règles.

## Décision

- `AddMovement` s'exécute dans une transaction et commence par lire la ligne du lot avec un verrou de mise à jour (`UPDLOCK`), gardé jusqu'à la fin de la transaction.
- Un deuxième appel sur le même lot attend la fin du premier, puis lit l'état déjà modifié : les règles métier s'appliquent sur l'état réel, et chacune garde son propre numéro d'erreur (voir [procedures.md](../procedures.md)).
- Le verrou porte sur la ligne du lot : des appels sur des lots différents ne devraient pas s'attendre.
- La procédure utilise `SET XACT_ABORT ON` : une erreur annule toute la transaction.

## Alternatives écartées

- **Ne rien protéger.** Le journal peut contenir deux fois la même étape, et le lot garde une quantité qui dépend de l'ordre d'arrivée.
- **Mettre à jour le lot en premier, avec une condition** (`UPDATE ... WHERE Status = <étape précédente>`, puis tester le nombre de lignes modifiées). C'est atomique et sans verrou écrit à la main, mais quand aucune ligne n'est modifiée, on ne sait pas quelle règle a échoué : il faut relire le lot pour trouver la bonne erreur, ce qui complique la procédure.
- **Niveau d'isolation `SERIALIZABLE` pour toute la procédure.** Une seule ligne à écrire, mais des verrous plus larges, et deux appels simultanés peuvent se bloquer mutuellement : SQL Server arrête alors l'un des deux avec l'erreur 1205 (deadlock), à gérer. Plus difficile à raisonner.

## Conséquences

Positives :

- Les règles sont vérifiées sur l'état réel du lot, et chaque règle garde son numéro d'erreur.
- La solution est simple à expliquer et à lire dans la procédure.

Négatives :

- Un appel attend si un autre traite le même lot. Aucun délai limite n'est fixé (par défaut, SQL Server attend sans limite) : à reconsidérer.
- Le verrou ne protège que ce qui passe par la procédure : une écriture directe dans les tables le contournerait (les droits d'accès seront restreints plus tard).
- Il ne couvre pas `CreateBatch` : il n'y a pas encore de ligne à verrouiller. Deux créations simultanées du même code de lot sont arrêtées par la contrainte d'unicité du lot 1, avec l'erreur SQL Server habituelle et non notre erreur 50202.
- Si une procédure verrouille plusieurs objets dans des ordres différents, un blocage mutuel (deadlock) devient possible : à surveiller quand de nouvelles procédures seront ajoutées.

## Notes

- 2026-10-18 : décision validée. Le comportement devait être observé à la main avec deux fenêtres SSMS (lot 2a) ; voir la note suivante.
- 2026-10-19 : comportement observé à la main sur `TraceabilityTest`, avec deux fenêtres SSMS (détail dans [verification.md](../verification.md)). Observé : (1) tant qu'une session tient un verrou de mise à jour sur le lot (`UPDLOCK`), un appel à `AddMovement` sur ce lot attend (`LCK_M_U`, bloqué par l'autre session), alors qu'une lecture simple n'attend pas ; l'appel se termine dès que le verrou est libéré ; (2) deux `SORTING` contradictoires sur le même lot : le second attend, puis, après la validation du premier, est refusé par l'erreur 50301, sans mouvement en double et sans transaction ouverte. Non observé : le comportement sans `UPDLOCK` (on ne sait donc pas ce que le verrou apporte en plus de la modification faite par le premier appel), deux appels sur des lots différents, les blocages mutuels, la charge. Dans l'essai (2), le premier appel était lancé à l'intérieur d'une transaction ouverte par l'appelant.
