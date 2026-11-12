# ADR 0016 : un mouvement ne se modifie pas, il se corrige par une ligne de plus, faite par un rôle `supervisor`

Statut : **Accepté** (2026-11-12)

## Contexte

Un mouvement saisi peut être faux : une erreur de frappe, une balance mal tarée, un mouvement noté sur le mauvais lot. Jusqu'au lot 11, on ne pouvait rien y faire : `Movement` est un journal où l'on n'ajoute que des lignes ([ADR 0015](0015-auteur-des-mouvements.md)), et seuls `CreateBatch` et `AddMovement` y écrivent. Le lot 12a ajoute la correction des mouvements. La correction de la fiche du lot (variété, date de récolte, ferme) et de son code est le lot 12b : elle n'est pas commencée. L'essai et ses résultats sont dans [verification.md](../verification.md), section 22.

## Décision

- **Le journal `Movement` n'est jamais modifié.** Une correction est une ligne de plus dans une table à part, `trace.MovementCorrection` : le mouvement d'origine reste tel qu'il a été saisi, et l'historique des corrections reste lisible.
- **Deux sortes de corrections.** `REPLACE` donne de nouvelles valeurs (station, quantité, heure) ; le type du mouvement ne change pas. `CANCEL` dit que le mouvement n'a pas eu lieu ; sa ligne répète les valeurs de la version annulée. **La version valable** d'un mouvement est sa ligne du journal avec la dernière correction appliquée (plus grand `CorrectionId`). Une annulation est définitive.
- **Règles**, contrôlées dans les procédures `ReplaceMovement` et `CancelMovement` :
  - la quantité corrigée reste entre celle de l'étape valable précédente et celle de l'étape valable suivante, l'égalité étant acceptée (50304) ; la réception n'a pas d'étape avant elle, et la dernière étape n'a pas de limite basse, sauf d'être supérieure à 0 ;
  - la station doit avoir la fonction du mouvement ;
  - des valeurs identiques à la version valable sont refusées (50308) ;
  - seul le dernier mouvement valable peut être annulé (50306), jamais la réception (50307), parce qu'un lot a toujours sa réception et n'est jamais supprimé ;
  - un mouvement annulé ne peut plus être corrigé ni annulé (50305) ;
  - un mouvement qui n'est pas dans le lot donné est refusé (50103).
- **Le statut et la quantité du lot suivent la version valable** : le lot est `SHIPPED` seulement si son dernier mouvement valable est une expédition ; annuler l'expédition le ramène à `PACKED`. `Batch` reste l'état actuel, `Movement` et `MovementCorrection` gardent l'histoire.
- **Un motif est obligatoire** : `DATA_ENTRY_ERROR`, `MEASUREMENT_ERROR` ou `OTHER` (50407 si le motif est inconnu). Le commentaire, de 500 caractères au plus (50409), est obligatoire pour `OTHER` (50408).
- **L'auteur de la correction** est lu dans le jeton comme pour les mouvements ([ADR 0015](0015-auteur-des-mouvements.md)) : `AuthorId` et `AuthorName`, contrôlés par les erreurs 50405 et 50406. Une correction garde aussi sa date (`CorrectedAt`, en UTC).
- **Les procédures prennent le même verrou `UPDLOCK` sur le lot que `AddMovement`** ([ADR 0003](0003-verrou-sur-le-lot.md)) : une correction et un ajout de mouvement ne s'exécutent pas en même temps sur le même lot.
- **Un nouveau rôle Keycloak, `supervisor`**, qui lit et corrige, et ne saisit pas de mouvement. Les règles de l'API : lecture pour `reader`, `writer` et `supervisor` ; écriture (ajout de mouvement) pour `writer` ; correction pour `supervisor`. Le rôle est dans `identity/traceability-realm.json` ; les comptes de l'essai sont créés à la main.
- **Deux routes** : `POST /batches/{batchCode}/movements/{movementId}/replace` et `.../cancel`, qui répondent 201. Les erreurs gardent les familles des autres : 501xx donne 404, 502xx 409, 503xx 422, 504xx 400.
- **`GetBatch` renvoie trois tableaux** : le lot, ses mouvements (valeurs valables, valeurs d'origine, état annulé, nombre de corrections) et l'historique des corrections.
- **L'interface** montre les valeurs valables avec « saisie : … » pour la valeur d'origine, les mouvements annulés barrés, l'historique des corrections avec leur auteur, et, pour le rôle `supervisor` seulement, la section « Corriger un mouvement ». Un refus de l'API qui a un code d'erreur s'affiche en français dans une alerte en haut du formulaire ; ce qui a été tapé est conservé. Seules les erreurs de forme (`fieldErrors`) s'affichent sous le champ.
- **Le destinataire d'un lot expédié** : quand une correction est faite sur un lot qui était expédié, l'interface affiche un message en français, prêt à être copié, que le `supervisor` transmet lui-même. L'application n'envoie rien (pas de courriel), n'enregistre pas qu'un message a été transmis, et la base ne connaît pas le destinataire.
- **Visibilité** : tous les rôles qui lisent (`reader`, `writer`, `supervisor`) voient l'historique des corrections et le nom de leur auteur, comme pour les mouvements. Aucune règle ne le cache. Ce choix sera rediscuté à la fin du lot.
- **Migration** : `002` crée la table pour une base neuve ; `database/019_add_movement_correction.sql` met à niveau une base existante (rejouable). `005` (`ReplaceMovement`, `CancelMovement`, `GetBatch`) et `017` sont à rejouer. `019` n'a été exécuté que sur `TraceabilityTest`. La CI n'est pas modifiée.
- **Tests** : `003` (31 tests) et `006` (88 tests) testent la table et les procédures ; 301 tests en C# et 297 tests pour l'interface. L'essai à la main avec Keycloak est en [verification.md](../verification.md), section 22 ; `database/901_trial_data_lot12a.sql` recrée les données de l'essai.

## Alternatives écartées

- **Modifier la ligne du mouvement en place.** Non essayée : on perdrait la valeur saisie et l'histoire, et `Movement` cesserait d'être un journal où l'on n'ajoute que des lignes.
- **Un mouvement de signe contraire pour annuler.** Non essayée : une annulation devrait alors être lue à travers les autres mouvements ; une table de corrections garde le lien avec le mouvement corrigé.
- **Laisser le rôle `writer` corriger.** Non essayée : la personne qui saisit corrigerait ses propres saisies sans second regard ; le rôle `supervisor` sépare les deux. Le `writer` reçoit un 403 (L6, L11).
- **Un `supervisor` qui saisit aussi des mouvements.** Non essayée : même raison ; le rôle lit et corrige seulement.
- **Envoyer un courriel au destinataire depuis l'application, ou garder une trace de la transmission.** Non essayée : cela demande un serveur de courriel, l'adresse du destinataire (que la base ne connaît pas) et une règle sur ce qui est envoyé, hors du périmètre du lot 12a.
- **Permettre de corriger ou d'annuler n'importe quel mouvement du lot.** Non essayée : annuler un mouvement du milieu obligerait à recalculer ou à refuser les étapes qui le suivent ; seul le dernier peut être annulé.

## Conséquences

Positives :

- Une correction est une ligne à part, le journal est intact et les auteurs sont les vrais comptes ([verification.md](../verification.md) 22.2, L8). `supervisor` corrige ; `writer` et `reader` sont refusés (403), `norole-test` est refusé en lecture (L6, L7, L11).
- Les neuf refus essayés renvoient le code attendu et laissent le lot inchangé ; une annulation est définitive (L9, L10).
- Deux sessions SQL sur le même lot : la seconde attend la première, puis reçoit l'erreur 50308 (L12).
- Les tests détectent trois casses essayées : le rôle exigé par `replace`, le code de réponse de `cancel` et le troisième tableau de `GetBatch` (L13).
- L'interface : chaque rôle voit ce qu'il doit voir, les corrections et les annulations s'affichent, les refus s'affichent en français sans rien écrire (L16 à L23, L26, L28) ; l'heure envoyée à l'API se termine par `Z` (L24).
- Le message pour le destinataire apparaît sur un lot expédié et n'apparaît pas sur un lot dont l'expédition est annulée (L20, L27).

Négatives :

- **Seule l'interface web prévient du destinataire.** Un client qui appelle l'API directement, ou un autre programme, ne reçoit aucun avertissement quand il corrige un lot expédié. C'est une conséquence de ne pas avoir de notion de destinataire dans l'API ni dans la base.
- **Rien n'enregistre l'état du lot au moment de la correction.** Le message est calculé par l'interface d'après le statut du lot qu'elle affichait. Plus tard, rien dans la base ne dit si un lot était expédié quand il a été corrigé, et rien ne dit si le message a été transmis.
- **Le nom de l'auteur d'une correction est visible de tous les rôles qui lisent**, y compris `reader`. Ce choix est à rediscuter à la fin du lot.
- **Le message est transmis à la main**, sans trace : le `supervisor` peut oublier de le faire.
- **Le verrou n'est essayé qu'avec deux sessions SQL**, une transaction tenue ouverte à la main (L12), pas avec deux appels HTTP lancés en même temps. Le comportement sans `UPDLOCK` n'est pas essayé.
- **`019`, et la nouvelle version de `005` et `017`, ne sont pas rejoués sur `TraceabilityDev`** : la décision d'y toucher n'est pas prise. `007` n'est jamais rejoué et `018` reste en essai à blanc (`@keep = N'NO'`).
- **La CI n'a pas été vue sur ce lot** : la branche n'est pas poussée, donc les contrôles `backend`, `frontend` et `docker` ne sont pas vus.
- **L'essai de l'interface est fait dans un seul navigateur, sur un seul PC**, dont l'horloge est à l'heure UTC ; le renouvellement du jeton pendant la saisie d'une correction n'est pas essayé. Voir [verification.md](../verification.md) 22.3.
- **Deux écarts ont été relevés pendant l'essai** : le message pour le destinataire apparaissait à tort quand l'expédition avait été annulée (corrigé, L20 et L27), et le texte de l'erreur 50304, jugé peu clair, a été réécrit (L26).

## Notes

- 2026-11-12 : décision prise à la fin de l'essai du lot 12a ([verification.md](../verification.md), section 22). Le plan du lot a été approuvé avant l'écriture du code. Les alternatives ci-dessus ont été rédigées en écrivant ce document, aucune n'a été essayée. Le point de la visibilité du nom de l'auteur d'une correction reste ouvert.
- 2026-11-12 (après la fusion) : la CI a été vue sur ce lot, ce qui complète la conséquence « La CI n'a pas été vue sur ce lot » : elle est verte sur la branche et sur `main` après la fusion de la pull request n° 27, après un premier échec dû au SDK 11 ([verification.md](../verification.md), L30, et [ADR 0009](0009-integration-continue-github-actions.md)). Le point sur la visibilité du nom de l'auteur d'une correction est reporté au plan du lot 12b : la correction de la fiche du lot aura aussi un auteur, et la règle sera décidée pour les deux.
