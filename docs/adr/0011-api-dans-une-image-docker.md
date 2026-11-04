# ADR 0011 : l'API dans une image Docker, construite par un Dockerfile à la racine ; environnement et secrets donnés au lancement

Statut : **Accepté** (2026-11-03)

## Contexte

Le lot 7 a lancé l'API à la main contre SQL Server dans un conteneur, mais l'API elle-même restait sur le poste. Le README gardait ouverte la question de la mettre aussi dans un conteneur. Le lot 8 l'a essayée : construire une image de l'API, la lancer à côté du conteneur SQL Server sur un réseau Docker, et appeler l'API depuis l'interface web. L'essai et ses résultats sont dans [verification.md](../verification.md), section 16.

## Décision

- Un `Dockerfile` à la racine du dépôt, en deux étapes : compilation avec l'image `mcr.microsoft.com/dotnet/sdk:10.0` (restauration des paquets à partir des deux fichiers de projet, puis publication en Release de `src/Traceability.Api`), puis image d'exécution `mcr.microsoft.com/dotnet/aspnet:10.0` qui ne contient que l'API publiée.
- L'image s'exécute avec l'utilisateur `app` (non administrateur) et écoute en HTTP sur le port 8080, le port par défaut des images .NET.
- Un `.dockerignore` à la racine : `web`, `database`, `docs`, `tests`, `.git`, `.github`, `bin` et `obj` ne sont pas envoyés à Docker.
- **Aucun secret dans l'image.** La chaîne de connexion est donnée au lancement du conteneur par la variable `ConnectionStrings__Default`, comme en local. Les variables d'environnement de l'image ne contiennent ni mot de passe ni chaîne de connexion ([verification.md](../verification.md) 16.2, F3).
- **L'environnement n'est pas fixé dans l'image.** Un conteneur démarre par défaut en `Production`, où Swagger n'existe pas (réponse 404) et où le CORS de l'ADR 0007 n'est pas appliqué. Pour essayer Swagger et l'interface web, l'environnement `Development` est donné au lancement (`ASPNETCORE_ENVIRONMENT`).
- Le `Dockerfile` et le `.dockerignore` sont gardés dans le dépôt, avec la procédure pour rejouer l'essai ([verification.md](../verification.md) 16.5).

## Alternatives écartées

- **Ne pas mettre l'API dans une image** (la lancer avec `dotnet run`, comme avant le lot 8). Écartée : l'essai a montré que l'image se construit et que l'API en conteneur joint SQL Server et répond. Garder le `Dockerfile` coûte deux fichiers à entretenir.
- **Forcer l'environnement `Development` dans l'image.** Écartée : l'image activerait Swagger et le CORS quel que soit l'usage. L'environnement se donne au lancement.
- **Publier l'image avec le SDK .NET, sans `Dockerfile`.** Le SDK sait le faire (l'exemple officiel `aspnetapp` en montre un usage). Non essayée.
- **Une image d'exécution plus réduite (`aspnet:10.0-noble-chiseled`).** Non essayée : l'image essayée est `aspnet:10.0`.
- **Un fichier `docker-compose.yml` pour démarrer SQL Server et l'API ensemble.** Non essayé : le lot 8 a utilisé des commandes `docker run` et un réseau créé à la main.

## Conséquences

Positives :

- L'image se construit (259,5 s au premier lancement, 356 Mo), s'exécute avec l'utilisateur `app` et ne porte aucun secret dans ses variables ([verification.md](../verification.md) 16.2, F1 à F3).
- L'API du conteneur joint SQL Server, dans un autre conteneur, par son nom sur un réseau Docker, et répond à `GET /farms` et `GET /batches`. L'interface web y lit et y écrit une ferme (F4 à F6 et F9).
- L'essai se rejoue en suivant 16.5.

Négatives :

- **Le `Dockerfile` n'est pas construit par la CI.** La CI (`ci.yml`) compile et teste le code mais ne lance jamais `docker build`, et `protect-main` n'exige que `backend` et `frontend`. Si le `Dockerfile` casse (par exemple si l'API dépend un jour d'un troisième projet dont le fichier n'est pas copié), la CI reste verte et la fusion reste possible. Une construction de l'image en CI est prévue dans un lot dédié à la CI, dont la liste est à fixer à son début.
- Le `Dockerfile` copie à la main les deux fichiers de projet : il est à tenir à jour si la liste des projets change.
- L'API écoute en HTTP seulement : elle journalise `Failed to determine the https port for redirect` (observé, F6), car la redirection vers HTTPS est active dans `Program.cs` et aucun port HTTPS n'est connu. Le HTTPS n'est pas essayé.
- En `Production` (par défaut), Swagger est absent et le CORS n'est pas appliqué : l'interface web ne peut pas appeler l'API sans l'environnement `Development`.
- La chaîne de connexion, mot de passe compris, est une variable d'environnement du conteneur. Aucun coffre à secrets n'est essayé, et le contenu de la configuration du conteneur (`docker inspect`) n'a pas été relevé.
- Les étiquettes `10.0` des images de base sont mobiles et leurs empreintes complètes n'ont pas été relevées : une construction ultérieure peut utiliser une autre version.
- Essai sur une seule machine, avec une seule construction, et seulement la création d'une ferme et deux lectures : les stations, les mouvements et la création d'un lot n'ont pas été essayés avec l'API en conteneur.

## Notes

- 2026-11-03 : décision prise après l'essai du lot 8 ([verification.md](../verification.md), section 16). La construction de l'image en CI est renvoyée à un lot dédié à la CI.
- 2026-11-04 (lot 9) : la première conséquence négative (« Le `Dockerfile` n'est pas construit par la CI ») est levée, sans que le corps de l'ADR soit modifié. La tâche `docker` de `ci.yml` construit l'image à chaque push et à chaque pull request, sans la lancer, sans l'envoyer dans un registre et sans secret, et `docker` est exigé par `protect-main` ([ADR 0010](0010-protection-de-main-par-ruleset.md)). Observé : image construite en 16 s sur le runner (240 MB) ; un `Dockerfile` dont la ligne `COPY` de `Traceability.Data.csproj` est retirée rend la tâche rouge, à l'étape `dotnet publish` (`dotnet restore` réussit en ignorant le projet absent) ; sur la pull request jetable n° 17, le bouton de fusion est grisé ([verification.md](../verification.md), section 17, G2, G3, G6, G22 et G23). Les autres conséquences négatives restent.
