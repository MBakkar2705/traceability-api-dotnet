# ADR 0007 : CORS dans l'API, plutôt qu'un proxy de développement

Statut : **Accepté** (2026-10-21)

## Contexte

L'interface web (lot 4a, dossier `web/`) tourne sur `http://localhost:5173`, avec le serveur de développement de Vite, et appelle l'API sur `https://localhost:7080`. Ce sont deux origines différentes (une origine est un schéma, un hôte et un port). Un navigateur ne laisse pas une page lire la réponse d'une autre origine, sauf si cette réponse porte l'en-tête `Access-Control-Allow-Origin` qui nomme l'origine de la page : c'est le CORS. Avant ce lot, l'API n'en avait aucun (voir le README : « non configuré »).

Deux façons de lever le blocage en développement : déclarer l'origine de l'interface dans l'API, ou faire passer les appels par le serveur de développement de Vite (son option `server.proxy`), pour que le navigateur ne parle qu'à une seule origine.

## Décision

- L'API déclare une politique CORS nommée `WebUi`, **appliquée seulement en développement** : origine `http://localhost:5173` (sans `/` final), méthodes `GET` (lot 4a, lecture) et `POST` (lot 4b, écriture) et en-tête `Content-Type`, rien d'autre. `UseCors` est placé entre `UseHttpsRedirection` et `UseAuthorization`.
- Côté Vite, le port 5173 est fixé avec `strictPort: true` : si le port est pris, le serveur s'arrête au lieu de changer de port, ce qui changerait l'origine et ferait échouer le CORS sans message clair.
- Au lot 4b, la politique accepte aussi `POST` et l'en-tête `Content-Type` (`WithMethods("GET", "POST")` et `WithHeaders("Content-Type")`). Prouvé par les tests d'intégration ; l'essai dans Edge reste à faire (voir « Non observé »).

Cette option prouve la vraie chaîne navigateur, CORS, API, avec des tests.

## Alternatives écartées

- **Le proxy de développement de Vite.** Le navigateur ne parlerait qu'à l'origine de l'interface : aucun CORS à configurer ni à tester en C#. En contrepartie, il n'existe que pendant le développement, et l'API resterait « CORS non configuré, non prouvé ». Non essayé.
- **Autoriser toutes les origines** (`AllowAnyOrigin`) : n'importe quelle page web pourrait lire les réponses de l'API depuis un navigateur. Non essayé.

## Conséquences

Positives :

- 8 tests d'intégration par HTTP (`CorsTests`) : l'origine autorisée reçoit l'en-tête, une autre origine non, une requête sans origine non, une erreur 404 écrite par le gestionnaire d'exceptions garde l'en-tête, une pré-vérification pour `POST` avec `Content-Type` autorise les deux, une pré-vérification ne liste ni `PUT` ni `DELETE`, un `POST` réel reçoit l'en-tête (201), et un `POST` refusé en 400 le garde aussi (sans cela, le navigateur cacherait à la page les erreurs par champ).
- Observé au lot 4b : avant la modification, le test de pré-vérification échouait (`Allow-Methods` valait `GET`) ; après, les 8 tests de CORS et les 162 tests C# de la solution réussissent. Les 2 tests de `POST` réel réussissaient déjà avant : sur une requête réelle, l'API met `Allow-Origin` quelle que soit la méthode listée ; seule la pré-vérification regarde la liste.
- Casse volontaire (lot 4a, sur les 5 tests de l'époque) : avec l'origine changée en `http://localhost:5174`, 4 tests sur 5 échouent. Le cinquième (« sans origine ») réussit même sans CORS : il ne prouve rien seul.
- Observé dans Edge, sur `TraceabilityDev` : les 5 écrans de lecture (fermes, stations, détail d'une station, lots, détail d'un lot) lisent l'API réelle. Avec l'API arrêtée, la console dit `ERR_CONNECTION_REFUSED` : ce n'est pas un blocage CORS.

Négatives :

- Le CORS n'est pas une protection : « `GET` seulement » veut dire que le navigateur ne laissera pas la page lire autre chose, pas que l'API refuse un `POST`.
- Observé (lot 4a, politique `GET` seulement) : la réponse à une pré-vérification pour `POST` contient `Access-Control-Allow-Origin` (l'origine) et `Access-Control-Allow-Methods: GET`. La page de Microsoft lue pendant le lot disait qu'une pré-vérification refusée n'a aucun en-tête : ce n'est pas ce qu'on observe avec cette version de .NET. Deux hypothèses de Claude fondées sur cette phrase ont été corrigées par l'observation (voir [verification.md](../verification.md), section 11).
- La politique n'existe qu'en développement. Le déploiement est hors périmètre : l'origine d'un autre environnement n'est pas définie.
- L'origine est écrite dans le code, pas dans une configuration.

Non observé : un autre navigateur que Edge, et ce que fait Edge d'une pré-vérification pour `POST` (essai de l'étape 5 du lot 4b ; les tests C# lisent les en-têtes, ils ne montrent pas ce que fait le navigateur).

## Notes

- 2026-10-21 : décision au lot 4a, avant l'écriture du code. Observé : les 159 tests C# passent (154 existants et 5 de CORS) et l'interface lit l'API dans Edge.
- 2026-10-22 : lot 4b, étape 1 : la politique accepte `POST` et `Content-Type`. Observé : le test de pré-vérification échouait avant (`["GET"]`), les 8 tests de CORS et les 162 tests C# réussissent après.
