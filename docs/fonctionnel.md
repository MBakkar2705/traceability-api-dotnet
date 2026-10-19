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

Hors périmètre pour l'instant :

- Découpe ou fusion de lots : un lot reste un lot du début à la fin.
- Connexion à un ERP, un DataWarehouse ou un outil BI.
- Gestion des utilisateurs et des droits.
- Archivage ou purge des anciennes données : aucun lot ni mouvement n'est supprimé (règles 3 et 4), donc la base ne fait que grossir.
- Retours de marchandise (voir section 9).
- Interface web : plus tard (lot 7, optionnel).

## 3. Ce qu'on trace

| Notion | Table | À quoi ça sert |
|---|---|---|
| Ferme | `trace.Farm` | Le lieu de production. Un lot vient toujours d'une ferme. |
| Lot | `trace.Batch` | Une quantité de tomates récoltées ensemble. C'est l'objet qu'on suit. |
| Station | `trace.Station` | Un lieu de traitement, identifié par un code (par exemple `SITE-01`). |
| Fonction d'une station | `trace.StationCapability` | La liste de ce qu'une station a le droit de faire (réception, tri, emballage, expédition). Une station peut avoir plusieurs fonctions. |
| Mouvement | `trace.Movement` | Une ligne de journal : « tel lot est passé par telle station, à telle heure, avec telle quantité ». |

Le lot garde son état actuel (statut et dernière quantité connue). Le mouvement garde l'historique : on le lit pour reconstituer tout le parcours.

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
2. **Quantité** : elle est toujours supérieure à 0 et ne peut pas augmenter d'une étape à l'autre. Elle peut baisser (le tri écarte des tomates), jamais monter.
3. **Journal** : un mouvement n'est jamais modifié ni supprimé. Pour corriger, on ajoute un nouveau mouvement.
4. **Fin de parcours** : un lot `SHIPPED` n'a plus de nouveau mouvement, mais il reste consultable avec tout son parcours. Aucun lot n'est supprimé, pour pouvoir y revenir en cas de réclamation.
5. **Unicité** : le code d'un lot, d'une ferme et d'une station est unique.
6. **Fonction de la station** : un mouvement n'est accepté que si la station a la fonction correspondante. Cette règle est garantie par la base elle-même (clé étrangère).

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
- Enregistrer la réception d'un lot (création du lot et de son premier mouvement).
- Enregistrer le mouvement suivant d'un lot.
- Consulter un lot avec tout son parcours, dans l'ordre.
- Lister les lots par statut ou par ferme.

## 8. Choix retenus

Validés par Mohamed le 2026-10-18.

- À la création, un lot reçoit directement son premier mouvement `RECEPTION` et son statut `RECEIVED`.
- Dans un mouvement, la quantité est celle constatée à cette étape. Dans le lot, c'est la dernière quantité connue.
- Une station peut avoir une ou plusieurs fonctions, listées dans `trace.StationCapability`.

## 9. Limites et évolutions possibles

### Retours de marchandise

Le système ne gère pas les retours de marchandise. `SHIPPED` reste la fin du parcours.

Ce choix est volontaire : nous ne connaissons pas assez le métier ni la façon dont ces cas sont traités dans la réalité (que devient un lot retourné, qui décide, comment la quantité est comptée). Plutôt que d'inventer des règles, nous préférons ne pas les modéliser.

Ce qu'on sait déjà :

- **Retour total** : techniquement simple. Il faudrait un statut `RETURNED` et un type de mouvement `RETURN`, sans nouvelle table. Les règles qui suivent le retour restent à connaître.
- **Retour partiel** : le modèle actuel ne peut pas le représenter. Un lot n'a qu'un statut et qu'une quantité, donc on ne peut pas dire qu'une partie est expédiée et l'autre retournée. Il faudrait pouvoir scinder un lot, ce qui est aussi hors périmètre.

Un lot expédié reste consultable avec tout son parcours (règle 4), ce qui permet de le retrouver en cas de réclamation.

### Corrections

La règle 3 dit de corriger par un nouveau mouvement. Mais les procédures refusent un mouvement de correction : l'ordre des statuts (erreur 50301) et la quantité qui ne monte pas (erreur 50302) l'interdisent. Une faute de saisie ne peut donc pas être corrigée aujourd'hui. C'est une question à poser au métier (voir [procedures.md](procedures.md), section 5).

### Heure des mouvements

L'heure d'un mouvement n'est pas contrôlée : un mouvement peut avoir une heure antérieure au précédent ou située dans le futur. Le parcours est donné dans l'ordre d'enregistrement. Le métier réel dira si une règle est nécessaire.
