# ADR 0017 : la fiche d'un lot se corrige par une ligne de plus, les anciens codes restent réservés, et les noms des auteurs ne sont montrés qu'à `auditor` et `supervisor`

Statut : **Accepté** (2026-11-16)

## Contexte

La fiche d'un lot (son code, sa ferme, sa variété, son jour de récolte) est saisie à la création, et elle peut être fausse comme un mouvement. Le lot 12a a rendu les mouvements corrigeables ([ADR 0016](0016-correction-des-mouvements.md)) en laissant la fiche à un lot suivant. `Batch` est l'état actuel du lot : corriger la fiche en place effacerait ce qui avait été saisi, et un code changé pose un problème que les mouvements n'avaient pas : un code a pu être donné à quelqu'un (un destinataire, une étiquette) avant d'être corrigé.

L'ADR 0016 a aussi laissé ouverte la visibilité des noms des auteurs : tous les rôles qui lisent les voyaient depuis le lot 11, « à rediscuter à la fin du lot ». Ce lot la tranche.

## Décision

- **`Batch` reste l'état actuel, et rien n'est écrasé en silence.** Une correction est une ligne de plus dans une table à part, `trace.BatchCorrection` : elle garde l'ancienne et la nouvelle valeur des quatre champs, le motif, le commentaire, l'auteur (`AuthorId` et `AuthorName`, lus dans le jeton comme au lot 11) et la date (`CorrectedAt`, en UTC). Ses lignes ne sont jamais modifiées.
- **La procédure `CorrectBatch`** met à jour le lot et écrit la ligne dans une seule transaction, avec le même verrou `UPDLOCK` que les autres procédures sur le lot ([ADR 0003](0003-verrou-sur-le-lot.md)). Les quatre valeurs sont toujours données (un champ qui ne change pas répète sa valeur actuelle). Le statut et la quantité du lot ne changent jamais ici, et un lot expédié peut être corrigé.
- **Règles** : des valeurs identiques aux valeurs actuelles sont refusées (50308), un changement de casse seul compte comme un changement ; une ferme inconnue (50101) ; un lot inconnu (50100) ; un code déjà porté par un autre lot (50202) ; un code qui est l'ancien code d'un autre lot (50203) ; un jour de récolte après le jour de la réception (50309).
- **Un ancien code reste réservé au lot qui l'a eu.** Aucun autre lot ne peut le prendre, ni à la création ni par une correction ; le lot lui-même peut le reprendre. Un code qui est l'ancien code d'un autre lot est refusé par l'erreur 50203, un numéro qui existait déjà pour « la station a déjà cette fonction » : chaque formulaire de l'interface donne donc son propre texte.
- **Lire avec un ancien code trouve le lot, écrire avec un ancien code est refusé.** `GetBatch` répond avec le code actuel dans `batchCode`. L'ajout d'un mouvement, son remplacement, son annulation et la correction de la fiche faits avec un ancien code répondent 404, erreur 50104, dont le détail cite le code actuel : on n'écrit jamais sur un lot par un code qui ne le désigne plus.
- **Ce qui départage deux corrections vers le même code** : l'index unique `UQ_Batch_BatchCode`, qui ne porte que sur les codes actuels. Deux corrections vers le même nouveau code au même instant donnent une réponse 201 et une réponse 409 (50202). **Deux lots qui prennent le même ancien code au même instant ne sont protégés par rien** (voir les conséquences).
- **Motifs** : seulement `DATA_ENTRY_ERROR` et `OTHER` pour une fiche (50407 sinon, y compris `MEASUREMENT_ERROR`, qui parle d'une mesure) ; le commentaire est obligatoire pour `OTHER` (50408) et de 500 caractères au plus (50409, que l'API ne laisse pas atteindre : elle refuse d'abord par une erreur de forme 400 sur `reasonComment`).
- **Le jour de récolte ne peut pas être après le jour de la réception** (50309). La règle est aussi contrôlée à la création d'un lot et quand on déplace la réception avant le jour de récolte (`ReplaceMovement`).
- **Un nouveau rôle Keycloak, `auditor`** : il lit tout, y compris les noms des auteurs, et ne peut ni saisir ni corriger. `supervisor` lit, corrige et voit les noms. **`reader` et `writer` lisent, mais reçoivent `authorName` à `null`** : c'est un changement de comportement, ils voyaient ces noms depuis le lot 11. `authorId` n'est jamais renvoyé. La politique `CanSeeAuthors` (`auditor` ou `supervisor`) n'est la règle d'aucune route : le contrôleur l'évalue pour choisir entre le nom et `null` dans une réponse.
- **Une route** : `POST /batches/{batchCode}/correct`, réservée à `supervisor`, avec `newBatchCode`, `farmCode`, `variety`, `harvestDate`, `reasonCode` et `reasonComment`. Elle répond 201 sans corps, avec un en-tête `Location` vers le lot sous son nouveau code. `GET /batches/{batchCode}` gagne `sheetCorrections` ; `corrections` reste la liste des corrections de mouvements.
- **L'interface** : pour `supervisor`, la section « Corriger la fiche » (quatre champs préremplis, deux motifs) ; pour tous les rôles qui lisent, la section « Corrections de la fiche », qui liste les champs changés ; les colonnes d'auteur disparaissent quand l'API n'envoie aucun nom ; après un changement de code, la page passe à la nouvelle adresse, et elle remplace un ancien code de l'adresse par le code actuel.
- **Le destinataire d'un lot expédié** : comme en 12a, l'interface affiche un message à copier (avec le nouveau code), que le `supervisor` transmet lui-même ; l'application n'envoie rien et ne garde aucune trace.
- **Migration** : `002` crée la table pour une base neuve ; `database/020_add_batch_correction.sql` met à niveau une base existante (après `019`). `005` est à rejouer. `902` crée les données de l'essai, sur `TraceabilityTest` seulement.
- **Tests** : `003` (43 tests) et `006` (122 tests) testent la table et les procédures ; 356 tests en C# et 332 tests pour l'interface. L'essai à la main avec de vrais jetons est en [verification.md](../verification.md), section 23.

## Alternatives écartées

- **Modifier la fiche en place, sans table de corrections.** Non essayée : on perdrait ce qui a été saisi et l'histoire du lot.
- **Libérer l'ancien code pour d'autres lots.** Non essayée : un code déjà transmis pourrait alors désigner un autre lot ; l'ancien code reste donc réservé.
- **Accepter les écritures faites avec un ancien code, en les redirigeant.** Non essayée : on écrirait sur un lot par un code qui ne le désigne plus, sans que la personne le sache ; le 404 dit le nouveau code et laisse la personne relancer.
- **Garder les noms des auteurs visibles de tous les rôles qui lisent.** Écartée par ce lot : seuls `auditor` et `supervisor` en ont besoin ; c'est le changement de comportement relevé plus haut.
- **Accepter `MEASUREMENT_ERROR` pour une fiche.** Non essayée : une erreur de mesure parle d'une quantité, pas d'un code, d'une ferme, d'une variété ou d'une date.

## Conséquences

Positives :

- Une correction de la fiche est une ligne à part, les anciennes valeurs sont conservées et l'auteur est le vrai compte, comparé à la console de Keycloak ([verification.md](../verification.md) 23.2, M18).
- Les rôles essayés avec de vrais jetons : `auditor` lit sans corriger, `supervisor` corrige, `writer` et `reader` reçoivent `authorName` à `null` et sont refusés en correction (M5, M7, M8).
- Les six refus essayés s'affichent en français sans rien écrire (M16, M18) ; l'ancien code trouve le lot en lecture et est refusé en écriture (M17).
- Les tests détectent les trois casses essayées (rôle des noms, rôle de `/correct`, colonnes d'auteur), les fichiers étant remis à l'identique (M19).

Négatives :

- **Deux lots qui prennent le même ancien code au même instant ne sont protégés par aucune contrainte, et ce cas n'est pas testé.** Le test de concurrence ne couvre que le même nouveau code, avec un faux jeton.
- **Les noms d'auteurs ne sont plus visibles de `reader` et de `writer`** : c'est un changement de comportement depuis le lot 11.
- **Seule l'interface web prévient du destinataire**, et rien n'enregistre l'état du lot au moment de la correction ni la transmission du message, comme en 12a.
- **Une variété tapée avec un espace à la fin est enregistrée telle quelle**, à la création comme à la correction (M15, M18). Hors de ce lot.
- **La CI ne rejoue pas `020`** : elle recrée la base avec `002`. `006` sur une base neuve de la CI ne sera connu qu'après le push, et les durées de `019`, `020` et `005` sur `TraceabilityDev` n'ont pas été mesurées.
- **L'ordre des heures des mouvements** (une correction qui ferait passer une étape avant la précédente) est le lot 12c.

## Notes

- 2026-11-16 : décision prise à la fin de l'essai du lot 12b ([verification.md](../verification.md), section 23). Le plan du lot a été approuvé avant l'écriture du code. Les alternatives ci-dessus ont été rédigées en écrivant ce document, aucune n'a été essayée. La visibilité du nom des auteurs, laissée ouverte par l'[ADR 0016](0016-correction-des-mouvements.md), est tranchée ici pour les mouvements et pour les corrections.
- 2026-11-16, après la fusion : la CI est verte sur la branche, la pull request et `main` ; `006` a tourné sur la base neuve de la CI (122 tests). Elle ne rejoue toujours pas `020` ([verification.md](../verification.md), section 23, M20).
