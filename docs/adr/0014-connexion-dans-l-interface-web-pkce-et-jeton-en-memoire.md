# ADR 0014 : l'interface web se connecte avec le flux code d'autorisation et PKCE, garde le jeton en mémoire et le renouvelle automatiquement

Statut : **Accepté** (2026-11-09)

## Contexte

Depuis le lot 10b ([ADR 0013](0013-jetons-keycloak-et-roles-dans-l-api.md)), l'API refuse tout appel sans jeton valide, et l'interface web affichait « Erreur 401. ». Le lot 10c fait connecter l'utilisateur dans l'interface par Keycloak. L'enregistrement de l'auteur de chaque mouvement reste pour un lot suivant. L'essai et ses résultats sont dans [verification.md](../verification.md), section 20.

Une interface web est un client « public » : tout son code est lu par le navigateur, elle ne peut garder aucun secret. Il fallait décider comment elle obtient le jeton, où elle le garde, ce qu'elle fait quand il expire, et ce qu'elle montre selon le rôle.

## Décision

- **Flux code d'autorisation avec PKCE (méthode S256)**, par la bibliothèque `oidc-client-ts` 3.5.0 : l'interface envoie l'utilisateur à Keycloak, qui le renvoie sur `/auth/callback` avec un code que l'interface échange contre un jeton. Le mot de passe n'est saisi que chez Keycloak. Les flux « implicite » et « mot de passe direct » ne sont pas activés pour ce client.
- **Un client Keycloak propre à l'interface, `traceability-web`**, dans `identity/traceability-realm.json` : public (aucun secret), flux standard seulement, PKCE exigé, adresse de retour `http://localhost:5173/auth/callback`, adresse après déconnexion `http://localhost:5173/`, origine `http://localhost:5173`, et le même mappeur d'audience que `traceability-trial` (`aud` contient `traceability-api`). `traceability-trial` est gardé pour les essais à la main.
- **Le jeton reste en mémoire** : une variable du module qui envoie les appels et le stockage en mémoire de la bibliothèque. Ni `localStorage` ni `sessionStorage` ne gardent l'utilisateur ou ses jetons. Recharger la page déconnecte ; Keycloak gardant sa propre session, « Se connecter » reconnecte alors sans mot de passe. La bibliothèque garde seulement, dans le `localStorage` et le temps de la redirection, l'état de la demande de connexion (son réglage par défaut).
- **Renouvellement automatique**, au réglage par défaut de la bibliothèque : environ 1 minute avant l'expiration du jeton, qui dure 300 secondes.
- **`Authorization: Bearer …` est ajouté à un seul endroit** (`web/src/api/client.ts`). La règle CORS de l'API (Development seulement) accepte en plus l'en-tête `Authorization` ; un test d'intégration contrôle la pré-vérification.
- **Un écran « Connexion » à un seul bouton** tant que personne n'est connecté : l'interface n'appelle alors pas l'API. Il affiche un message propre à la session expirée et un message si Keycloak est injoignable (« Impossible de joindre le serveur de connexion. Est-il lancé ? »).
- **Les rôles sont lus dans la charge utile du jeton** (`realm_access.roles`), sans en vérifier la signature : c'est un confort, l'API reste l'autorité. Sans le rôle `writer`, les boutons et formulaires d'écriture sont cachés, et les pages `/new-farm`, `/new-batch` et `/new-station` affichent « Vous n'avez pas le droit de saisir des données. » à la place du formulaire.
- **Deux messages en français** pour les réponses de l'API : 401 (connexion absente ou expirée) et 403 (« Vous n'avez pas le droit de faire cela. »).
- **Deux réglages de l'interface, sans secret** : `VITE_AUTH_AUTHORITY` (par défaut `http://localhost:8180/realms/traceability`) et `VITE_AUTH_CLIENT_ID` (par défaut `traceability-web`).
- **Tests** : la connexion est simulée (un faux contexte d'authentification, ni Keycloak ni la bibliothèque) pour contrôler ce que l'interface fait d'un `reader`, d'un `writer` ou de personne ; le vrai flux est essayé à la main. La CI n'est pas modifiée.

## Alternatives écartées

- **Écrire notre propre code d'échange OAuth et PKCE, sans bibliothèque.** Non essayée : ce serait du code de sécurité à écrire et à maintenir nous-mêmes, alors qu'une bibliothèque en fait le travail. Coût : deux paquets ajoutés (`oidc-client-ts` et `jwt-decode`, que la bibliothèque utilise).
- **Garder le jeton dans `sessionStorage` ou `localStorage`** pour qu'il survive au rechargement. Non essayée : il resterait lisible par tout script de la page et après la fermeture de l'onglet (`localStorage`). La mémoire ne protège pas d'un script malveillant déjà dans la page (raisonnement, non essayé) : elle évite seulement de le laisser sur le disque. Coût accepté : recharger reconnecte (sans mot de passe tant que la session de Keycloak dure, J13).
- **Pas de renouvellement** (reconnexion toutes les 5 minutes). Non essayée : trop gênant pour l'utilisateur.
- **Renouvellement par une page cachée** (plan de repli si Keycloak ne donnait pas de jeton de rafraîchissement). Non nécessaire : l'essai montre un renouvellement par appel à `/token`, sans page cachée (J14).
- **Le flux « implicite »** (jeton placé dans l'adresse de retour). Non essayé et non activé.
- **Un serveur intermédiaire qui garde le jeton dans un cookie `HttpOnly`.** Non essayé : un composant de plus à héberger et à maintenir.
- **Montrer les boutons d'écriture grisés à un `reader`** plutôt que les cacher. Non essayée : choix de simplicité.
- **Des tests avec un vrai Keycloak dans la CI.** Non essayés, comme à l'ADR 0013 : la CI n'est pas modifiée.

## Conséquences

Positives :

- La connexion fonctionne avec un vrai Keycloak, dans Docker et sous Windows : adresse envoyée à Keycloak avec `code_challenge_method=S256`, jeton envoyé à l'API, lecture et écriture en `writer-test` ([verification.md](../verification.md) 20.4, J8 à J11, J20).
- Aucun jeton n'est stocké dans le navigateur (J12).
- Le renouvellement a été observé deux fois à 4 minutes d'intervalle, et la session a continué après l'expiration du jeton de départ (J14).
- Les rôles sont respectés dans l'interface (J16 à J18), et un Keycloak arrêté donne un message clair puis se rattrape sans recharger (J19).
- Les tests détectent deux casses essayées : `canWrite` toujours vrai (19 tests échouent) et l'en-tête `Authorization` retiré (2 tests échouent) (J23, J24).

Négatives :

- **Recharger la page déconnecte** (J13), et après la connexion l'interface va toujours à l'accueil, pas à la page demandée.
- **Le moyen exact du renouvellement est déduit, pas lu** : deux appels `/token` et aucune page cachée, sans ouvrir le contenu des requêtes (J14). Aucun renouvellement n'a été essayé sous Windows, ni en cas d'échec pendant une session.
- **Deux entrées `oidc.…` ont été vues dans le `localStorage` au premier essai** là où une seule était attendue ; la cause n'est pas établie (un double clic est possible) et un essai suivant n'en montre qu'une, supprimée après la connexion (J12).
- **La déconnexion quand Keycloak est injoignable n'est pas essayée** : l'interface retire alors seulement la connexion locale.
- **Les rôles lus sans vérifier la signature** servent au confort : un jeton modifié à la main ferait voir des boutons, que l'API refuserait (403, lot 10b) ; ce cas précis n'est pas essayé.
- **Un realm Keycloak déjà importé n'a pas le client `traceability-web`** : le conteneur (ou, sous Windows, `data\h2`) est à recréer, et les comptes à refaire à la main.
- Essai dans un seul navigateur (Chrome), sur une seule machine ; le mode production, HTTPS, plusieurs onglets et un autre navigateur ne sont pas essayés. Voir [verification.md](../verification.md) 20.3.

## Notes

- 2026-11-09 : décision prise après l'essai du lot 10c ([verification.md](../verification.md), section 20). Les choix (bibliothèque, jeton en mémoire, renouvellement automatique, boutons cachés pour un `reader`, tests simulés) ont été faits un à un avant l'écriture du code. L'enregistrement de l'auteur de chaque mouvement reste pour un lot suivant.
