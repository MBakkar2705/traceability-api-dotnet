# Documentation fonctionnelle

Ce document décrit ce que le système doit faire, pas ce qu'il fait déjà. L'avancement est dans le [README](../README.md).

## 1. Objectif

Le système enregistre le parcours des lots de tomates, de la ferme jusqu'à l'expédition.
Il doit permettre de répondre à quatre questions pour n'importe quel lot :

- D'où vient-il ? (la ferme)
- Où est-il passé ? (les stations, dans l'ordre)
- Dans quel état est-il ? (son statut)
- Quelle quantité reste-t-il à chaque étape ? (en kg)

## 2. Périmètre

Il s'agit d'un scénario simplifié et inventé, créé pour apprendre. Il ne représente aucun système réel.

Inclus :

- Des fermes, des stations, des lots et des mouvements.
- Un parcours de lot en quatre étapes (voir section 4).
- Des règles métier appliquées par la base de données (procédures stockées).
- Une API pour enregistrer et consulter.
- Une interface web en React : lecture, écriture et correction.
- La correction des mouvements par un rôle de supervision (voir section 5, règle 8).

Ce qui est hors périmètre, et ce qui reste à faire ou à prendre en compte, est dans le [README](../README.md), section « Hors périmètre et suite ».

## 3. Ce qu'on trace

| Notion | Table | À quoi ça sert |
|---|---|---|
| Ferme | `trace.Farm` | Le lieu de production. Un lot vient toujours d'une ferme. |
| Lot | `trace.Batch` | Une quantité de tomates récoltées ensemble. C'est l'objet qu'on suit. |
| Station | `trace.Station` | Un lieu de traitement, identifié par un code (par exemple `SITE-01`). |
| Fonction d'une station | `trace.StationCapability` | La liste de ce qu'une station a le droit de faire (réception, tri, emballage, expédition). Une station peut avoir plusieurs fonctions. |
| Mouvement | `trace.Movement` | Une ligne de journal : « tel lot est passé par telle station, à telle heure, avec telle quantité, saisi par tel utilisateur ». |
| Correction d'un mouvement | `trace.MovementCorrection` | Une ligne qui remplace les valeurs d'un mouvement ou l'annule, avec son motif et son auteur. Le mouvement d'origine reste tel qu'il a été saisi. |

Le lot garde son état actuel (statut et dernière quantité connue). Le mouvement garde l'historique : on le lit pour reconstituer tout le parcours. Les corrections gardent ce qui a été changé après coup.

## 4. Cycle de vie d'un lot

Un lot passe par quatre statuts, dans cet ordre :

`RECEIVED` → `SORTED` → `PACKED` → `SHIPPED`

Chaque étape correspond à un type de mouvement :

| Statut du lot | Type de mouvement |
|---|---|
| `RECEIVED` | `RECEPTION` |
| `SORTED` | `SORTING` |
| `PACKED` | `PACKING` |
| `SHIPPED` | `SHIPMENT` |

À chaque étape, on ajoute un mouvement. Le statut du lot passe à l'étape suivante.

Une station n'accepte un type de mouvement que si cette fonction figure dans `trace.StationCapability`. Une même station peut avoir une fonction (emballage seul) ou plusieurs (réception et tri sur le même site).

## 5. Règles métier

Ces règles seront appliquées dans la base de données (procédures stockées et contraintes), pas seulement dans l'API.

1. **Ordre des statuts** : un lot ne saute pas d'étape. Il ne peut pas passer de `RECEIVED` à `PACKED`.
2. **Quantité** : elle est toujours supérieure à 0 et ne peut pas augmenter d'une étape à l'autre. Elle peut baisser (le tri écarte des tomates), jamais monter. La même règle vaut pour une quantité corrigée : elle reste entre celle de l'étape précédente et celle de l'étape suivante (règle 8).
3. **Journal** : un mouvement n'est jamais modifié ni supprimé. Pour corriger, on ajoute une ligne de correction à part (règle 8) ; le mouvement d'origine reste dans le journal.
4. **Fin de parcours** : un lot `SHIPPED` n'a plus de nouveau mouvement, mais il reste consultable avec tout son parcours. Aucun lot n'est supprimé, pour pouvoir y revenir en cas de réclamation.
5. **Unicité** : le code d'un lot, d'une ferme et d'une station est unique.
6. **Fonction de la station** : un mouvement n'est accepté que si la station a la fonction correspondante. Cette règle est garantie par la base elle-même (clé étrangère).
7. **Auteur** : chaque mouvement enregistre qui l'a saisi, l'identifiant du compte et son nom d'utilisateur, pris dans le jeton de connexion et jamais dans la demande. Le nom est celui du moment de la saisie. Les mouvements d'avant cette règle n'ont pas d'auteur connu : ils portent un auteur de remplacement, que l'interface affiche « Données initiales ».
8. **Corrections** : seul un utilisateur qui a le rôle `supervisor` peut corriger un mouvement. Il peut **remplacer** ses valeurs (station, quantité, heure ; le type du mouvement ne change pas) ou **l'annuler** (le mouvement n'a pas eu lieu). Un motif est obligatoire : erreur de saisie, erreur de mesure ou autre ; le commentaire (500 caractères au plus) est obligatoire pour « autre ». La valeur valable d'un mouvement est celle de sa dernière correction.
   - La quantité corrigée reste entre celle de l'étape valable précédente et celle de l'étape valable suivante ; l'égalité est acceptée. La réception peut donc être augmentée, tant qu'elle n'est pas inférieure à l'étape suivante ; la dernière étape n'a pas de limite basse, sauf d'être supérieure à 0.
   - La station doit avoir la fonction du mouvement. Des valeurs identiques aux valeurs actuelles sont refusées.
   - Seul le dernier mouvement valable peut être annulé, jamais la réception (un lot a toujours sa réception). Un mouvement annulé ne peut plus être corrigé ni annulé.
   - Le statut et la quantité du lot suivent les valeurs valables : annuler l'expédition d'un lot `SHIPPED` le ramène à `PACKED` (c'est le seul cas où un lot expédié bouge, la règle 4 vaut pour l'ajout de mouvements).
   - Chaque correction enregistre son auteur (comme la règle 7) et sa date. Tous les rôles qui lisent voient l'historique des corrections et le nom de leur auteur.
9. **Rôles** : `reader` lit ; `writer` lit et saisit des mouvements ; `supervisor` lit et corrige, et ne saisit pas de mouvement.
10. **Destinataire d'un lot expédié** : quand une correction est faite sur un lot qui était expédié, l'interface web affiche un message en français à copier, que le `supervisor` transmet lui-même. Le système n'envoie rien, et ne garde aucune trace de la transmission. Un appel direct à l'API ne donne pas ce message.

## 6. Exemple de bout en bout

Données inventées.

Stations et leurs fonctions :

| Station | Fonctions |
|---|---|
| `SITE-01` | `RECEPTION`, `SORTING` |
| `PCK-01` | `PACKING` |
| `SHP-01` | `SHIPMENT` |

Ferme `F01` « Ferme Nord », région Souss-Massa. Lot `LOT-2026-0001`, variété cerise, récolté le 2026-10-14, 500.00 kg.

| # | Heure (UTC) | Mouvement | Station | Quantité | Statut du lot après |
|---|---|---|---|---|---|
| 1 | 2026-10-14 06:30 | `RECEPTION` | `SITE-01` | 500.00 kg | `RECEIVED` |
| 2 | 2026-10-14 09:15 | `SORTING` | `SITE-01` | 470.00 kg | `SORTED` |
| 3 | 2026-10-14 13:40 | `PACKING` | `PCK-01` | 465.00 kg | `PACKED` |
| 4 | 2026-10-14 17:05 | `SHIPMENT` | `SHP-01` | 465.00 kg | `SHIPPED` |

Trois demandes qui seraient refusées :

- Un `SHIPMENT` juste après le `RECEPTION` : une étape est sautée (règle 1).
- Un `SORTING` à 520.00 kg alors que le lot en a 500.00 : la quantité augmente (règle 2).
- Un `PACKING` à la station `SITE-01` : cette station n'a pas la fonction `PACKING` (règle 6).

## 7. Ce que l'API fera

- Créer et lister les fermes et les stations.
- Déclarer les fonctions d'une station.
- Consulter une station avec ses fonctions.
- Enregistrer la réception d'un lot (création du lot et de son premier mouvement).
- Enregistrer le mouvement suivant d'un lot.
- Consulter un lot avec tout son parcours, dans l'ordre, chaque mouvement avec le nom de son auteur, ses valeurs valables et, s'il a été corrigé, ses valeurs d'origine ; l'historique des corrections est dans la même réponse.
- Remplacer les valeurs d'un mouvement ou l'annuler (rôle `supervisor`).
- Lister les lots par statut ou par ferme.

## 8. Choix retenus

Validés le 2026-10-18.

- À la création, un lot reçoit directement son premier mouvement `RECEPTION` et son statut `RECEIVED`.
- Dans un mouvement, la quantité est celle constatée à cette étape. Dans le lot, c'est la dernière quantité connue.
- Une station peut avoir une ou plusieurs fonctions, listées dans `trace.StationCapability`.

Validés pour le lot 12a (correction des mouvements), voir [ADR 0016](adr/0016-correction-des-mouvements.md) :

- Une correction est une ligne à part, jamais une modification du journal ; on remplace ou on annule, on ne supprime pas.
- Les corrections sont faites par un rôle `supervisor`, qui ne saisit pas de mouvement.
- Le message pour le destinataire d'un lot expédié est affiché par l'interface web seulement, copié et transmis à la main.

## 9. Limites et évolutions possibles

### Retours de marchandise

Le système ne gère pas les retours de marchandise. `SHIPPED` reste la fin du parcours.

Ce choix est volontaire : nous ne connaissons pas assez le métier ni la façon dont ces cas sont traités dans la réalité (que devient un lot retourné, qui décide, comment la quantité est comptée). Plutôt que d'inventer des règles, nous préférons ne pas les modéliser.

Ce qu'on sait déjà :

- **Retour total** : techniquement simple. Il faudrait un statut `RETURNED` et un type de mouvement `RETURN`, sans nouvelle table. Les règles qui suivent le retour restent à connaître.
- **Retour partiel** : le modèle actuel ne peut pas le représenter. Un lot n'a qu'un statut et qu'une quantité, donc on ne peut pas dire qu'une partie est expédiée et l'autre retournée. Il faudrait pouvoir scinder un lot, ce qui est aussi hors périmètre.

Un lot expédié reste consultable avec tout son parcours (règle 4), ce qui permet de le retrouver en cas de réclamation.

### Corrections

Depuis le lot 12a, une faute de saisie sur un mouvement se corrige (règle 8). Ce qui reste hors périmètre :

- **La fiche du lot** (variété, date de récolte, ferme) et son code ne se corrigent pas ; c'est le lot 12b, pas commencé.
- **Le destinataire** : seule l'interface web prévient, par un message à copier ; un appel direct à l'API ne donne rien, aucun courriel n'est envoyé, et rien n'enregistre qu'un message a été transmis, ni l'état du lot au moment de la correction.
- **La visibilité du nom de l'auteur d'une correction** : tous les rôles qui lisent le voient, comme pour les mouvements. Ce choix reste à rediscuter, avec les responsables des données si les utilisateurs sont réels.
- **Corriger un mouvement qui n'est pas le dernier** : on peut remplacer ses valeurs, pas l'annuler.

### Heure des mouvements

L'heure d'un mouvement n'est pas contrôlée, ni à la saisie ni à la correction : un mouvement peut avoir une heure antérieure au précédent ou située dans le futur. Le parcours est donné dans l'ordre d'enregistrement. Le métier réel dira si une règle est nécessaire.
