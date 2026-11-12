# traceability-api-dotnet

[![CI](https://github.com/MBakkar2705/traceability-api-dotnet/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/MBakkar2705/traceability-api-dotnet/actions/workflows/ci.yml)

API ASP.NET Core et SQL Server de traçabilité (projet d'apprentissage).

Elle suit le parcours de lots de tomates, de la ferme à l'expédition : fermes, lots, stations et mouvements.

Ce projet est réalisé avec l'assistance de Claude (Anthropic), sous ma supervision.


## État

| Lot | Contenu | État |
|---|---|---|
| 0 | Documentation | Terminé |
| 1 | Base de données (scripts SQL) | Terminé |
| 2a | Procédures stockées et leurs tests | Terminé |
| 2b | Données volumineuses, index, mesures | Terminé |
| 3a | Évolutions SQL pour l'API (lister les fermes et les stations, lire une station, total des lots) | Terminé |
| 3b | API ASP.NET Core : fermes et stations (6 routes) | Terminé |
| 3c | API ASP.NET Core : lots (4 routes) | Terminé |
| 4a | Interface web (React) : lecture, 5 écrans, et CORS de l'API | Terminé |
| 4b | Interface web : écriture (formulaires, erreurs par champ) | Terminé |
| 5 | Optimisation de la liste des lots (total, dernière page, index, mesures) | Terminé |
| 6 | Intégration continue (GitHub Actions) : SQL Server en conteneur, tests C# et interface à chaque push et pull request, `main` protégée | Terminé |
| 7 | SQL Server en conteneur Docker : base reconstruite par les scripts, API et interface essayées à la main (fermes seulement) | Terminé |
| 8 | L'API dans une image Docker (`Dockerfile`) : image construite, lancée avec SQL Server en conteneur, interface essayée (fermes seulement) | Terminé |
| 9 | CI dédiée : image Docker construite par la CI, scripts `006` et `012` rejoués (une erreur met la CI au rouge), `SQLCMDPASSWORD` limité aux étapes `sqlcmd`, actions fixées par empreinte, badge, `docker` exigé pour fusionner | Terminé |
| 10a | Pseudo annuaire Keycloak 26.6.2 (OAuth 2.0 et OpenID Connect) : realm, rôles `reader` et `writer` et client d'essai importés depuis `identity/traceability-realm.json`, jetons obtenus par deux comptes d'essai, dans Docker et sous Windows (JDK 21). L'API n'est pas modifiée | Terminé |
| 10b | L'API vérifie les jetons de Keycloak (signature, émetteur, expiration, public visé `traceability-api`) et applique les rôles : `reader` ou `writer` pour les 5 routes `GET`, `writer` pour les 5 routes `POST` ; 55 tests ajoutés (faux schéma d'authentification), essais à la main avec de vrais jetons dans Docker puis sous Windows. L'interface reçoit 401 jusqu'au lot 10c | Terminé |
| 10c | La connexion dans l'interface web : écran « Connexion », flux code d'autorisation avec PKCE (bibliothèque `oidc-client-ts`), client Keycloak `traceability-web`, jeton gardé en mémoire, renouvelé automatiquement et envoyé à l'API ; boutons et formulaires d'écriture cachés sans le rôle `writer` ; 70 tests de l'interface et 1 test CORS ajoutés (connexion simulée), essais à la main avec Keycloak dans Docker puis sous Windows | Terminé |
| 11 | L'auteur de chaque mouvement : colonnes `AuthorId` et `AuthorName` dans `Movement` (migration `018`), lues dans le jeton par l'API (`sub` et `preferred_username`), colonne « Auteur » dans l'interface, valeur de remplacement « Données initiales » pour les anciens mouvements ; 10 tests unitaires, 6 tests d'intégration, 9 tests de procédures (`006`) et 2 tests d'interface ajoutés, essais à la main avec un vrai jeton de Keycloak et trois casses volontaires | Terminé |
| 12a | La correction des mouvements : table `trace.MovementCorrection` (migration `019`), procédures `ReplaceMovement` et `CancelMovement`, rôle Keycloak `supervisor`, 2 routes (`replace` et `cancel`), interface (valeurs valables avec « saisie : … », mouvements annulés barrés, historique des corrections, section « Corriger un mouvement », message à copier pour le destinataire d'un lot expédié) ; `003` à 31 tests, `006` à 88 tests, 301 tests C#, 297 tests de l'interface, essais à la main avec Keycloak (voir l'[ADR 0016](docs/adr/0016-correction-des-mouvements.md)) | Terminé (le point sur la visibilité du nom de l'auteur d'une correction est reporté au plan du lot 12b, voir l'[ADR 0016](docs/adr/0016-correction-des-mouvements.md)) |

## Technologies

ASP.NET Core (.NET 10), ADO.NET (`Microsoft.Data.SqlClient`), Swagger UI, SQL Server 2025, procédures stockées T-SQL, xUnit, Git et GitHub. Interface web : React, TypeScript, Vite, Tailwind CSS, React Router, Vitest et React Testing Library, Oxlint (voir l'[ADR 0006](docs/adr/0006-interface-web-vite-react.md)). Intégration continue : GitHub Actions (lot 6, voir l'[ADR 0009](docs/adr/0009-integration-continue-github-actions.md)). Conteneurs : Docker (lots 7 et 8, voir l'[ADR 0011](docs/adr/0011-api-dans-une-image-docker.md)). Identification : Keycloak (lot 10a, voir l'[ADR 0012](docs/adr/0012-keycloak-serveur-d-identification.md)), jetons vérifiés par l'API avec `Microsoft.AspNetCore.Authentication.JwtBearer` (lot 10b, voir l'[ADR 0013](docs/adr/0013-jetons-keycloak-et-roles-dans-l-api.md)).

## Documentation

- [Documentation fonctionnelle](docs/fonctionnel.md) : ce qu'on trace et les règles métier.
- [Modèle de données](docs/modele-de-donnees.md) : tables, colonnes et contraintes.
- [Contrat des procédures](docs/procedures.md) : paramètres, contrôles et erreurs des 12 procédures.
- [Vérification](docs/verification.md) : ce qui a été exécuté et observé, et ce qui ne l'est pas encore.
- [Mesures des lots 2b, 3a et 5](docs/mesures.md) : hypothèses écrites avant de mesurer, mesures avant et après chaque index, décisions.
- [Glossaire](docs/glossaire.md) : les termes techniques expliqués simplement.
- [ADR 0001](docs/adr/0001-procedures-stockees.md) : règles métier dans des procédures stockées.
- [ADR 0002](docs/adr/0002-tests-sur-base-reelle.md) : tests sur une vraie base SQL Server.
- [ADR 0003](docs/adr/0003-verrou-sur-le-lot.md) : verrou sur le lot pour deux mouvements simultanés.
- [ADR 0004](docs/adr/0004-index-simple-sur-mouvement-par-lot.md) : index simple sur les mouvements par lot.
- [ADR 0005](docs/adr/0005-ado-net-sans-dapper.md) : accès aux données en ADO.NET, sans Dapper.
- [ADR 0006](docs/adr/0006-interface-web-vite-react.md) : interface web en Vite, React et TypeScript.
- [ADR 0007](docs/adr/0007-cors-dans-l-api.md) : CORS dans l'API, plutôt qu'un proxy de développement.
- [ADR 0008](docs/adr/0008-listbatches-page-avant-jointure-total-recompile.md) : `ListBatches` : page découpée avant la jointure, total refait à chaque appel, index sur la ferme.
- [ADR 0009](docs/adr/0009-integration-continue-github-actions.md) : intégration continue avec GitHub Actions : SQL Server en conteneur (authentification SQL), déclenchement à chaque push et pull request, runner et actions fixés. Les changements du lot 9 sont dans ses notes.
- [ADR 0010](docs/adr/0010-protection-de-main-par-ruleset.md) : protection de `main` par un ruleset GitHub : pull request obligatoire, vérifications `backend` et `frontend` exigées (`docker` ajoutée au lot 9, voir ses notes).
- [ADR 0011](docs/adr/0011-api-dans-une-image-docker.md) : l'API dans une image Docker, construite par un `Dockerfile` à la racine ; environnement et secrets donnés au lancement. La CI construit l'image depuis le lot 9 (voir ses notes).
- [ADR 0012](docs/adr/0012-keycloak-serveur-d-identification.md) : Keycloak comme serveur d'identification (OAuth 2.0 et OpenID Connect), réglages gardés dans `identity/traceability-realm.json`, essayé dans Docker et sous Windows.
- [ADR 0013](docs/adr/0013-jetons-keycloak-et-roles-dans-l-api.md) : l'API vérifie les jetons de Keycloak (signature, émetteur, expiration, public visé) et applique les rôles `reader` et `writer`.
- [ADR 0014](docs/adr/0014-connexion-dans-l-interface-web-pkce-et-jeton-en-memoire.md) : l'interface web se connecte avec le flux code d'autorisation et PKCE, garde le jeton en mémoire et le renouvelle automatiquement.
- [ADR 0015](docs/adr/0015-auteur-des-mouvements.md) : chaque mouvement enregistre son auteur (identifiant du compte et nom d'utilisateur), lu dans le jeton ; l'API ne renvoie que le nom.
- [ADR 0016](docs/adr/0016-correction-des-mouvements.md) : un mouvement ne se modifie pas, il se corrige par une ligne de plus dans `MovementCorrection` ; un rôle `supervisor` corrige, le message pour le destinataire d'un lot expédié est affiché par l'interface web seulement.

## Ce que ce projet ne prouve pas

- Il ne représente aucun système réel : le scénario est simplifié et inventé.
- Pour chaque lot, tout n'est pas prouvé : les listes sont dans [docs/verification.md](docs/verification.md), sections 4, 6.4, 7.3, 8.3, 9.3, 10.3, 11.3, 12.3, 13.3, 14.8, 15.3, 16.3, 17.3, 18.3, 19.3, 20.3, 21.3 et 22.3. Chaque liste date de son lot : un point peut avoir été réglé depuis, et la preuve est alors dans la section « Ce qui est prouvé » du lot concerné.
- La CI (lot 6) prouve que les 163 tests C# et les 178 tests de l'interface passent sur une machine vierge en authentification SQL, et qu'un test en échec bloque la fusion. Elle ne prouve ni l'authentification Windows, ni les scripts `006` et `012` (rejoués par la CI depuis le lot 9), ni une pull request venue d'un fork (le secret n'y serait pas transmis), ni la migration annoncée d'`ubuntu-latest`, ni le lancement à la main de l'application contre un SQL Server en conteneur. Son moteur SQL Server est plus récent que celui de la machine de développement (17.0.5035.5 contre 17.0.1145.4).
- Le lot 7 prouve que l'application, lancée à la main, lit et écrit les fermes dans un SQL Server 2025 en conteneur (authentification SQL, une seule machine). Il ne prouve ni les lots, les stations et les mouvements dans ce conteneur, ni les données volumineuses, ni l'authentification Windows, ni l'application dans un conteneur, essayée au lot 8 (voir [docs/verification.md](docs/verification.md), section 15).
- Le lot 8 prouve que l'image de l'API se construit et que l'API en conteneur lit et écrit les fermes dans SQL Server en conteneur, avec l'interface web. Il ne prouve ni les stations, les mouvements ou la création d'un lot dans ce montage, ni le HTTPS, ni un coffre à secrets, ni que le `Dockerfile` reste valable : la CI ne le construisait pas à ce lot, elle le construit depuis le lot 9 (voir [docs/verification.md](docs/verification.md), sections 16 et 17, et l'[ADR 0011](docs/adr/0011-api-dans-une-image-docker.md)).
- Le lot 9 prouve que la CI construit l'image de l'API (tâche `docker`, sans la lancer) et que, dans les essais jetables, un `Dockerfile` cassé rend la CI rouge, que `006` rejoué par la CI la rend rouge quand une règle d'une procédure est cassée, et qu'avec `docker` exigé par `protect-main` le bouton de fusion d'une pull request au `Dockerfile` cassé est grisé. Il ne prouve ni le contenu des tests « à vérifier à l'œil » (un seul cas essayé : un test C# l'a détecté, pas `012`), ni une règle cassée vue par `012`, ni le démarrage de l'image dans la CI ou son envoi dans un registre, ni la mise à jour future des empreintes des actions, ni un badge « failing » (voir [docs/verification.md](docs/verification.md), sections 17.3 et 17.4).
- Le lot 10a prouve que Keycloak 26.6.2 démarre dans Docker et sous Windows (JDK 21 à côté du Java 24), qu'il recrée depuis `identity/traceability-realm.json` le realm, les rôles `reader` et `writer` et le client d'essai, et que deux comptes créés à la main obtiennent un jeton contenant leur rôle. Il ne prouve ni que l'API vérifie un jeton ou applique un rôle (lot 10b), ni la connexion dans l'interface web (lot 10c), ni le mode de production, le HTTPS, une base externe, ni la conservation des comptes, ni un mot de passe d'administrateur permanent (voir [docs/verification.md](docs/verification.md), sections 18.3 et 18.4, et l'[ADR 0012](docs/adr/0012-keycloak-serveur-d-identification.md)).
- Le lot 10b prouve que l'API refuse un appel sans jeton valide (401) et applique les rôles (403 pour un `reader` qui écrit), avec de vrais jetons de Keycloak dans Docker et, pour les contrôles principaux, sous Windows, et par des tests automatiques qui n'utilisent aucun vrai jeton. Il ne prouve ni l'API dans un conteneur avec Keycloak, ni le mode de production et le HTTPS, ni la révocation d'un jeton, ni la cause du délai d'environ 5 minutes avant le refus d'un jeton expiré, ni la connexion dans l'interface web (lot 10c) : en attendant, l'interface reçoit 401 (voir [docs/verification.md](docs/verification.md), sections 19.3 et 19.4, et l'[ADR 0013](docs/adr/0013-jetons-keycloak-et-roles-dans-l-api.md)).
- Le lot 10c prouve que l'interface web se connecte à Keycloak par le flux code d'autorisation avec PKCE (dans Chrome, avec Keycloak dans Docker puis, pour les contrôles principaux, sous Windows), envoie le jeton à l'API, ne le stocke pas dans le navigateur, le renouvelle automatiquement (deux renouvellements observés à 4 minutes d'intervalle) et cache l'écriture sans le rôle `writer` ; un compte sans rôle voit le message du 403 de l'API. Il ne prouve ni le moyen exact du renouvellement (déduit, non lu), ni un renouvellement qui échoue, ni la déconnexion quand Keycloak est injoignable, ni plusieurs onglets, un autre navigateur, le mode de production et le HTTPS, ni l'enregistrement de l'auteur de chaque mouvement (voir [docs/verification.md](docs/verification.md), sections 20.3 et 20.4, et l'[ADR 0014](docs/adr/0014-connexion-dans-l-interface-web-pkce-et-jeton-en-memoire.md)).
- Le lot 11 prouve que chaque mouvement enregistre l'auteur lu dans un vrai jeton de Keycloak (identifiant du compte et nom d'utilisateur, comparés à la console de Keycloak), que l'interface affiche son nom et « Données initiales » pour les anciens mouvements, qu'un jeton valide sans nom d'utilisateur ne peut pas écrire (403) et que trois casses volontaires sont vues par les tests (dans Edge, avec Keycloak dans Docker, l'API sur `TraceabilityTest`, puis `TraceabilityDev` en lecture). Il ne prouve ni une règle de visibilité du nom (tous les rôles qui lisent le voient), ni un jeton sans `sub`, ni que `007` et `016`, modifiés, tournent (jamais rejoués), ni la durée de l'exécution réelle de `018`, ni la cause d'un échec isolé d'un test de l'interface (voir [docs/verification.md](docs/verification.md), sections 21.3 et 21.4, et l'[ADR 0015](docs/adr/0015-auteur-des-mouvements.md)).
- Le lot 12a prouve qu'un compte `supervisor` corrige et annule des mouvements (avec de vrais jetons de Keycloak, par l'API puis dans l'interface, le journal `Movement` restant intact en base), que `writer` et `reader` sont refusés, que neuf refus essayés ne changent rien, que le verrou fait attendre la seconde de deux sessions SQL, que des heures en UTC sont envoyées avec un `Z`, et que trois casses volontaires sont vues par les tests. Il ne prouve ni deux appels HTTP lancés en même temps sur le même lot, ni `019`, `005` et `017` rejoués sur `TraceabilityDev`, ni la CI sur ce lot, ni l'interface dans un autre navigateur ou avec un jeton qui expire pendant une correction, ni que le message pour le destinataire est transmis (rien ne l'enregistre, et seule l'interface web le propose), ni une règle de visibilité du nom de l'auteur d'une correction (voir [docs/verification.md](docs/verification.md), sections 22.3 et 22.4, et l'[ADR 0016](docs/adr/0016-correction-des-mouvements.md)).
- Le CORS n'est configuré que pour le serveur de développement de l'interface (`http://localhost:5173`, `GET` et `POST`). L'interface a été vue dans Edge (lots 4 à 8) et dans Chrome (lot 10c). Le bouton « Fin » de la liste des lots a été accéléré au lot 5, mais la correction de ses échecs n'est pas prouvée (voir [docs/verification.md](docs/verification.md), section 13.3). Une observation hors protocole du 2026-10-23 montre, avec un budget de mémoire de 5 Mo, l'ancienne requête de la dernière page en attente de sa mémoire pendant que la nouvelle répondait en moins d'une seconde ([docs/mesures.md](docs/mesures.md), section 9.7) : elle ne démontre pas la cause des échecs d'origine. Swagger UI décrit les 10 routes et leurs erreurs, mais son exemple d'erreur n'affiche pas les champs ajoutés par l'API (`errorCode`, `errors`).
- Les mesures des lots 2b et 5 portent sur un million de lots inventés et une seule machine : elles ne disent rien d'un autre volume ni d'une autre machine ; le coût en écriture n'est mesuré que pour `IX_Batch_FarmId` (voir [docs/mesures.md](docs/mesures.md), sections 5 et 9.4).
- Il donne une base de travail, pas une expérience de production.

## Hors périmètre et suite

### Hors périmètre

Ce sont des choses qui se font en entreprise, mais elles sont hors périmètre de ce projet d'apprentissage :

- l'interfaçage avec un ERP, un DataWarehouse et des outils BI ;
- la livraison et le déploiement continus (le « CD » de CI/CD) et la mise en production ;
- le support applicatif de niveau 2 ;
- la découpe ou la fusion de lots.

### À faire ou à prendre en compte

Ces points ne sont pas planifiés dans un lot : ce sont des intentions, pas des promesses.

- la gestion des utilisateurs et des droits : le serveur d'identification (10a), la vérification des jetons par l'API avec les rôles (10b) et la connexion dans l'interface web (10c) sont essayés ; l'auteur de chaque mouvement est enregistré depuis le lot 11, mais qui peut voir son nom n'est pas réglé, pour les mouvements comme pour les corrections (voir l'[ADR 0015](docs/adr/0015-auteur-des-mouvements.md) et l'[ADR 0016](docs/adr/0016-correction-des-mouvements.md)) ;
- la correction de la fiche d'un lot (variété, date de récolte, ferme) et de son code : lot 12b, pas commencé ; la correction des mouvements est faite au lot 12a (voir l'[ADR 0016](docs/adr/0016-correction-des-mouvements.md)) ;
- les retours de marchandise ;
- l'archivage ou la purge des anciennes données ;
- des données et des écrans de contrôle qualité : le modèle n'a aucune donnée de ce genre, et le métier est à connaître avant de les concevoir ;
- essayer React Router 8.5.0 : elle demande Node 22.22.0 ou plus, ce que la version installée (22.23.4) permet ; non essayée (voir l'[ADR 0006](docs/adr/0006-interface-web-vite-react.md)) ;
- des tests d'interface qui pilotent un vrai navigateur, et un essai sur un vrai téléphone ;
- le journal de l'API écrit comme une erreur grave un appel que le navigateur a annulé (observé au lot 4a) ;
- un index sur le statut des lots : le total et la page de `RECEIVED` lisent encore 10 574 et 9 351 pages (voir [docs/mesures.md](docs/mesures.md), sections 9.5 et 9.6) ;
- une pagination par clé (reprendre après le dernier numéro de lot vu) plutôt que par numéro de page : la dernière page lit toujours toute la table (10 424 pages) ; cela changerait le contrat de l'API et de l'interface ;
- reproduire à volonté les échecs du bouton « Fin » (par exemple en limitant la mémoire de SQL Server) pour prouver la correction, et essayer « Fin » dans l'interface web, pas seulement par l'API ;
- un cahier de scénarios fonctionnels (une recette) : créer une ferme, créer un lot, le faire avancer jusqu'à l'expédition, avec un maximum de scénarios, y compris les refus. Il pourra être rejoué à la main, puis automatisé en partie une fois l'interface web faite.

## Démarrage

### Base de données (lots 1, 2a, 2b, 3a, 5, 11 et 12a)

Prérequis : SQL Server 2025 et SQL Server Management Studio (SSMS).

1. Se connecter à l'instance locale (`localhost`) avec l'authentification Windows. Dans cette configuration locale, « Certificat de serveur de confiance » est coché : acceptable seulement en local, jamais pour un serveur distant.
2. Activer le **mode SQLCMD** dans chaque fenêtre de requête : menu Requête > Mode SQLCMD. C'est une bascule propre à chaque fenêtre : si le mode est déjà actif, ne pas cliquer (cela le désactiverait). Sans ce mode, le nom de la base n'est pas remplacé : le script affiche des erreurs ou est arrêté par sa garde, sans rien créer.
3. Choisir la base : en haut de chaque script, la ligne `:setvar DbName ...` donne le nom (`TraceabilityDev` par défaut). Pour la base de test, remplacer par `TraceabilityTest` sans enregistrer le changement. Le script de remise à zéro (`900`) n'accepte que ces deux noms.
4. Exécuter dans l'ordre les scripts du dossier `database/` :
   - `001_create_database.sql` : crée la base (rejouable).
   - `002_create_schema_and_tables.sql` : crée le schéma `trace` et les 6 tables (non rejouable : il échoue si elles existent déjà).
   - `003_check_schema.sql` : inspecte la structure et lance des tests de refus, annulés à la fin (rejouable sur une base vide).
   - `004_create_reference_procedures.sql` : crée `CreateFarm`, `CreateStation` et `AddStationCapability` (écrit avec `CREATE OR ALTER`, donc conçu pour être rejoué).
   - `005_create_batch_procedures.sql` : crée `CreateBatch`, `AddMovement`, `ReplaceMovement`, `CancelMovement`, `GetBatch` et `ListBatches` (même principe ; `ListBatches` renvoie aussi le total depuis le lot 3a).
   - `006_check_procedures.sql` : 88 tests des procédures (81 automatiques et 7 dont le contenu se vérifie à l'œil), uniquement sur `TraceabilityTest` (le mode SQLCMD n'est pas nécessaire). Rejouable, mais il laisse ses lignes dans la base : ne pas relancer `003` ensuite sans reconstruire.
   - `007_generate_volume_data.sql` : génère les lots et leurs mouvements inventés dans `TraceabilityDev` (réglage `@TargetLots` en haut du script : 10 000 pour un échantillon, 1 000 000 pour le jeu complet, sans enregistrer le changement). Reprenable. Le mode SQLCMD n'est pas nécessaire.
   - `008_check_volume_data.sql` : 28 contrôles des données générées, en lecture seule (sans SQLCMD).
   - `009_measure_searches.sql` : mesure les recherches de l'API, en lecture seule (sans SQLCMD). Il exige le million de lots et les procédures de `004` et `005` ; activer le plan d'exécution réel (Ctrl+M).
   - `010_create_indexes.sql` : crée l'index retenu, `IX_Movement_BatchId`. Rejouable (sans SQLCMD).
   - `011_create_list_procedures.sql` : crée `ListFarms`, `ListStations` et `GetStation` (lot 3a). Même principe que `004` et `005` (`CREATE OR ALTER`, mode SQLCMD) : à lancer sur `TraceabilityDev` et sur `TraceabilityTest`.
   - `012_check_list_procedures.sql` : 16 tests des trois procédures, uniquement sur `TraceabilityTest` (sans SQLCMD) : 10 automatiques et 6 dont le contenu se vérifie à l'œil (voir [docs/verification.md](docs/verification.md), section 8). Il supprime d'abord les lignes `ZY-…` d'un passage précédent.
   - `013_measure_lot5.sql` : mesure le total et la dernière page de `ListBatches` (lot 5), en lecture seule (sans SQLCMD) ; activer le plan d'exécution réel (Ctrl+M) pour les blocs A, le désactiver pour les blocs B.
   - `014_measure_lot5_trials.sql` : essais G1 et G2 du lot 5, en lecture seule (son seul `INSERT` écrit dans des variables de type table qui disparaissent à la fin du lot). Sans SQLCMD.
   - `015_measure_lot5_t2.sql` : mesures de l'essai d'index pour le total, en lecture seule (sans SQLCMD).
   - `016_measure_lot5_costs.sql` : coûts de l'index et du plan refait à chaque appel. **Son bloc W1 écrit dans la base** (appels de `CreateBatch`, chaque série annulée) ; les autres blocs sont en lecture seule. Sans SQLCMD.
   - `017_optimize_list_batches.sql` : crée `IX_Batch_FarmId` s'il n'existe pas et remplace `ListBatches` (lot 5, [ADR 0008](docs/adr/0008-listbatches-page-avant-jointure-total-recompile.md)). Même principe que `011` (`CREATE OR ALTER`, mode SQLCMD) : à lancer sur `TraceabilityDev` et sur `TraceabilityTest`, API arrêtée.
   - `018_add_movement_author.sql` : ajoute `AuthorId` et `AuthorName` à `trace.Movement` d'une base qui existe déjà (lot 11, [ADR 0015](docs/adr/0015-auteur-des-mouvements.md)). Mode SQLCMD, une seule transaction, **essai à blanc par défaut** (`@keep = N'NO'` : tout est annulé à la fin ; ne pas enregistrer le passage à `YES`). Rejouable : si les colonnes existent, il ne fait rien. À lancer sur `TraceabilityDev` et sur `TraceabilityTest`, API arrêtée, puis rejouer `005` et `017`. Une base neuve reçoit les colonnes par `002` ; la CI ne rejoue pas `018`.
   - `019_add_movement_correction.sql` : crée la table `trace.MovementCorrection` dans une base qui existe déjà (lot 12a, [ADR 0016](docs/adr/0016-correction-des-mouvements.md)). Mode SQLCMD, une seule transaction, rejouable (si la table existe, il ne fait rien) ; il ajoute une table vide et un index, sans toucher aux autres tables. À lancer, puis rejouer `005` et `017`, API arrêtée. Il n'a été lancé que sur `TraceabilityTest` ; la décision de le lancer sur `TraceabilityDev` n'est pas prise. Une base neuve reçoit la table par `002` ; la CI ne rejoue pas `019`.
   - `901_trial_data_lot12a.sql` : crée les données de l'essai de l'interface du lot 12a (une ferme, trois stations, un lot expédié et un lot trié), uniquement sur `TraceabilityTest` (sans SQLCMD) ; le préfixe des codes se change en haut du script, sans enregistrer le changement.
5. Pour repartir de zéro : `900_reset_dev_database.sql` supprime la base indiquée par `:setvar DbName`. Il est verrouillé : il ne fait rien tant que `@confirm` n'est pas changé en `YES` (ne pas enregistrer ce changement). Puis rejouer `001` à `005`, `011` et `017` (et `006` et `012` pour la base de test).

Si SSMS souligne en rouge des procédures « introuvables » alors qu'elles existent, actualiser le cache de l'IntelliSense (Ctrl+Maj+R) : c'est arrivé aux lots 2a et 3a, et le compteur d'erreurs est retombé à 0.

L'essai du verrou de l'ADR 0003 se fait à la main, avec deux fenêtres SSMS : le déroulé et le résultat sont dans [docs/verification.md](docs/verification.md), section 6.3.

### API (lots 3b et 3c)

Prérequis : le SDK .NET 10 (10.0.402 observé), les deux bases du lot précédent (`TraceabilityDev` avec ses données, `TraceabilityTest` avec les procédures `004`, `005` et `011`), l'authentification Windows. Toutes les commandes sont à lancer dans PowerShell, depuis la racine du dépôt.

1. Certificat HTTPS de développement, une seule fois : `dotnet dev-certs https --trust`. Windows affiche une fenêtre de confirmation : elle concerne le certificat de développement créé par .NET pour `localhost`.
2. Variables d'environnement, une seule fois, au niveau du compte Windows (aucun mot de passe : authentification Windows) :

   ```powershell
   [Environment]::SetEnvironmentVariable("ConnectionStrings__Default", "Server=localhost;Database=TraceabilityDev;Integrated Security=True;TrustServerCertificate=True", "User")
   [Environment]::SetEnvironmentVariable("ConnectionStrings__Test", "Server=localhost;Database=TraceabilityTest;Integrated Security=True;TrustServerCertificate=True", "User")
   ```

   `TrustServerCertificate=True` est nécessaire en local : sans lui, la connexion depuis .NET a échoué avec une erreur de chaîne de certificats (« autorité qui n'est pas approuvée », observé le 2026-10-20). Comme dans SSMS, il est acceptable seulement en local, jamais pour un serveur distant. Un programme déjà ouvert ne voit pas une variable créée après son démarrage : rouvrir VS Code ou ouvrir une nouvelle fenêtre PowerShell.
3. Lancer l'API : `dotnet run --project src/Traceability.Api --launch-profile https`. Elle écoute sur `https://localhost:7080` et lit `ConnectionStrings__Default`. Depuis le lot 10b, elle lit aussi `Authentication__Authority` et `Authentication__Audience` et vérifie les jetons de Keycloak (voir la section Keycloak plus bas). Ouvrir ensuite `https://localhost:7080/swagger` à la main : `dotnet run` n'ouvre pas le navigateur (c'est documenté, pas une panne). Arrêt : Ctrl+C.
4. Les tests : `dotnet test Traceability.slnx`, ou séparément `tests/Traceability.UnitTests` (sans base) et `tests/Traceability.IntegrationTests`. **Attention :** les tests d'intégration vident les 6 tables de `TraceabilityTest` au début de chaque exécution (`DELETE` sans `WHERE`, précédés d'un contrôle du nom de la base) ; ils lisent `ConnectionStrings__Test` et ne touchent jamais `TraceabilityDev`. Les tests remplacent l'authentification par un faux schéma : ils n'ont pas besoin de Keycloak.

Les 12 routes (6 au lot 3b, 4 au lot 3c, 2 au lot 12a) :

| Route | Procédure |
|---|---|
| `POST /farms` | `CreateFarm` |
| `GET /farms?pageNumber=1&pageSize=20` | `ListFarms` |
| `POST /stations` | `CreateStation` |
| `GET /stations?pageNumber=1&pageSize=20` | `ListStations` |
| `GET /stations/{stationCode}` | `GetStation` |
| `POST /stations/{stationCode}/capabilities` | `AddStationCapability` |
| `POST /batches` | `CreateBatch` |
| `GET /batches?status=...&farmCode=...&pageNumber=1&pageSize=20` | `ListBatches` |
| `GET /batches/{batchCode}` | `GetBatch` |
| `POST /batches/{batchCode}/movements` | `AddMovement` |
| `POST /batches/{batchCode}/movements/{movementId}/replace` | `ReplaceMovement` |
| `POST /batches/{batchCode}/movements/{movementId}/cancel` | `CancelMovement` |

Authentification (lot 10b) : chaque route demande un jeton d'accès de Keycloak (`Authorization: Bearer …`). Les routes `GET` acceptent le rôle `reader`, `writer` ou `supervisor`, les routes `POST` qui créent ou saisissent demandent `writer`, et les deux routes de correction (`replace` et `cancel`, lot 12a) demandent `supervisor`. Sans jeton ou avec un jeton invalide, l'API répond 401 ; avec un rôle insuffisant, 403. Dans Swagger UI, le bouton Authorize permet de coller un jeton.

Les listes répondent `items`, `totalCount`, `pageNumber` et `pageSize` ; sans paramètre, la page est la 1 de 20. Les erreurs sont au format Problem Details, avec un champ `errorCode` qui reprend le numéro de la procédure (501xx → 404, 502xx → 409, 503xx → 422, 504xx → 400). Les routes `POST` répondent 201 sans corps, avec un en-tête `Location` vers la station ou le lot. `GET /batches/{batchCode}` renvoie un seul objet : le lot, la liste `movements`, dans l'ordre d'enregistrement (depuis le lot 12a : les valeurs valables, les valeurs d'origine, `isCancelled` et `correctionCount` ; un mouvement annulé reste dans la liste), et la liste `corrections`. Le corps de `replace` est `stationCode`, `quantityKg`, `occurredAt` (en UTC, avec `Z`), `reasonCode` et `reasonComment` ; celui de `cancel` est `reasonCode` et `reasonComment`. Motifs : `DATA_ENTRY_ERROR`, `MEASUREMENT_ERROR`, `OTHER` (commentaire obligatoire).

Formats (observés au lot 3c) : les champs sont en camelCase ; la date de récolte s'écrit `2026-10-14` ; une quantité est un nombre, avec au plus 2 décimales et au plus 99 999 999,99 ; une heure est toujours en UTC : elle doit se terminer par `Z` ou porter un décalage, sinon l'API répond 400 sur `occurredAt`, et les heures renvoyées se terminent par `Z`. L'API refuse (400) un texte plus long que sa colonne (noms, région, variété, type de mouvement, statut) et une quantité que la colonne ne peut pas stocker. Swagger UI décrit les 10 routes, leurs réponses et leurs `errorCode`.

Attention : `GET /batches` calcule le total à chaque appel. Depuis le lot 5, il lit 1 737 pages sans filtre (47 pour une ferme de 25 000 lots) ; le filtre par statut lit encore 10 574 pages (voir [docs/mesures.md](docs/mesures.md), section 9.6). L'interface web appelle cette route à chaque page : la dernière page répond en 0,45 à 1,59 s par l'API (10 appels), mais la correction des échecs observés au lot 4a n'est pas prouvée (voir [docs/verification.md](docs/verification.md), sections 11.3 et 13.3). Les routes `POST` écrivent dans la base que l'API lit : pour des essais à la main, préférer une base de test.

### Interface web (lots 4a, 4b et 10c)

Prérequis : Node.js (v22.23.4 et npm 10.9.9 observés), l'API et ses deux bases (voir la section précédente). Depuis le lot 10c, Keycloak doit aussi tourner et l'API doit être lancée avec ses variables `Authentication__` (section Keycloak plus bas). Les commandes sont à lancer dans PowerShell.

1. Dans un terminal, lancer l'API (étape 3 de la section précédente).
2. Dans un autre terminal, depuis le dossier `web/` : `npm install` (une seule fois), puis `npm run dev`. Vite écoute sur `http://localhost:5173/`. Le port est fixé (`strictPort`) : s'il est pris, le serveur s'arrête avec une erreur au lieu de changer de port, ce qui ferait échouer le CORS (voir l'[ADR 0007](docs/adr/0007-cors-dans-l-api.md)). L'API n'accepte l'interface qu'en développement (environnement `Development`, ce que donne le profil `https`).
3. Autres commandes, dans `web/` : `npm run lint`, `npm run build` (vérifie les types et écrit dans `dist/`, ignoré par git) et `npm test` (297 tests au lot 12a, sans API, sans Keycloak ni base).

L'interface appelle l'API sur `https://localhost:7080` ; la variable d'environnement `VITE_API_URL` remplace cette adresse. Depuis le lot 10c, `VITE_AUTH_AUTHORITY` (par défaut `http://localhost:8180/realms/traceability`) et `VITE_AUTH_CLIENT_ID` (par défaut `traceability-web`) règlent la connexion. Aucun fichier `.env` n'est fourni, et aucune de ces valeurs n'est un secret.

Les 5 écrans de lecture (15 lignes par page) :

| Adresse | Écran |
|---|---|
| `/batches?status=…&farmCode=…&page=…` | liste des lots, avec filtres par statut et par ferme (l'accueil `/` y mène) |
| `/batches/{batchCode}` | un lot et son parcours, les heures en UTC |
| `/farms?page=…` | liste des fermes |
| `/stations?page=…` | liste des stations |
| `/stations/{stationCode}` | une station et ses fonctions |

Les filtres et la page sont dans l'adresse : recharger la page ou revenir en arrière garde l'écran. Les noms de fermes et de stations s'affichent tels qu'ils sont dans la base (en anglais pour les données inventées). Attention : sur le million de lots de `TraceabilityDev`, le bouton « Fin » de la liste des lots a répondu en 1,9 à 11,7 s à quatre essais et a échoué par dépassement de délai (30 s) à trois autres (voir [docs/verification.md](docs/verification.md), section 11.3).

Les écrans d'écriture (lot 4b) : chaque liste a un lien vers la page de création. Les erreurs de l'API s'affichent en français, un seul envoi part à la fois, et les heures se saisissent et s'envoient en UTC.

| Adresse | Écran |
|---|---|
| `/new-farm` | créer une ferme (code, nom, région) ; le message de succès reste sur la page et le formulaire est vidé |
| `/new-station` | créer une station (code, nom) ; ouvre la page de la station |
| `/new-batch` | créer un lot (code, ferme, variété, date de récolte, quantité, station et heure de réception en UTC) ; ouvre la page du lot |
| `/stations/{stationCode}` | en plus : ajouter une fonction (Réception, Tri, Emballage, Expédition) |
| `/batches/{batchCode}` | en plus : ajouter un mouvement (le formulaire propose l'étape suivante et la quantité actuelle) ; un lot expédié n'a plus de formulaire. Pour le rôle `supervisor` (lot 12a), le formulaire d'ajout est remplacé par « Corriger un mouvement » (remplacer les valeurs d'un mouvement, ou annuler le dernier, avec un motif) ; les mouvements corrigés montrent « saisie : … », les mouvements annulés sont barrés, l'historique des corrections s'affiche pour tous les rôles, et, après la correction d'un lot qui était expédié, un message en français à copier pour le destinataire |

Ces écrans écrivent dans la base que l'API utilise. Pour les essayer sans toucher à `TraceabilityDev`, voir [docs/verification.md](docs/verification.md), section 12.4.

Connexion (lot 10c) : tant que personne n'est connecté, l'interface affiche l'écran « Connexion » (un bouton « Se connecter ») et n'appelle pas l'API. Le bouton envoie l'utilisateur à Keycloak (flux code d'autorisation avec PKCE, client `traceability-web`) ; au retour sur `/auth/callback`, l'interface va à l'accueil, et son nom et « Se déconnecter » apparaissent en haut. Le jeton n'est gardé qu'en mémoire : recharger la page déconnecte (Keycloak garde sa session, donc « Se connecter » reconnecte sans mot de passe). Il est renouvelé automatiquement avant son expiration (5 minutes). Sans le rôle `writer`, les boutons et formulaires d'écriture sont cachés et les pages de création affichent un message ; l'API refuse de toute façon l'écriture (403), et un compte sans rôle `reader` ni `writer` voit « Vous n'avez pas le droit de faire cela. » à la place des listes. Si Keycloak est arrêté, l'écran « Connexion » le dit. Constat, limites et hypothèses : [docs/verification.md](docs/verification.md), section 20, et [ADR 0014](docs/adr/0014-connexion-dans-l-interface-web-pkce-et-jeton-en-memoire.md).

### Intégration continue (lots 6 et 9)

La CI est le fichier `.github/workflows/ci.yml` : trois tâches, `backend` (SQL Server 2025 en conteneur, base `TraceabilityTest` reconstruite par les scripts `001`, `002`, `004`, `005`, `011` et `017`, scripts de tests `006` et `012` rejoués, puis `dotnet build` et `dotnet test Traceability.slnx`), `frontend` (Node 22, `npm ci`, lint, build et tests) et `docker` (construction de l'image de l'API avec le `Dockerfile`, sans la lancer ni l'envoyer dans un registre, sans secret). Elle se lance à chaque push et à chaque pull request ; une exécution dure environ une minute.

- **Secret à créer** : `MSSQL_SA_PASSWORD`, un secret de dépôt (réglages de GitHub, Secrets and variables). C'est le mot de passe du compte `sa` du conteneur de la CI : il doit respecter la politique de mot de passe de SQL Server, et il n'est jamais écrit dans le dépôt.
- **Voir et rejouer** : onglet Actions de GitHub ; « Re-run all jobs » dans une exécution, ou un nouveau push.
- **Authentification** : la CI se connecte en authentification SQL (utilisateur `sa`), la machine de développement en authentification Windows. Le code C# ne change pas : seule la chaîne de connexion `ConnectionStrings__Test` diffère.
- **`main` protégée** : le ruleset `protect-main` (un réglage de GitHub, hors du dépôt, voir l'[ADR 0010](docs/adr/0010-protection-de-main-par-ruleset.md)) impose une pull request et les vérifications `backend`, `frontend` et `docker` pour fusionner (`docker` depuis le lot 9).
- **Scripts `006` et `012`** : rejoués par la CI avec `sqlcmd -b` ; ils déclenchent une erreur quand un test est en échec, ce qui met la CI au rouge. Les tests « à vérifier à l'œil » ne sont contrôlés que pour leur forme, pas pour leur contenu.
- **Mot de passe et actions** : dans `ci.yml`, `SQLCMDPASSWORD` n'est défini que sur les étapes qui appellent `sqlcmd`, et les actions de GitHub sont fixées par empreinte de commit.
- **Badge** : sous le titre de ce README, il affiche l'état du dernier run de `main`.

Constat, limites et hypothèses : [docs/verification.md](docs/verification.md), sections 14 et 17, et [ADR 0009](docs/adr/0009-integration-continue-github-actions.md) (notes du lot 9 comprises).

### Docker : SQL Server et API en conteneurs (lots 7 et 8)

Prérequis : Docker Desktop (version 4.81.0 observée). Ces deux lots essaient l'application dans des conteneurs sur le poste de développement. Ils ne remplacent pas le montage décrit plus haut (SQL Server local, `dotnet run`).

- **Lot 7, SQL Server en conteneur** : image `mcr.microsoft.com/mssql/server:2025-latest` (la même que la CI), authentification SQL (utilisateur `sa`), port 14330 côté poste. Les scripts `001`, `002`, `004`, `005`, `011` et `017` reconstruisent la base `TraceabilityDev` dans le conteneur ; l'API et l'interface sont lancées à la main contre lui.
- **Lot 8, l'API en conteneur** : le `Dockerfile`, à la racine du dépôt, construit l'image de l'API. Elle est lancée sur un réseau Docker à côté du conteneur SQL Server, qu'elle joint par son nom (`traceability-sql`).
- **Secrets** : le mot de passe de `sa` est saisi masqué dans PowerShell, et la chaîne de connexion est donnée au conteneur par la variable `ConnectionStrings__Default`. Ni l'image ni le dépôt ne contiennent de mot de passe.
- **Environnement** : un conteneur démarre en `Production`, où Swagger n'existe pas (réponse 404) et où le CORS n'est pas appliqué. Pour essayer Swagger et l'interface web, `ASPNETCORE_ENVIRONMENT=Development` est donné au lancement, et l'interface vise l'API du conteneur avec `VITE_API_URL=http://localhost:8080`.
- **Rejouer** : les commandes complètes, sans mot de passe, sont dans [docs/verification.md](docs/verification.md), sections 15.5 et 16.5.
- **Depuis le lot 10b** : l'API en conteneur a besoin des deux variables `Authentication__` ; elle démarre en `Production`, où le code lit la configuration de Keycloak seulement en HTTPS. L'API en conteneur avec Keycloak n'est pas essayée (19.3).
- **Ce que ce montage n'est pas** : un seul poste, des conteneurs lancés à la main, sans registre d'images ni déploiement, l'API en HTTP seulement, aucun coffre à secrets. Depuis le lot 9, la CI construit l'image (sans la lancer).

Constat, limites et hypothèses : [docs/verification.md](docs/verification.md), sections 15 et 16, et [ADR 0011](docs/adr/0011-api-dans-une-image-docker.md).

### Keycloak : pseudo annuaire, jetons de l'API et connexion de l'interface (lots 10a, 10b et 10c)

Prérequis : Docker Desktop pour le mode Docker ; pour le mode Windows, un JDK 21 et l'archive de Keycloak 26.6.2, extraits d'archives `.zip` (aucun installateur). Keycloak est lancé à la main, en mode développement seulement, sur `127.0.0.1:8180`. Depuis le lot 10b, l'API vérifie ses jetons ; depuis le lot 10c, l'interface web s'y connecte.

- **Réglages** : `identity/traceability-realm.json`, importés au démarrage (`--import-realm`). Le fichier décrit le realm `traceability`, les rôles `reader`, `writer` et `supervisor` (lot 12a) et le client d'essai `traceability-trial` et le client `traceability-web` de l'interface (lot 10c), avec un mappeur qui met `traceability-api` dans le champ `aud` des jetons (lot 10b). Il ne contient aucun utilisateur ni mot de passe. Un realm déjà importé n'est pas réimporté : un Keycloak créé avant le lot 10c est à recréer pour avoir le mappeur et le client `traceability-web` (19.3, 20.5).
- **Comptes et mots de passe** : l'administrateur est donné par des variables d'environnement au lancement, et les comptes `reader-test`, `writer-test`, `supervisor-test` (lot 12a) et `norole-test` (sans rôle, pour voir le refus 403) sont créés à la main dans la console (`http://localhost:8180/admin`). Les mots de passe sont saisis masqués et ne sont écrits dans aucun fichier.
- **L'API** (lot 10b) : deux variables d'environnement, dans la fenêtre qui lance l'API, jamais dans un fichier du dépôt : `Authentication__Authority` (`http://localhost:8180/realms/traceability`) et `Authentication__Audience` (`traceability-api`). L'API refuse tout appel dont le jeton n'est pas émis par ce realm pour ce nom.
- **Rejouer** : les commandes complètes, dans Docker et sous Windows, sont dans [docs/verification.md](docs/verification.md), section 18.5 (Keycloak), section 19.5 (jetons et API) et section 20.5 (interface).
- **Ce que ce montage n'est pas** : un mode de développement (base H2 intégrée, comptes perdus avec le conteneur), en HTTP, avec un administrateur temporaire.

Constat, limites et hypothèses : [docs/verification.md](docs/verification.md), sections 18 à 22, [ADR 0012](docs/adr/0012-keycloak-serveur-d-identification.md), [ADR 0013](docs/adr/0013-jetons-keycloak-et-roles-dans-l-api.md), [ADR 0014](docs/adr/0014-connexion-dans-l-interface-web-pkce-et-jeton-en-memoire.md), [ADR 0015](docs/adr/0015-auteur-des-mouvements.md) et [ADR 0016](docs/adr/0016-correction-des-mouvements.md).
