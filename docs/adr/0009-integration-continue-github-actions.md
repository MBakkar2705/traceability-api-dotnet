# ADR 0009 : intégration continue avec GitHub Actions : SQL Server en conteneur (authentification SQL), déclenchement à chaque push et pull request, runner et actions fixés

Statut : **Accepté** (2026-10-26)

## Contexte

Les tests d'intégration tournent sur une vraie base SQL Server ([ADR 0002](0002-tests-sur-base-reelle.md)), mais jusqu'au lot 5 seulement sur la machine de développement, en authentification Windows. Le lot 6 les rejoue à chaque changement, sur une machine vierge : `.github/workflows/ci.yml`. Les hypothèses écrites avant le premier lancement, les neuf exécutions observées et ce qui est prouvé ou non sont dans [verification.md](../verification.md), section 14.

## Décision

- **SQL Server 2025 en conteneur de service, en authentification SQL.** L'image est `mcr.microsoft.com/mssql/server:2025-latest`, le mot de passe de `sa` vient du secret de dépôt `MSSQL_SA_PASSWORD`. La base `TraceabilityTest` est reconstruite à chaque exécution par les scripts `001`, `002`, `004`, `005`, `011` et `017`, sur des copies temporaires où la ligne `:setvar DbName` est remplacée : les fichiers du dépôt ne changent pas. `sqlcmd` est absent du runner (hypothèse C2 fausse, [verification.md](../verification.md) 14.2) : il est installé par `apt` (paquet `mssql-tools18`, 15 s). Le code C# ne change pas : la méthode d'authentification dépend du contenu de la chaîne de connexion, fournie par `ConnectionStrings__Test`.
- **Déclenchement sur chaque push et sur chaque pull request, sans filtre de branche.** Un push sur une branche qui a une pull request lance donc deux exécutions (une `push`, une `pull_request` de type `synchronize`). Ce doublon est accepté : le projet est petit et une exécution dure environ une minute. La pull request teste la fusion de la branche avec `main`, pas la branche seule ([verification.md](../verification.md) 14.6).
- **Runner fixé à `ubuntu-24.04`** sur les deux tâches, au lieu de `ubuntu-latest`, que GitHub annonçait migrer vers Ubuntu 26 à partir du 2026-10-19.
- **Actions fixées par version majeure** (`actions/checkout@v7`, `actions/setup-dotnet@v6`, `actions/setup-node@v7`), et `permissions: contents: read` pour le jeton du workflow.
- **Étiquette `2025-latest` de l'image conservée.** Le digest de l'image de chaque exécution est relevé dans les journaux ([verification.md](../verification.md) 14.5).

## Alternatives écartées

- **Ne tester en CI que le code sans base** (tests unitaires). Écarté : les 88 tests d'intégration sont ceux qui traversent l'API, les procédures et la base.
- **Un runner Windows, avec l'authentification Windows de la machine de développement.** Non essayé.
- **Lancer les scripts SQL dans le conteneur au lieu d'installer `sqlcmd` sur le runner.** Non essayé : le diagnostic ([verification.md](../verification.md) 14.3) a montré que `sqlcmd` existe dans le conteneur, donc c'était possible ; l'installation par `apt` a suffi.
- **Se déclencher seulement sur les pull requests, ou sur les push vers `main` plus les pull requests.** Aucun doublon, mais une branche sans pull request ne serait pas testée à chaque push. Non essayé.
- **Fixer les actions par empreinte de commit (SHA)** au lieu de la version majeure. Plus strict, plus lourd à tenir à jour. Non fait.
- **Fixer l'image par digest ou par numéro de version précis** au lieu de `2025-latest`. Non fait : le digest est seulement noté dans les journaux.

## Conséquences

Positives :

- Les 163 tests C# (75 unitaires et 88 d'intégration) et les 178 tests de l'interface (22 fichiers) tournent sur une machine vierge, en environ une minute (de 56 s à 1 min 12 s pour les exécutions réussies n° 3 à 7).
- Une pull request est testée telle qu'elle serait après la fusion avec `main`.
- Le secret est masqué (`***`) dans les journaux.

Négatives :

- Le doublon d'exécutions sur une branche qui a une pull request.
- Le moteur de la CI est plus récent que celui de la machine de développement (17.0.5035.5 contre 17.0.1145.4) et l'étiquette `2025-latest` se déplace avec le temps : une nouvelle version du moteur peut changer un résultat sans qu'aucun fichier du dépôt n'ait changé.
- L'authentification Windows, utilisée en local, n'est pas couverte par la CI.
- Selon la documentation de GitHub, les secrets ne sont pas transmis à un workflow lancé depuis un fork : la tâche `backend` d'une pull request venant d'un fork échouerait. Non essayé.
- Une action fixée par version majeure peut changer sans prévenir.
- `SQLCMDPASSWORD` est défini au niveau de la tâche `backend` : toutes ses étapes, y compris les actions de GitHub (`checkout`, `setup-dotnet`), y ont accès. Le réduire aux seules étapes qui appellent `sqlcmd` est possible ; non fait.
- `ubuntu-24.04` devra être remplacé à la main un jour.
- Aucun test n'a encore été vu faire passer la CI au rouge ([verification.md](../verification.md) 14.8).

## Notes

- 2026-10-26 : décision validée après neuf exécutions observées (n° 1 et 2 en échec, n° 3 à 9 réussies). Détail, versions des outils et du moteur : [verification.md](../verification.md), section 14.
