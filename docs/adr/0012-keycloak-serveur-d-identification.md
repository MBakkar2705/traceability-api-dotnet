# ADR 0012 : Keycloak comme serveur d'identification (OAuth 2.0 et OpenID Connect), réglages gardés dans le dépôt, essayé dans Docker et sous Windows

Statut : **Accepté** (2026-11-05)

## Contexte

Jusqu'au lot 9, l'API ne sait pas qui l'appelle : `Program.cs` active l'autorisation sans aucune authentification, et tout appel est accepté. Le lot 10 ajoute l'identification en trois étapes : 10a (un serveur d'identification seul, sans toucher au code C#), 10b (l'API vérifie les jetons et applique les rôles) et 10c (la connexion dans l'interface web). Cet ADR couvre le lot 10a. L'essai et ses résultats sont dans [verification.md](../verification.md), section 18.

Le cadre retenu est OAuth 2.0 avec OpenID Connect : l'utilisateur obtient un jeton auprès d'un serveur d'identification, et l'API accepte ce jeton sans jamais voir le mot de passe. Le serveur choisi pour l'essai est Keycloak.

## Décision

- **Keycloak 26.6.2** est le serveur d'identification de l'essai. Il est essayé de deux façons, comme l'API et la base : dans Docker (image `quay.io/keycloak/keycloak:26.6.2`, empreinte `sha256:f9ba7b2af90db8dc749a57ca9aedca51e840cb9224441ab546a968da941da900`) et sous Windows (archive `keycloak-26.6.2.zip`, sans installateur).
- **Sous Windows, avec un JDK 21 extrait d'une archive `.zip`** (Eclipse Temurin 21.0.13+9), à côté du Java 24 existant. `JAVA_HOME` n'est posé que dans la fenêtre qui lance Keycloak ; le PATH de Windows n'est pas modifié.
- **Les réglages sont gardés dans le dépôt**, dans `identity/traceability-realm.json`, et importés au démarrage (`--import-realm`) : un realm `traceability`, deux rôles (`reader` pour consulter, `writer` pour saisir) et un client d'essai `traceability-trial` (le flux « mot de passe direct » y est autorisé, il ne sert qu'aux essais à la main et n'est pas prévu pour l'interface web, qui utilisera le code d'autorisation avec PKCE au lot 10c).
- **Aucun utilisateur, aucun mot de passe et aucun secret dans le dépôt.** Le fichier ne contient aucun compte ; les comptes `reader-test` et `writer-test` sont créés à la main dans la console, et les mots de passe sont saisis masqués.
- **Mode développement seulement** (`start-dev`), port 8180 (8080 est pris par l'API en conteneur du lot 8), écoute limitée à `127.0.0.1`. Les données sont dans la base H2 intégrée de Keycloak : elles disparaissent avec le conteneur, et le fichier de réglages permet de recréer le realm.
- Aucun code C# n'est modifié par ce lot.

## Alternatives écartées

- **Écrire notre propre identification** (comptes et mots de passe dans notre base, émission de jetons par l'API). Écartée : la gestion des mots de passe et des jetons est un travail à risque que Keycloak fournit. Non essayée.
- **Ne pas identifier les appels** (situation actuelle). Écartée : la question « qui a fait chaque mouvement » (lot ultérieur) ne peut pas être traitée sans identité.
- **Un autre serveur d'identification** (un service hébergé, par exemple). Non essayé : seul Keycloak a été essayé.
- **Installer le JDK 21 avec l'installateur Windows.** Écartée : l'installateur modifie le système, et l'archive `.zip` permet de garder le Java 24 par défaut (H11, H15).
- **Java 24 ou Java 25 pour Keycloak.** Non essayés : les versions prises en charge indiquées par Keycloak sont 17, 21 et 25.
- **Une version de Keycloak plus récente que 26.6.2.** Non essayée : la 26.6.2 est gardée dans les deux modes pour qu'ils soient comparables.
- **Un fichier `docker-compose.yml`.** Non essayé : l'essai utilise une commande `docker run`.

## Conséquences

Positives :

- Le fichier `identity/traceability-realm.json` suffit à reconstruire le realm, les deux rôles et le client d'essai dans les deux modes, y compris après la suppression du conteneur ([verification.md](../verification.md) 18.4, H4, H10 et H13).
- Un compte par rôle obtient un jeton (`HTTP:200`, 300 secondes) qui contient son rôle dans `realm_access.roles` et pas l'autre ; un mauvais mot de passe est refusé (`HTTP:400`, `invalid_grant`) (H6 à H8).
- Sous Windows, c'est le JDK 21 qui fait tourner Keycloak, le Java 24 reste le défaut et aucun processus Java ne reste après l'arrêt (H11, H14 et H15).
- Le lot ne modifie ni l'API, ni l'interface, ni la CI, ni la base.

Négatives :

- **Le mode développement n'est pas un mode de production** : Keycloak le dit dans son journal. Le mode de production, le HTTPS et une base externe ne sont pas essayés.
- **Les comptes ne sont pas dans le dépôt** : après chaque recréation du conteneur, `reader-test` et `writer-test` sont à recréer à la main.
- **Un administrateur temporaire** (variables de démarrage, mot de passe saisi au lancement) est utilisé ; la console demande d'en créer un permanent. Cela n'est pas fait.
- **Keycloak consomme de la mémoire** : après les jetons, 706,3 MiB pour le conteneur et 512,5 MiB pour le processus Java sous Windows (deux mesures différentes). Le démarrage prend de 26 à 50 secondes.
- **Constats à traiter au lot 10b** (non essayés avec l'API) : le jeton du rôle `writer` ne contient pas `reader` ; `aud` vaut `account`, pas l'API ; `iss` dépend de l'adresse utilisée pour demander le jeton (observé seulement avec `http://localhost:8180`).
- Essai sur une seule machine, avec une seule version de Keycloak, deux comptes et sans aucune API qui vérifie un jeton.

## Notes

- 2026-11-05 : décision prise après l'essai du lot 10a ([verification.md](../verification.md), section 18). La vérification des jetons par l'API (10b), la connexion dans l'interface web (10c) et l'enregistrement de l'auteur de chaque mouvement sont renvoyés à des lots suivants.
- 2026-11-07 : le lot 10b ([ADR 0013](0013-jetons-keycloak-et-roles-dans-l-api.md)) a traité les « constats à traiter au lot 10b » ci-dessus. Le corps de cet ADR n'est pas modifié.
