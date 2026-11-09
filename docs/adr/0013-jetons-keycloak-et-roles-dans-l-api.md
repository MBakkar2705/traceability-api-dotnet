# ADR 0013 : l'API vérifie les jetons de Keycloak (signature, émetteur, expiration, public visé) et applique deux rôles, `reader` et `writer`

Statut : **Accepté** (2026-11-07)

## Contexte

Après le lot 10a ([ADR 0012](0012-keycloak-serveur-d-identification.md)), Keycloak délivre des jetons mais l'API les ignore : `Program.cs` active l'autorisation sans authentification, et tout appel est accepté. Le lot 10b fait vérifier les jetons par l'API et applique les rôles `reader` et `writer`. La connexion dans l'interface web (10c) et l'enregistrement de l'auteur de chaque mouvement restent pour des lots suivants. L'essai et ses résultats sont dans [verification.md](../verification.md), section 19.

L'ADR 0012 laissait trois constats à traiter : le jeton du rôle `writer` ne contient pas `reader` ; `aud` vaut `account` et non l'API ; `iss` n'était observé qu'avec `http://localhost:8180`.

## Décision

- **L'API vérifie chaque jeton d'accès** (`Authorization: Bearer …`) avec le composant `Microsoft.AspNetCore.Authentication.JwtBearer` 10.0.13 : signature, émetteur (`iss`), expiration (`exp`) et public visé (`aud`). Elle lit la configuration publique du realm (dont les clés de signature) ; elle ne détient aucun secret.
- **Deux variables d'environnement**, comme `ConnectionStrings__Default` et jamais dans un fichier du dépôt : `Authentication__Authority` (`http://localhost:8180/realms/traceability`) et `Authentication__Audience` (`traceability-api`). Si l'une manque, le code lève une erreur qui nomme la variable ; ce cas n'a pas été essayé. Elles sont lues quand les réglages d'authentification sont demandés pour la première fois, et non à la construction de l'application, pour que les tests d'intégration, qui remplacent ce schéma, n'en aient pas besoin.
- **Un mappeur d'audience** est ajouté au client `traceability-trial` dans `identity/traceability-realm.json` : `aud` contient `traceability-api`, et l'API l'exige.
- **Deux règles d'autorisation** : `CanRead` (les 5 routes `GET`) accepte `reader` ou `writer` ; `CanWrite` (les 5 routes `POST`) demande `writer`. `reader` ou `writer` pour la lecture, parce que le jeton d'un `writer` ne contient pas `reader` (constat de 18.2, H7). Chaque route de contrôleur porte sa règle ; le code ne définit pas de règle par défaut.
- **Les rôles sont lus par du code C#** : ils sont dans `realm_access.roles`, un objet JSON dans le jeton, que l'API ne transforme pas d'elle-même en rôles. À la validation d'un jeton, `KeycloakRoles` ajoute un rôle par entrée de `realm_access.roles`. Une valeur absente, mal formée ou d'un autre type donne zéro rôle, donc un 403.
- **Réponses** : pas de jeton ou jeton invalide, 401 (`WWW-Authenticate: Bearer`) ; jeton valide mais rôle insuffisant, 403.
- **Swagger** (Development seulement) déclare le schéma « Bearer » : le bouton Authorize permet d'envoyer un jeton.
- **Tests** : un faux schéma d'authentification remplace le vrai dans les tests (aucun Keycloak, aucun vrai jeton) ; un en-tête de test donne les rôles de l'appelant. Ils contrôlent les règles route par route et qu'aucune route n'est sans règle. La vérification d'un vrai jeton est essayée à la main. La CI n'est pas modifiée.
- **L'interface web n'est pas modifiée** : elle reçoit 401 tant que le lot 10c n'a pas ajouté la connexion.

## Alternatives écartées

- **Ne pas vérifier les jetons, ou écrire notre propre connexion.** Écartée : voir l'ADR 0012. L'API ne gère aucun mot de passe.
- **Demander à Keycloak si le jeton est valide à chaque appel** (introspection). Non essayée : la vérification locale de la signature évite un appel réseau par requête. Conséquence attendue, non essayée : un jeton révoqué reste accepté jusqu'à son expiration (voir plus bas).
- **Rendre `writer` composite (il inclurait `reader`), ou donner les deux rôles aux écrivains.** Non essayées : ce serait un réglage de plus à maintenir dans Keycloak, alors que la règle `CanRead` accepte les deux rôles.
- **Ne pas contrôler `aud`.** Écartée : un jeton émis pour une autre application du même realm serait accepté. Le contrôle de `aud` est essayé (I15).
- **Faire transformer les rôles par Keycloak** (un mappeur de rôles en champ simple) **au lieu du code C#.** Non essayée : elle changerait la forme des jetons du realm et le fichier de réglages ; le code C# garde les jetons tels que le lot 10a les a observés.
- **Un vrai Keycloak dans la CI.** Non essayé : la CI n'est pas modifiée, donc les tests automatiques ne vérifient aucun vrai jeton.
- **Réduire la tolérance d'horloge de la validation** (5 minutes par défaut). Non essayée : la valeur par défaut est gardée.

## Conséquences

Positives :

- Un vrai jeton est accepté ou refusé comme prévu : sans jeton 401, `reader` 200 en lecture et 403 en écriture, `writer` 200 et 201, jeton mal formé 401, mauvais émetteur 401, mauvais public visé 401, jeton expiré 401 après environ 5 minutes ([verification.md](../verification.md) 19.4, I7 à I15).
- Un test échoue si une route de contrôleur n'a aucune règle (I3).
- Les contrôles principaux donnent le même résultat sous Windows (I18).
- Aucun jeton brut ni mot de passe dans les fichiers du lot (I20).

Négatives :

- **L'interface web affiche « Erreur 401. » jusqu'au lot 10c** (I19).
- **Un realm Keycloak déjà créé n'est pas réimporté** : sous Windows, le mappeur d'audience n'y est pas pris en compte tant que le dossier `data\h2` n'est pas supprimé, et les comptes sont à recréer (I18). Dans Docker, un conteneur créé avant le lot est à recréer.
- **L'API en conteneur avec Keycloak n'est pas essayée** : l'adresse où l'API lit les clés de Keycloak peut différer de l'émetteur attendu.
- **La révocation d'un jeton n'est pas essayée** : l'API ne demande rien à Keycloak à chaque appel, donc un jeton révoqué devrait rester accepté jusqu'à son expiration (non vérifié). Keycloak arrêté, un jeton déjà vu par l'API est encore accepté (I16).
- **Le flux « mot de passe direct » reste sur le client d'essai** ; il ne sert qu'aux essais à la main.
- Essai sur une seule machine, avec deux comptes ; le mode production, HTTPS (l'API n'accepte de lire la configuration de Keycloak en HTTP qu'en Development) et la rotation des clés de signature ne sont pas essayés. Voir [verification.md](../verification.md) 19.3.

## Notes

- 2026-11-07 : décision prise après l'essai du lot 10b ([verification.md](../verification.md), section 19). La connexion dans l'interface web (10c) et l'enregistrement de l'auteur de chaque mouvement sont renvoyés à des lots suivants.
