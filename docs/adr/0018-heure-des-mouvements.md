# ADR 0018 : une heure plus de 5 minutes dans le futur, ou pas dans l'ordre des étapes, est refusée par la base

Statut : **Accepté** (2026-11-20)

## Contexte

Jusqu'au lot 12b, l'heure d'un mouvement n'était pas contrôlée : à la saisie comme à la correction, un mouvement pouvait avoir une heure dans le futur ou antérieure à celle de l'étape précédente ([fonctionnel.md](../fonctionnel.md), section 9). Le parcours d'un lot est pourtant une suite d'étapes dans le temps, et une heure fausse rend l'historique trompeur. Le lot 12c ajoute les contrôles. Il s'applique aux mouvements, donc aux procédures déjà décrites par les [ADR 0003](0003-verrou-sur-le-lot.md) et [0016](0016-correction-des-mouvements.md).

## Décision

- **Futur** : une heure ne peut pas dépasser de plus de 5 minutes l'horloge de SQL Server (`SYSUTCDATETIME()`, lue au moment du contrôle). Erreur **50310**, HTTP 422. Les 5 minutes laissent passer un petit écart entre l'ordinateur de la personne et le serveur. Le message d'erreur de l'API donne l'heure refusée et l'heure du serveur.
- **Ordre** : une heure est strictement après celle de l'étape valable précédente ; pour une correction, elle est aussi strictement avant celle de l'étape valable suivante. Une heure égale est refusée. Erreur **50311**, HTTP 422, un seul numéro pour les deux sens.
- **Étapes valables et voisines** : un mouvement valable est un mouvement non annulé, avec sa dernière correction appliquée. Les voisins sont pris dans l'ordre de `MovementId`, comme pour la quantité ([ADR 0016](0016-correction-des-mouvements.md)). La réception n'a pas d'étape précédente, la dernière étape n'a pas d'étape suivante.
- **Le futur est contrôlé avant l'ordre.** Sur un lot `SHIPPED`, le refus d'un nouveau mouvement (50300) passe avant les deux.
- **Où** : le futur dans `CreateBatch` (heure de réception), `AddMovement` et `ReplaceMovement` ; l'ordre dans `AddMovement` et `ReplaceMovement`. Les règles sont dans les procédures stockées, avec le même verrou `UPDLOCK` sur le lot que le reste, pas seulement dans l'API. `SqlErrorTranslator` ne change pas : la famille 503xx donne déjà 422.
- **`ReplaceMovement` ne contrôle l'heure que si elle change** (`@OccurredAt <> @CurrentTime`) : corriger la station ou la quantité d'un mouvement ne dépend pas d'un vieux désordre.
- **`CancelMovement` ne contrôle rien** : une annulation ne change aucune heure.
- **Une heure passée est acceptée** (saisie tardive) : l'heure dit quand le mouvement a eu lieu, pas quand il a été saisi.
- **Les anciennes données ne sont pas touchées.** `database/021_find_unordered_movements.sql` compte et liste, en lecture seule, les mouvements d'un lot qui ne sont pas dans l'ordre. Rien ne les corrige ni ne les signale dans l'API.
- **L'interface** : deux textes français dans `web/src/lib/messages.ts`. 50310 : « L'heure ne peut pas dépasser de plus de 5 minutes l'heure du serveur. Vérifiez l'heure saisie (elle est en UTC) et l'horloge de votre ordinateur. » 50311 : « L'heure doit être après celle de l'étape précédente et, pour une correction, avant celle de l'étape suivante. »
- **Pas de nouvelle table ni de nouvelle route.** `005` est à rejouer pour avoir les nouvelles règles ; `021` ne modifie rien.
- **Tests** : `006` passe de 122 à 150 tests (142 automatiques, 8 à l'œil) ; 375 tests en C# (118 + 257) et 339 pour l'interface. L'essai à la main avec de vrais jetons est en [verification.md](../verification.md), section 24.

## Alternatives écartées

- **Contrôler l'heure dans l'API seulement.** Non essayée : les règles métier sont dans la base ([fonctionnel.md](../fonctionnel.md), section 5), qui doit les tenir aussi pour un appel qui ne passe pas par l'API.
- **Comparer à l'horloge de l'API plutôt qu'à celle de SQL Server.** Non essayée : les procédures n'ont pas accès à l'horloge de l'API, et une seule horloge sert à tous les contrôles.
- **Aucune tolérance (0 minute).** Non essayée : un ordinateur légèrement en avance ferait refuser une saisie honnête. Le chiffre de 5 minutes est un choix de conception, sans mesure derrière.
- **Refuser aussi les heures passées trop anciennes.** Non essayée : la saisie tardive est un cas réel, et aucune durée limite n'est connue du métier.
- **Contrôler l'heure à chaque remplacement, même inchangée.** Non essayée : un vieux désordre empêcherait de corriger la quantité ou la station d'un mouvement.
- **Deux numéros d'erreur, un par sens de l'ordre.** Non essayée : un seul numéro suffit pour dire « pas dans l'ordre », et l'interface donne un seul texte.
- **Accepter une heure égale à celle de l'étape voisine.** Non essayée : une heure égale ne dit pas laquelle des deux étapes vient avant.
- **Corriger ou signaler automatiquement les anciennes données.** Non essayée : on ne sait pas combien il y en a, et on décidera en fonction du nombre.

## Conséquences

Positives :

- Les règles sont tenues par la base : `006` les teste (150 tests, aucune ligne « ATTENTION »), et elles tiennent aussi pour un appel direct à une procédure.
- Les tests détectent les trois casses essayées dans `005` (le futur dans `AddMovement`, l'ordre suivant dans `ReplaceMovement`, l'heure inchangée dans `ReplaceMovement`), le fichier étant remis à l'identique ([verification.md](../verification.md) 24.3, M17).
- Avec de vrais jetons, par l'API : une heure égale ou hors ordre est refusée (422, 50311), une heure à +10 minutes aussi (422, 50310), rien n'est écrit, et un tri remplacé entre ses deux voisins est accepté (M8 à M12).
- L'interface affiche le texte français à la création d'un lot (50310), à l'ajout d'un mouvement et à la correction (50311) ; après un refus, la page ne relit pas le lot (M13 à M15).

Négatives :

- **La limite exacte de 5 minutes n'est pas prouvée** : +4 minutes acceptées et +6 refusées en SQL, +2 et +10 par l'API.
- **Deux appels simultanés sur le même lot** et **un ordinateur dont l'horloge est en avance de plus de 5 minutes** ne sont pas essayés. Dans le second cas, une saisie honnête est refusée.
- **L'heure ne dit pas quand un mouvement a été saisi** (saisie tardive acceptée).
- **On ne peut pas réordonner les étapes.** Une heure corrigée doit rester entre celles de ses voisines ; pour la sortir de cet intervalle, il faudrait d'abord corriger les voisines. Seul le dernier mouvement valable peut être annulé ([ADR 0016](0016-correction-des-mouvements.md)).
- **Deux étapes à la même heure sont refusées**, même si elles ont eu lieu dans la même minute.
- **Les anciennes données hors ordre restent comme elles sont.** `021` n'a été lancé que sur `TraceabilityTest`, pas sur `TraceabilityDev`, et sa durée sur une grande base n'est pas mesurée.
- **Le texte de 50310 dans les formulaires d'ajout et de correction** n'a été vu que par les tests automatiques de l'interface, pas dans le navigateur.
- **La CI n'est pas encore lue** (M19 de [verification.md](../verification.md)) et n'utilise ni Keycloak ni vrai jeton ; elle ne rejoue pas `020`.

## Notes

- 2026-11-20 : ce document est écrit après l'essai de la section 24 de [verification.md](../verification.md). Les règles ont été validées une à une pendant la préparation du lot, avant l'écriture du code. Les alternatives ci-dessus ont été rédigées en écrivant ce document, aucune n'a été essayée. La ligne M19 (CI) sera complétée après le push.
