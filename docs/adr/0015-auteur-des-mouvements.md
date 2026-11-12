# ADR 0015 : chaque mouvement enregistre son auteur, lu dans le jeton, avec son identifiant et son nom

Statut : **Accepté** (2026-11-10)

## Contexte

Depuis le lot 10c ([ADR 0014](0014-connexion-dans-l-interface-web-pkce-et-jeton-en-memoire.md)), un utilisateur se connecte à Keycloak dans l'interface, et l'API connaît son rôle. Mais le journal des mouvements dit seulement quoi, où et quand : il ne dit pas qui a saisi. Le lot 11 ajoute l'auteur de chaque mouvement. L'essai et ses résultats sont dans [verification.md](../verification.md), section 21.

Le modèle garde deux sortes de données : `Movement` est un journal où l'on n'ajoute que des lignes, et `Batch` est l'état actuel du lot, qui change à chaque mouvement. Seuls `CreateBatch` et `AddMovement` écrivent des mouvements. La base ne connaît pas les comptes : ils sont dans Keycloak.

## Décision

- **L'auteur est dans `Movement`, pas dans `Batch`.** Un lot passe par plusieurs étapes, saisies par des personnes différentes : une seule colonne dans `Batch` ne garderait que le premier ou le dernier auteur, et il faudrait la réécrire à chaque mouvement, donc perdre l'ancien. Chaque ligne du journal garde son auteur. « Qui a créé le lot » est l'auteur de son premier mouvement.
- **Deux colonnes**, `AuthorId` (`NVARCHAR(64)`, le champ `sub` du jeton, identifiant stable du compte) et `AuthorName` (`NVARCHAR(100)`, le champ `preferred_username`, le nom au moment de la saisie). L'identifiant d'un compte Keycloak ne change pas si la personne change de nom ; le nom rend l'historique lisible sans annuaire.
- **Obligatoires, sans valeur par défaut**, chacune avec une contrainte `CHECK` (ni vide, ni espaces seulement). Les anciens mouvements reçoivent une valeur de remplacement : `AuthorId` = `00000000-0000-0000-0000-000000000000` et `AuthorName` = `Initial_User`, qui veut dire « aucun auteur n'a été enregistré ». L'interface affiche « Données initiales » à la place de `Initial_User`.
- **Deux paramètres de plus** pour `CreateBatch` et `AddMovement`, `@AuthorId` et `@AuthorName` (`NVARCHAR(200)`, après `@OccurredAt`), plus larges que les colonnes pour qu'une valeur trop longue arrive jusqu'au contrôle au lieu d'être coupée. Ils sont contrôlés en premier : vide ou `NULL`, erreur 50405 ; trop long, erreur 50406 ; l'API les traduit en 400 comme les autres erreurs 504xx. Un appel qui ne donne pas ces paramètres échoue avec l'erreur SQL Server 201, ce qui est voulu.
- **L'API lit l'auteur dans le jeton déjà validé, jamais dans le corps de la requête**, par `CurrentUser` (`sub` et `preferred_username`). Pour que les champs gardent le nom qu'ils ont dans le jeton, `MapInboundClaims` est réglé à `false` (par défaut, le gestionnaire de jetons de .NET renomme `sub`).
- **Un jeton valide sans `sub` ou sans `preferred_username` ne peut pas écrire un mouvement** : réponse 403. Les lectures ne sont pas touchées.
- **L'API et la base ne renvoient que le nom.** L'identifiant ne sort pas de la base. L'interface ajoute une colonne « Auteur » au parcours d'un lot.
- **Visibilité** : tous les rôles qui lisent (`reader` et `writer`) voient le nom de l'auteur. Aucune règle ne le cache. Avec des personnes réelles, ou pour un public extérieur (un organisme d'audit, par exemple), qui voit quoi se déciderait avec les responsables des données (RGPD, audit).
- **Migration** : `database/018_add_movement_author.sql` met à niveau une base existante, en une seule transaction. Par défaut (`@keep = N'NO'`) elle est annulée à la fin, c'est un essai à blanc ; les contrôles du script portent sur les colonnes, la valeur de remplacement et les contraintes. Une base neuve reçoit les colonnes par `002`. Les scripts `007` et `016` écrivent la valeur de remplacement ou passent les deux paramètres. La CI n'est pas modifiée.
- **Tests** : les tests d'intégration donnent l'identité par des en-têtes de test (faux schéma d'authentification) ; un test vérifie le réglage `MapInboundClaims`. `006` et `003` testent les procédures et les contraintes. La vraie lecture du jeton est essayée à la main avec Keycloak.

## Alternatives écartées

- **Le nom seul.** Non essayée : un changement de nom casserait le lien entre les mouvements d'une même personne.
- **L'identifiant seul.** Non essayée : la base ne connaît pas les comptes, donc l'historique ne dirait pas de qui il parle sans interroger Keycloak.
- **Des colonnes qui acceptent `NULL`**, sans valeur de remplacement. Non essayée : un mouvement sans auteur serait alors une donnée comme une autre, au lieu d'une erreur.
- **L'auteur dans `Batch`.** Non essayée : voir la décision ; un seul auteur par lot, réécrit à chaque mouvement.
- **L'auteur donné dans le corps de la requête.** Non essayée : n'importe quel appelant pourrait y mettre un autre nom (raisonnement).
- **Accepter un jeton sans identité et enregistrer un auteur « inconnu ».** Écartée : la colonne dirait « inconnu » sans qu'on sache pourquoi ; le 403 oblige à corriger la configuration de Keycloak.
- **Une table d'utilisateurs dans la base.** Non essayée : une table de plus à tenir à jour, alors que Keycloak garde déjà les comptes.
- **Renvoyer aussi l'identifiant dans l'API.** Non essayée : rien dans l'interface n'en a besoin.

## Conséquences

Positives :

- Un lot et un mouvement créés avec un vrai jeton de `writer-test` portent son nom et l'identifiant de son compte Keycloak : `AuthorId` est le même que celui affiché dans la console de Keycloak ([verification.md](../verification.md) 21.2, K15 et K16).
- Les quatre mouvements de `LOT-0000001` affichent « Données initiales » (K19), et la migration a été faite sur `TraceabilityDev` (1 000 000 de lots, 3 250 000 mouvements) : l'essai à blanc a pris 2 min 08 s, dont 54 s pour l'ajout des colonnes (K1, K2).
- Un jeton valide sans nom d'utilisateur reçoit 403 et rien n'est écrit (K21). Les rôles ne changent pas avec `MapInboundClaims = false` (K18, K20).
- Les tests détectent trois casses essayées : l'auteur non transmis par l'API (12 tests d'intégration échouent), la règle 50405 retirée de `AddMovement` (`006` échoue) et `MapInboundClaims` retiré (un test échoue, et un vrai jeton de `writer-test` est refusé) (K11 à K13).

Négatives :

- **Le nom est visible de tous les rôles qui lisent.** Aucune règle de visibilité n'existe (voir la décision).
- **Un vrai utilisateur nommé `Initial_User` serait affiché « Données initiales »** : l'interface ne distingue pas le nom de la valeur de remplacement.
- **Le nom est celui du moment de la saisie** : un changement de nom ultérieur ne change pas les lignes déjà écrites.
- **Les procédures ne vérifient pas que l'auteur est un vrai compte** : un appel direct à une procédure peut enregistrer n'importe quelle valeur non vide.
- **Un seul test de `006` attrape la suppression de la règle 50405 de `AddMovement`** (identifiant `NULL`) : il n'y a pas de test d'identifiant vide ni de nom vide pour cette procédure (K12). La contrainte de la table protège alors les données, avec une autre erreur.
- **Le réglage `MapInboundClaims` n'est vu que par un test** (`The_token_handler_keeps_the_names_of_the_fields_of_the_token`), parce que les tests d'intégration posent `sub` directement (K13).
- **`007` et `016` sont modifiés mais jamais rejoués** : rejouer `007` effacerait les 1 000 000 de lots de `TraceabilityDev` ; ils ont été relus seulement. `018` n'est pas rejoué par la CI.
- **L'effet de la migration sur la taille n'est pas établi** : l'index cluster de `Movement` fait 194,92 Mo après, sa taille avant n'a pas été mesurée. La durée de l'exécution réelle de `018` n'a pas été relevée.
- Un test de l'interface a échoué dans une exécution lente, sans être identifié ni reproduit en exécution seule (K9).
- Essai dans un seul navigateur (Edge) et sur une seule machine ; le renouvellement du jeton, la déconnexion et le cas d'un jeton sans `sub` ne sont pas essayés pour ce lot. Voir [verification.md](../verification.md) 21.3.

## Notes

- 2026-11-10 : décision prise après l'essai du lot 11 ([verification.md](../verification.md), section 21). Les choix (les deux colonnes, les colonnes obligatoires avec une valeur de remplacement, les deux paramètres des procédures, le nom seul renvoyé par l'API, la valeur de remplacement affichée « Données initiales », les longueurs, le 403 sans identité) ont été faits un à un avant l'écriture du code.
