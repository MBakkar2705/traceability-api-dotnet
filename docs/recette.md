# Cahier de recette fonctionnelle

Ce cahier prouve, sur une base à part, que les règles de [fonctionnel.md](fonctionnel.md) sont tenues par l'application. Il se rejoue : chaque scénario a un identifiant, des étapes, un résultat attendu et un statut. Il doit évoluer avec l'application : chaque nouvelle règle ou modification fonctionnelle y ajoute ou y change des scénarios.

État au lot 13b (2026-11-24, en cours) : la base de recette, les outils et la préparation sont en place et essayés (lot 13a). Les scénarios des règles (R01 à R12 et NOMINAL) sont écrits par blocs et rejoués au fur et à mesure : un scénario n'est marqué « Observé » qu'après son exécution.

## 1. Principes

- **Base** : `TraceabilityAcceptance`, créée à part de `TraceabilityDev` et de `TraceabilityTest`. `dotnet test` ne la touche pas, et le script `900` accepte son nom (voir l'[ADR 0002](adr/0002-tests-sur-base-reelle.md), note du lot 13a).
- **Un groupe par règle** de `fonctionnel.md`, un lot par groupe. Les identifiants de scénario ont la forme `R01-01` (groupe, puis numéro). Deux groupes de service : `R00-PREPARATION` (données de référence) et `R99-OUTILS` (contrôle de l'outillage).
- **Code du lot** : `Rxx-GROUPE-aammjj`, où `aammjj` est la date du jour où le groupe commence (variable `$s`, voir la section 3), par exemple `R01-ORDRE-261124`. Un groupe rejoué le même jour reçoit un suffixe sur son code (`-2`, par exemple). Un code de lot contient 30 caractères au plus : des lettres sans accent, des chiffres, `-` et `_`.
- **Canal** : chaque scénario dit s'il est essayé par l'API, par l'interface, ou par les deux.
- **Statuts** : `Observé le AAAA-MM-JJ` (exécuté et relevé), `Non essayé`, `Échec` (avec ce qui a été vu). Un scénario n'est marqué observé qu'après son exécution.
- **Un scénario = une action** (un appel, un refus ou une lecture), avec un seul résultat attendu et son propre statut. Quelques scénarios de préparation regroupent plusieurs appels (R00, R10-01, NOM-03).
- **Un groupe se joue dans l'ordre, sur son lot, en une seule journée** : un succès fait avancer le lot, un refus ne change rien. On ne commence un groupe que si on peut le finir le jour même ; un groupe interrompu se rejoue en entier, avec un nouveau lot (suffixe `-2`). Plusieurs groupes peuvent se jouer le même jour. Un groupe peut avoir un deuxième lot quand une règle l'exige (R11).
- **Dates** : J est la date du jour où le groupe commence. Les heures des mouvements sont du jour J − 1 (toujours dans le passé), le jour de récolte est J − 2. Les commandes n'ont aucune date écrite en dur : elles lisent les variables `$s`, `$v` et `$r` (section 3).
- **Réponses attendues** : les codes d'erreur viennent de [procedures.md](procedures.md). L'API répond 404 pour les erreurs 501xx, 409 pour 502xx, 422 pour 503xx et 400 pour 504xx. Le groupe NOMINAL a les identifiants `NOM-01` et le lot `NOM-PARCOURS-aammjj`.
- **Sécurité** : ni mot de passe ni jeton dans ce fichier ni dans les outils. Les mots de passe se tapent dans la saisie masquée de `Get-Trial`.

## 2. Comptes de test

Les cinq comptes existent dans le realm `traceability` de Keycloak. Ils ont été créés à la main, chacun avec le rôle de son nom (`norole-test` n'en a aucun). Les rôles ouvrent ces droits (`Program.cs`) :

| Compte | Rôle | Lire | Écrire | Corriger | Voir les auteurs |
|---|---|---|---|---|---|
| `reader-test` | reader | oui | non | non | non |
| `writer-test` | writer | oui | oui | non | non |
| `supervisor-test` | supervisor | oui | non | oui | oui |
| `auditor-test` | auditor | oui | non | non | oui |
| `norole-test` | aucun | non | non | non | non |

Au lot 13a, `reader-test`, `writer-test` et `supervisor-test` ont servi. `auditor-test` et `norole-test` serviront au lot 13b.

## 3. Préparer une séance

1. **Base** (si elle doit être reconstruite) : `900` avec `:setvar DbName TraceabilityAcceptance` et `@confirm` à `YES` (sans enregistrer le fichier), puis `001`, `002`, `004`, `005`, `011` et `017`, chacun avec son `:setvar` mis sur `TraceabilityAcceptance` à l'écran, sans enregistrer. `003` est un contrôle facultatif : il laisse les compteurs d'identité avancés.
2. **Keycloak** : `docker start traceability-keycloak`, attendre environ une minute, puis le realm doit répondre `200` sur `http://localhost:8180/realms/traceability/.well-known/openid-configuration`.
3. **API**, dans sa propre fenêtre, depuis la racine du dépôt :

```powershell
$env:ConnectionStrings__Default = [Environment]::GetEnvironmentVariable("ConnectionStrings__Acceptance", "User")
$env:Authentication__Authority = "http://localhost:8180/realms/traceability"
$env:Authentication__Audience = "traceability-api"
$env:ConnectionStrings__Default
dotnet run --project src/Traceability.Api --launch-profile https
```

Relire la quatrième ligne avant de lancer : elle doit contenir `Database=TraceabilityAcceptance`. La variable `ConnectionStrings__Acceptance` se crée une seule fois, dans le compte Windows : `Server=localhost;Database=TraceabilityAcceptance;Integrated Security=True;TrustServerCertificate=True`.

4. **Essais**, dans une autre fenêtre : `. .\docs\recette-outils.ps1`. À refaire dans chaque nouvelle fenêtre et quand le fichier change.
5. **Dates du groupe**, au début de chaque groupe, dans la même fenêtre (à recoller si la fenêtre est fermée ou si la journée UTC change) :

```powershell
$d = (Get-Date).ToUniversalTime()
$s = $d.ToString('yyMMdd')                  # suffixe du code du lot (aammjj)
$v = $d.AddDays(-1).ToString('yyyy-MM-dd')  # la veille : date des heures des mouvements
$r = $d.AddDays(-2).ToString('yyyy-MM-dd')  # l'avant-veille : jour de récolte
```

Les commandes des groupes utilisent ces variables, par exemple `"R01-ORDRE-$s"` et `"${v}T06:00:00Z"`. Pour voir la valeur d'une variable, taper son nom (`$s`). Ces lignes n'ont pas encore été essayées : le premier groupe joué le dira.

## 4. Les outils

Tout est dans [recette-outils.ps1](recette-outils.ps1). Un jeton vit 300 secondes : en redemander un avant chaque série d'appels.

| Fonction | Rôle | Compte nécessaire |
|---|---|---|
| `Get-Trial` | demande un jeton et le garde, sans l'afficher | tous |
| `Show-Token`, `Show-Identity` | montrent le contenu du jeton (émetteur, durée, rôles, identité) | tous |
| `Read-Api`, `Read-Lot` | lisent une route, ou la fiche d'un lot | reader, writer, supervisor, auditor |
| `Send-Api` | envoie un `POST` (JSON écrit à la main possible) | selon la route |
| `New-Farm`, `New-Station`, `Add-Capability`, `New-Lot`, `Add-Movement` | écrivent | writer |
| `Replace-Movement`, `Cancel-Movement`, `Correct-Lot` | corrigent | supervisor |

## 5. R00-PREPARATION : données de référence

Les scénarios des règles s'appuient sur des fermes et des stations qui existent. Elles se créent avec `writer-test`.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R00-01 | `New-Farm 'FERME-NORD' 'Ferme du Nord' 'Nord'` | `HTTP 201` et la ferme en réponse | API | Observé le 2026-11-23 |
| R00-02 | `New-Station 'STA-RECEPTION' 'Station de reception'`, puis `Add-Capability 'STA-RECEPTION' 'RECEPTION'` | `HTTP 201` pour chacun | API | Observé le 2026-11-23 |
| R00-03 | `New-Farm 'FERME-SUD' 'Ferme du Sud' 'Sud'` | `HTTP 201` | API | Observé le 2026-11-24 |
| R00-04 | `New-Station 'STA-TRI' 'Station de tri'`, puis `Add-Capability 'STA-TRI' 'SORTING'` | `HTTP 201` pour chacun | API | Observé le 2026-11-24 |
| R00-05 | `New-Station 'STA-EMBALLAGE' 'Station emballage'`, puis `Add-Capability 'STA-EMBALLAGE' 'PACKING'` | `HTTP 201` pour chacun | API | Observé le 2026-11-24 |
| R00-06 | `New-Station 'STA-EXPEDITION' 'Station expedition'`, puis `Add-Capability 'STA-EXPEDITION' 'SHIPMENT'` | `HTTP 201` pour chacun | API | Observé le 2026-11-24 |
| R00-07 | `New-Station 'STA-MIXTE' 'Station mixte'`, puis `Add-Capability 'STA-MIXTE' 'RECEPTION'` et `Add-Capability 'STA-MIXTE' 'SORTING'` | `HTTP 201` pour chacun | API | Observé le 2026-11-24 |
| R00-08 | `New-Station 'STA-VIDE' 'Station sans fonction'` (aucune fonction), puis `Read-Api '/stations/STA-VIDE'` | `HTTP 201`, puis `HTTP 200` sans fonction | API | Observé le 2026-11-24 |

R00-03 à R00-08 (lot 13b) préparent les données des groupes R01 à R12. Elles se jouent une fois, avec `writer-test`, avant le premier groupe.

## 6. R99-OUTILS : contrôle de l'outillage

Lot d'essai : `R99-OUTILS-261123`. Vérifié le 2026-11-23, API et base lancées sur `TraceabilityAcceptance`.

| ID | Étapes | Attendu et relevé | Canal | Statut |
|---|---|---|---|---|
| R99-01 | `Get-Trial reader-test`, `Show-Token`, `Show-Identity` | `HTTP 200 Bearer`, durée 300 s, rôle `reader`, identité `reader-test` | API | Observé le 2026-11-23 |
| R99-02 | `Read-Api '/farms'`, `Read-Lot 'NOPE-1'`, puis la même lecture sans jeton | `200` page vide ; `404` avec `errorCode` 50100 ; `401` | API | Observé le 2026-11-23 |
| R99-03 | avec `writer-test` : `New-Lot 'R99-OUTILS-261123' 'FERME-NORD' 'Roma' '2026-11-22' 100.5 'STA-RECEPTION' '2026-11-23T06:00:00Z'`, puis `Read-Lot` | `201` ; fiche `RECEIVED`, 100.50 kg ; lot présent dans `TraceabilityAcceptance` (1) et absent de `TraceabilityDev` et `TraceabilityTest` (0 et 0), lu dans SSMS | API | Observé le 2026-11-23 |
| R99-04 | avec `supervisor-test` : `Replace-Movement` (95.5, motif `MEASUREMENT_ERROR`), `Correct-Lot` (variété `Cherry`, motif `DATA_ENTRY_ERROR`), `Cancel-Movement` de la réception | `201`, `201`, puis `422` avec `errorCode` 50307 ; la fiche montre `Cherry`, 95.50 kg (original 100.50) et le nom de l'auteur | API | Observé le 2026-11-23 |

**Non essayé au lot 13a** : les accents dans les noms (l'affichage de la console peut les déformer), le succès de `Cancel-Movement` (il faut un deuxième mouvement), les comptes `auditor-test` et `norole-test`, le mauvais mot de passe, et le canal Interface.

**À savoir** : sans commentaire (`$null`), l'API renvoie `"reasonComment": ""` (texte vide). Dans l'affichage de PowerShell, l'apostrophe d'un message peut s'écrire `'` : c'est cosmétique.


## 7. R01-ORDRE : l'ordre des statuts (règle 1)

Lot `R01-ORDRE-$s`, compte `writer-test`. Après chaque ligne, `Read-Lot "R01-ORDRE-$s"` relève le statut du lot.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R01-01 | `New-Lot "R01-ORDRE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` ; `RECEIVED`, 100.00 kg | API | Observé le 2026-11-24 |
| R01-02 | `Add-Movement "R01-ORDRE-$s" 'STA-EMBALLAGE' 'PACKING' 90 "${v}T07:00:00Z"` (saute le tri) | `422`, 50301 ; le lot reste `RECEIVED` | API | Observé le 2026-11-24 |
| R01-03 | `Add-Movement "R01-ORDRE-$s" 'STA-EXPEDITION' 'SHIPMENT' 90 "${v}T07:00:00Z"` (saute deux étapes) | `422`, 50301 ; le lot reste `RECEIVED` | API | Observé le 2026-11-24 |
| R01-04 | `Add-Movement "R01-ORDRE-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"` | `201` ; `SORTED` | API | Observé le 2026-11-24 |
| R01-05 | `Add-Movement "R01-ORDRE-$s" 'STA-EXPEDITION' 'SHIPMENT' 90 "${v}T08:00:00Z"` (saute l'emballage) | `422`, 50301 ; le lot reste `SORTED` | API | Observé le 2026-11-24 |
| R01-06 | `Add-Movement "R01-ORDRE-$s" 'STA-EMBALLAGE' 'PACKING' 90 "${v}T08:00:00Z"` | `201` ; `PACKED` | API | Observé le 2026-11-24 |
| R01-07 | `Add-Movement "R01-ORDRE-$s" 'STA-TRI' 'SORTING' 90 "${v}T09:00:00Z"` (retour en arrière) | `422`, 50301 ; le lot reste `PACKED` | API | Observé le 2026-11-24 |
| R01-08 | `Add-Movement "R01-ORDRE-$s" 'STA-EXPEDITION' 'SHIPMENT' 90 "${v}T09:00:00Z"` | `201` ; `SHIPPED` | API | Observé le 2026-11-24 |

Les stations de ce groupe ont toutes la bonne fonction : les refus viennent uniquement de l'ordre (la fonction de la station est le groupe R06).

## 8. R02-QUANTITE : la quantité (règle 2)

Lot `R02-QUANTITE-$s`, compte `writer-test`. Ce groupe couvre la saisie ; les bornes d'une quantité corrigée (50304) sont dans R08.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R02-01 | `New-Lot "R02-QUANTITE-$s" 'FERME-NORD' 'Roma' $r 0 'STA-RECEPTION' "${v}T06:00:00Z"`, puis `Read-Lot "R02-QUANTITE-$s"` | `400`, 50401 ; `Read-Lot` donne `404` (rien n'est créé) | API | Observé le 2026-11-24 |
| R02-02 | le même `New-Lot` avec `(-5)` à la place de `0` | `400`, 50401 | API | Observé le 2026-11-24 |
| R02-03 | le même `New-Lot` avec `100` | `201` ; `RECEIVED`, 100.00 kg | API | Observé le 2026-11-24 |
| R02-04 | `Add-Movement "R02-QUANTITE-$s" 'STA-TRI' 'SORTING' 0 "${v}T07:00:00Z"` | `400`, 50401 ; le lot reste `RECEIVED`, 100.00 kg | API | Observé le 2026-11-24 |
| R02-05 | `Add-Movement "R02-QUANTITE-$s" 'STA-TRI' 'SORTING' 120 "${v}T07:00:00Z"` (la quantité monte) | `422`, 50302 ; le lot reste `RECEIVED`, 100.00 kg | API | Observé le 2026-11-24 |
| R02-06 | `Add-Movement "R02-QUANTITE-$s" 'STA-TRI' 'SORTING' 100 "${v}T07:00:00Z"` (quantité égale) | `201` ; `SORTED`, 100.00 kg | API | Observé le 2026-11-24 |
| R02-07 | `Add-Movement "R02-QUANTITE-$s" 'STA-EMBALLAGE' 'PACKING' 90 "${v}T08:00:00Z"` (la quantité baisse) | `201` ; `PACKED`, 90.00 kg | API | Observé le 2026-11-24 |
| R02-08 | `Add-Movement "R02-QUANTITE-$s" 'STA-EXPEDITION' 'SHIPMENT' 95 "${v}T09:00:00Z"` (la quantité monte) | `422`, 50302 ; le lot reste `PACKED`, 90.00 kg | API | Observé le 2026-11-24 |
| R02-09 | `Add-Movement "R02-QUANTITE-$s" 'STA-EXPEDITION' 'SHIPMENT' 90 "${v}T09:00:00Z"` | `201` ; `SHIPPED`, 90.00 kg | API | Observé le 2026-11-24 |

## 9. R03-JOURNAL : le journal ne se modifie jamais (règle 3)

Lot `R03-JOURNAL-$s` (variété `Roma`). Écriture avec `writer-test`, corrections avec `supervisor-test`, lecture SQL dans SSMS, en lecture seule, sur `TraceabilityAcceptance`.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R03-01 | `New-Lot "R03-JOURNAL-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` ; `RECEIVED` | API | Observé le 2026-11-24 |
| R03-02 | `Add-Movement "R03-JOURNAL-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"` | `201` ; `SORTED` | API | Observé le 2026-11-24 |
| R03-03 | avec `supervisor-test` : `Read-Lot "R03-JOURNAL-$s"` pour lire le `movementId` du tri, puis `Replace-Movement "R03-JOURNAL-$s" <movementId> 'STA-TRI' 95 "${v}T07:00:00Z" 'MEASUREMENT_ERROR' $null`, puis `Read-Lot` | `201` ; le tri montre 95.00 (valable) et 90.00 (original), `correctionCount` à 1 | API | Observé le 2026-11-24 |
| R03-04 | dans SSMS, les deux requêtes ci-dessous (remplacer le suffixe du code par la valeur de `$s`) | `Movement` a 2 lignes pour le lot, le tri à 90.00 ; `MovementCorrection` a 1 ligne, pour le tri | SQL | Observé le 2026-11-24 |
| R03-05 | avec `supervisor-test` : `Correct-Lot "R03-JOURNAL-$s" "R03-JOURNAL-$s" 'FERME-NORD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null`, puis `Read-Lot` | `201` ; la fiche montre `Cherry` ; la correction de la fiche garde `Roma` (ancienne valeur) et `Cherry` (nouvelle) | API | Observé le 2026-11-24 |

Requêtes de R03-04 :

```sql
DECLARE @code NVARCHAR(30) = N'R03-JOURNAL-261124';  -- remplacer 261124 par la valeur de $s
SELECT m.MovementId, m.MovementType, m.QuantityKg, m.OccurredAt, m.AuthorName
FROM trace.Movement AS m
JOIN trace.Batch AS b ON b.BatchId = m.BatchId
WHERE b.BatchCode = @code
ORDER BY m.MovementId;

SELECT c.CorrectionId, c.MovementId, c.Kind, c.QuantityKg, c.ReasonCode, c.AuthorName
FROM trace.MovementCorrection AS c
JOIN trace.Movement AS m ON m.MovementId = c.MovementId
JOIN trace.Batch AS b ON b.BatchId = m.BatchId
WHERE b.BatchCode = @code
ORDER BY c.CorrectionId;
```

**Ce que ce groupe ne prouve pas** : qu'une personne qui a les droits sur la base ne pourrait pas modifier la table par un accès direct. Rien dans le journal ne se modifie par l'API (aucune route `PUT`, `DELETE` ni `PATCH`) ni par les procédures, mais les droits d'accès à la table seront restreints plus tard (voir [modele-de-donnees.md](modele-de-donnees.md)). La colonne d'auteur ne signalerait pas un tel accès.

## 10. R04-FIN : la fin de parcours (règle 4)

Lot `R04-FIN-$s`, compte `writer-test`, puis `reader-test` pour la dernière lecture.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R04-01 | `New-Lot "R04-FIN-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` ; `RECEIVED` | API | Observé le 2026-11-24 |
| R04-02 | `Add-Movement "R04-FIN-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"` | `201` ; `SORTED` | API | Observé le 2026-11-24 |
| R04-03 | `Add-Movement "R04-FIN-$s" 'STA-EMBALLAGE' 'PACKING' 90 "${v}T08:00:00Z"` | `201` ; `PACKED` | API | Observé le 2026-11-24 |
| R04-04 | `Add-Movement "R04-FIN-$s" 'STA-EXPEDITION' 'SHIPMENT' 90 "${v}T09:00:00Z"` | `201` ; `SHIPPED` | API | Observé le 2026-11-24 |
| R04-05 | `Add-Movement "R04-FIN-$s" 'STA-EXPEDITION' 'SHIPMENT' 90 "${v}T10:00:00Z"`, puis `Read-Lot "R04-FIN-$s"` | `422`, 50300 ; le lot reste `SHIPPED`, 4 mouvements | API | Observé le 2026-11-24 |
| R04-06 | avec `reader-test` : `Read-Lot "R04-FIN-$s"` | `200` ; `SHIPPED`, les 4 mouvements dans l'ordre, 90.00 kg | API | Observé le 2026-11-24 |

**Ce que ce groupe ne prouve pas** : « aucun lot n'est supprimé ». Cela repose sur l'absence de route de suppression dans l'API, lue dans le code, sans scénario.

## 11. R05-UNICITE : l'unicité des codes (règle 5)

Lot `R05-UNICITE-$s`. R05-01 et R05-02 réutilisent la ferme et la station de R00. R05-05 se fait avec `supervisor-test`, les autres avec `writer-test`.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R05-01 | `New-Farm 'FERME-NORD' 'Ferme du Nord' 'Nord'` (code qui existe déjà) | `409`, 50200 | API | Observé le 2026-11-24 |
| R05-02 | `New-Station 'STA-RECEPTION' 'Station de reception'` (code qui existe déjà) | `409`, 50201 | API | Observé le 2026-11-24 |
| R05-03 | `New-Lot "R05-UNICITE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` ; `RECEIVED` | API | Observé le 2026-11-24 |
| R05-04 | le même `New-Lot`, avec le même code | `409`, 50202 | API | Observé le 2026-11-24 |
| R05-05 | `Correct-Lot "R05-UNICITE-$s" "R05-UNICITE-$s-B" 'FERME-NORD' 'Roma' $r 'DATA_ENTRY_ERROR' $null`, puis `Read-Lot "R05-UNICITE-$s-B"` | `201` ; le lot s'appelle maintenant `R05-UNICITE-$s-B` | API | Observé le 2026-11-24 |
| R05-06 | `New-Lot "R05-UNICITE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` (ancien code du lot corrigé) | `409`, 50203 | API | Observé le 2026-11-24 |

Ce que fait un ancien code (le lire, écrire avec, le reprendre) est dans R11. R05 ne garde que « le code reste réservé ».

## 12. R06-FONCTION : la fonction de la station (règle 6)

Lot `R06-FONCTION-$s`, compte `writer-test`. Les stations viennent de R00.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R06-01 | `New-Lot "R06-FONCTION-$s" 'FERME-NORD' 'Roma' $r 100 'STA-VIDE' "${v}T06:00:00Z"`, puis `Read-Lot "R06-FONCTION-$s"` | `422`, 50303 ; `Read-Lot` donne `404` | API | Observé le 2026-11-24 |
| R06-02 | le même `New-Lot`, avec la station `'STA-TRI'` (a `SORTING`, pas `RECEPTION`) | `422`, 50303 | API | Observé le 2026-11-24 |
| R06-03 | le même `New-Lot`, avec la station `'STA-MIXTE'` | `201` ; `RECEIVED`, 100.00 kg | API | Observé le 2026-11-24 |
| R06-04 | `Add-Movement "R06-FONCTION-$s" 'STA-EMBALLAGE' 'SORTING' 90 "${v}T07:00:00Z"` (`STA-EMBALLAGE` n'a que `PACKING`) | `422`, 50303 ; le lot reste `RECEIVED` | API | Observé le 2026-11-24 |
| R06-05 | `Add-Movement "R06-FONCTION-$s" 'STA-MIXTE' 'SORTING' 90 "${v}T07:00:00Z"` | `201` ; `SORTED` (une station à deux fonctions accepte l'une et l'autre) | API | Observé le 2026-11-24 |
| R06-06 | `Add-Capability 'STA-MIXTE' 'SORTING'` (déjà déclarée) | `409`, 50203 | API | Observé le 2026-11-24 |

**Ce que ce groupe ne prouve pas** : la clé étrangère de la base elle-même, que [fonctionnel.md](fonctionnel.md) cite comme garantie. Les scénarios montrent le refus par la procédure et l'API, pas un `INSERT` direct dans la table.


## 13. R07-AUTEUR : l'auteur d'un mouvement (règle 7)

Lot `R07-AUTEUR-$s`. L'auteur est pris dans le jeton, jamais dans la demande. Son nom n'est montré qu'à `auditor` et `supervisor` (la visibilité par rôle est dans R09) ; l'identifiant n'est jamais renvoyé par l'API.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R07-01 | `writer-test` : `New-Lot "R07-AUTEUR-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` ; `RECEIVED` | API | Observé le 2026-11-24 |
| R07-02 | `writer-test` : `Add-Movement "R07-AUTEUR-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"` | `201` ; `SORTED` | API | Observé le 2026-11-24 |
| R07-03 | `Get-Trial auditor-test`, `Show-Token` (on relève ses rôles), puis `Read-Lot "R07-AUTEUR-$s"` | `200` ; `authorName` à `writer-test` sur les deux mouvements ; aucun identifiant d'auteur dans la réponse | API | Observé le 2026-11-24 |
| R07-04 | `Get-Trial writer-test`, `Show-Identity` (relever le `sub`), puis dans SSMS la requête ci-dessous | `AuthorName` à `writer-test` ; `AuthorId` égal au `sub` relevé | SQL | Observé le 2026-11-24 |
| R07-05 | `writer-test` : `Send-Api "/batches/R07-AUTEUR-$s/movements" ([ordered]@{ stationCode = 'STA-EMBALLAGE'; movementType = 'PACKING'; quantityKg = 90; occurredAt = "${v}T08:00:00Z"; authorName = 'intrus' })`, puis `Get-Trial auditor-test` et `Read-Lot "R07-AUTEUR-$s"` | on relève le code rendu ; si le mouvement est enregistré, son auteur est `writer-test`, jamais `intrus` | API | Observé le 2026-11-24 |

Requête de R07-04 :

```sql
USE TraceabilityAcceptance;
GO
DECLARE @code NVARCHAR(30) = N'R07-AUTEUR-261124';  -- remplacer 261124 par la valeur de $s
SELECT m.MovementId, m.MovementType, m.AuthorId, m.AuthorName
FROM trace.Movement AS m
JOIN trace.Batch AS b ON b.BatchId = m.BatchId
WHERE b.BatchCode = @code
ORDER BY m.MovementId;
```

**Ce que ce groupe ne prouve pas** : les anciens mouvements d'avant le lot 11 (« Données initiales »), un jeton sans nom d'utilisateur, le nom « du moment de la saisie » (il faudrait renommer un compte) et deux comptes `writer` différents (un seul existe). L'auteur d'une correction est dans R08.

## 14. R08-CORRECTION : les corrections des mouvements (règle 8)

Lot `R08-CORRECTION-$s`. R08-01 à R08-03 avec `writer-test`, puis `Read-Lot` pour relever les `movementId` de la réception (`<idR>`), du tri (`<idT>`) et de l'emballage (`<idE>`). R08-04 à R08-15 et R08-18 avec `supervisor-test` ; R08-16 et R08-17 avec `writer-test` ; R08-19 avec `auditor-test`. `<idS>` est le `movementId` de l'expédition, relevé après R08-17. Le message au destinataire d'un lot expédié est dans R10.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R08-01 | `New-Lot "R08-CORRECTION-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` ; `RECEIVED` | API | Observé le 2026-11-24 |
| R08-02 | `Add-Movement "R08-CORRECTION-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"` | `201` ; `SORTED` | API | Observé le 2026-11-24 |
| R08-03 | `Add-Movement "R08-CORRECTION-$s" 'STA-EMBALLAGE' 'PACKING' 85 "${v}T08:00:00Z"`, puis `Read-Lot` (relever `<idR>`, `<idT>`, `<idE>`) | `201` ; `PACKED`, 85.00 kg | API | Observé le 2026-11-24 |
| R08-04 | `Replace-Movement "R08-CORRECTION-$s" <idT> 'STA-TRI' 92 "${v}T07:00:00Z" 'MEASUREMENT_ERROR' $null`, puis `Read-Lot` | `201` ; tri valable 92.00, original 90.00 ; le lot reste à 85.00 kg | API | Observé le 2026-11-24 |
| R08-05 | `Replace-Movement "R08-CORRECTION-$s" <idT> 'STA-TRI' 105 "${v}T07:00:00Z" 'MEASUREMENT_ERROR' $null` (plus que la réception, 100.00) | `422`, 50304 | API | Observé le 2026-11-24 |
| R08-06 | `Replace-Movement "R08-CORRECTION-$s" <idT> 'STA-TRI' 80 "${v}T07:00:00Z" 'MEASUREMENT_ERROR' $null` (moins que l'emballage, 85.00) | `422`, 50304 | API | Observé le 2026-11-24 |
| R08-07 | `Replace-Movement "R08-CORRECTION-$s" <idR> 'STA-RECEPTION' 110 "${v}T06:00:00Z" 'DATA_ENTRY_ERROR' $null` (la réception peut monter, tant qu'elle reste au moins égale au tri) | `201` | API | Observé le 2026-11-24 |
| R08-08 | `Replace-Movement "R08-CORRECTION-$s" <idT> 'STA-MIXTE' 92 "${v}T07:00:00Z" 'DATA_ENTRY_ERROR' $null` (`STA-MIXTE` a `SORTING`) | `201` | API | Observé le 2026-11-24 |
| R08-09 | `Replace-Movement "R08-CORRECTION-$s" <idT> 'STA-EMBALLAGE' 92 "${v}T07:00:00Z" 'DATA_ENTRY_ERROR' $null` (`STA-EMBALLAGE` n'a pas `SORTING`) | `422`, 50303 | API | Observé le 2026-11-24 |
| R08-10 | `Replace-Movement "R08-CORRECTION-$s" <idT> 'STA-MIXTE' 92 "${v}T07:00:00Z" 'DATA_ENTRY_ERROR' $null` (valeurs identiques aux valeurs valables) | `422`, 50308 | API | Observé le 2026-11-24 |
| R08-11 | `Replace-Movement "R08-CORRECTION-$s" <idT> 'STA-MIXTE' 91 "${v}T07:00:00Z" 'OTHER' $null` (motif `OTHER` sans commentaire) | `400`, 50408 | API | Observé le 2026-11-24 |
| R08-12 | `Cancel-Movement "R08-CORRECTION-$s" <idR> 'DATA_ENTRY_ERROR' $null` | `422`, 50307 | API | Observé le 2026-11-24 |
| R08-13 | `Cancel-Movement "R08-CORRECTION-$s" <idT> 'DATA_ENTRY_ERROR' $null` (ce n'est pas le dernier mouvement valable) | `422`, 50306 | API | Observé le 2026-11-24 |
| R08-14 | `Cancel-Movement "R08-CORRECTION-$s" <idE> 'OTHER' 'essai de recette'`, puis `Read-Lot` | `201` ; le lot revient à `SORTED`, 92.00 kg | API | Observé le 2026-11-24 |
| R08-15 | `Replace-Movement "R08-CORRECTION-$s" <idE> 'STA-EMBALLAGE' 85 "${v}T08:00:00Z" 'DATA_ENTRY_ERROR' $null` (mouvement annulé) | `422`, 50305 | API | Observé le 2026-11-24 |
| R08-16 | `writer-test` : `Add-Movement "R08-CORRECTION-$s" 'STA-EMBALLAGE' 'PACKING' 90 "${v}T08:00:00Z"` | `201` ; `PACKED`, 90.00 kg | API | Observé le 2026-11-24 |
| R08-17 | `writer-test` : `Add-Movement "R08-CORRECTION-$s" 'STA-EXPEDITION' 'SHIPMENT' 90 "${v}T09:00:00Z"`, puis `Read-Lot` (relever `<idS>`) | `201` ; `SHIPPED` | API | Observé le 2026-11-24 |
| R08-18 | `Cancel-Movement "R08-CORRECTION-$s" <idS> 'DATA_ENTRY_ERROR' $null`, puis `Read-Lot` | `201` ; le lot revient à `PACKED`, 90.00 kg (le seul cas où un lot expédié bouge) | API | Observé le 2026-11-24 |
| R08-19 | `auditor-test` : `Read-Lot "R08-CORRECTION-$s"` | l'historique des corrections montre `supervisor-test` comme auteur ; les valeurs d'origine des mouvements sont intactes | API | Observé le 2026-11-24 |

**Ce que ce groupe ne prouve pas** : les corrections par l'interface (R10), l'heure d'une correction (R12) et le motif trop long (50409).

## 15. R09-ROLES : les rôles (règle 9)

Lot `R09-ROLES-$s`. Les trois premiers scénarios préparent un lot avec une correction, pour que les noms des mouvements et ceux des corrections se voient dans les lectures qui suivent. `<idT>` est le `movementId` du tri, relevé avec `Read-Lot`. Pour R09-14, `$global:Token = $null` vide le jeton avant la lecture. R09-15 et R09-16 demandent l'interface (`npm run dev` dans `web/`, connexion à Keycloak dans le navigateur).

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R09-01 | `writer-test` : `New-Lot "R09-ROLES-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` | API | Observé le 2026-11-24 |
| R09-02 | `writer-test` : `Add-Movement "R09-ROLES-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"`, puis `Read-Lot` (relever `<idT>`) | `201` | API | Observé le 2026-11-24 |
| R09-03 | `supervisor-test` : `Replace-Movement "R09-ROLES-$s" <idT> 'STA-TRI' 92 "${v}T07:00:00Z" 'MEASUREMENT_ERROR' $null` | `201` | API | Observé le 2026-11-24 |
| R09-04 | `reader-test` : `Read-Lot "R09-ROLES-$s"` | `200` ; `authorName` à `null`, y compris dans les corrections | API | Observé le 2026-11-24 |
| R09-05 | `reader-test` : `Add-Movement "R09-ROLES-$s" 'STA-EMBALLAGE' 'PACKING' 85 "${v}T08:00:00Z"` | `403` | API | Observé le 2026-11-24 |
| R09-06 | `writer-test` : `Read-Lot "R09-ROLES-$s"` | `200` ; `authorName` à `null` | API | Observé le 2026-11-24 |
| R09-07 | `writer-test` : `Replace-Movement "R09-ROLES-$s" <idT> 'STA-TRI' 91 "${v}T07:00:00Z" 'MEASUREMENT_ERROR' $null` | `403` | API | Observé le 2026-11-24 |
| R09-08 | `supervisor-test` : `Read-Lot "R09-ROLES-$s"` | `200` ; noms visibles (`writer-test` sur les mouvements, `supervisor-test` sur la correction) | API | Observé le 2026-11-24 |
| R09-09 | `supervisor-test` : `Add-Movement "R09-ROLES-$s" 'STA-EMBALLAGE' 'PACKING' 85 "${v}T08:00:00Z"` | `403` | API | Observé le 2026-11-24 |
| R09-10 | `auditor-test` : `Get-Trial`, `Show-Token` (on relève ses rôles), puis `Read-Lot "R09-ROLES-$s"` | `200` ; noms visibles | API | Observé le 2026-11-24 |
| R09-11 | `auditor-test` : `Add-Movement "R09-ROLES-$s" 'STA-EMBALLAGE' 'PACKING' 85 "${v}T08:00:00Z"` | `403` | API | Observé le 2026-11-24 |
| R09-12 | `auditor-test` : `Replace-Movement "R09-ROLES-$s" <idT> 'STA-TRI' 91 "${v}T07:00:00Z" 'MEASUREMENT_ERROR' $null` | `403` | API | Observé le 2026-11-24 |
| R09-13 | `norole-test` : `Get-Trial`, `Show-Token` (on relève ses rôles), puis `Read-Lot "R09-ROLES-$s"` | `403` | API | Observé le 2026-11-24 |
| R09-14 | `$global:Token = $null`, puis `Read-Lot "R09-ROLES-$s"` | `401` | API | Observé le 2026-11-24 |
| R09-15 | `reader-test` : ouvrir `http://localhost:5173/batches/R09-ROLES-aammjj` (le code du lot avec la valeur de `$s`) | pas de colonne d'auteur, pas de formulaire d'écriture | Interface | Observé le 2026-11-24 |
| R09-16 | `auditor-test` : même page | colonnes d'auteur visibles, pas de formulaire d'écriture | Interface | Observé le 2026-11-24 |

**Ce que ce groupe ne prouve pas** : l'interface pour `writer` et `supervisor` (formulaires de saisie et de correction, vus dans R10 et NOMINAL), les autres routes de lecture (fermes, stations) avec chaque rôle, et un rôle donné par un autre moyen que Keycloak.

## 16. R10-DESTINATAIRE : le message au destinataire d'un lot expédié (règle 10)

Lot `R10-DESTINATAIRE-$s`. R10-01, R10-04 : API. Les autres : interface (`npm run dev`, connexion Keycloak dans le navigateur) avec `supervisor-test`. R10-01 regroupe plusieurs appels (préparation, comme R00-02).

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R10-01 | `writer-test` : `New-Lot "R10-DESTINATAIRE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"`, puis `Add-Movement` : tri 95 kg à 07:00, emballage 90 kg à 08:00, expédition 90 kg à 09:00 (même format d'heure), puis `Read-Lot` (relever `<idS>`, le numéro de l'expédition) | quatre `201` ; lot `SHIPPED` | API | Observé le 2026-11-25 |
| R10-02 | `supervisor-test` : « Corriger un mouvement », l'expédition, « Remplacer les valeurs », quantité 90 → 88, motif « Erreur de mesure » | correction acceptée ; encadré « Ce lot avait été expédié : prévenez le destinataire. » avec son message ; « Copier le message » affiche « Message copié. » ou « Copie impossible… » (on relève lequel) | Interface | Observé le 2026-11-25 |
| R10-03 | « Corriger la fiche » : variété `Roma` → `Cherry`, motif « Erreur de saisie » | correction acceptée ; encadré avec le message de la fiche | Interface | Observé le 2026-11-25 |
| R10-04 | `supervisor-test` : `Replace-Movement "R10-DESTINATAIRE-$s" <idS> 'STA-EXPEDITION' 87 "${v}T09:00:00Z" 'MEASUREMENT_ERROR' $null` | `201`, sans aucun message pour le destinataire (un appel direct à l'API n'en donne pas) | API | Observé le 2026-11-25 |
| R10-05 | « Corriger un mouvement » : annuler l'expédition, motif « Erreur de saisie » | encadré destinataire ; le lot revient à `PACKED` | Interface | Observé le 2026-11-25 |
| R10-06 | « Corriger la fiche » : variété `Cherry` → `Roma`, sur le lot maintenant `PACKED`, motif « Erreur de saisie » | correction acceptée, sans encadré (le lot n'était plus expédié) | Interface | Observé le 2026-11-25 |

Ce que R10 ne prouve pas : que rien n'est enregistré ni envoyé. On ne peut constater qu'une absence de trace, ce qu'un scénario ne montre pas.

## 17. R11-FICHE : la correction de la fiche d'un lot (règle 11)

Lots `R11-FICHE-$s` (ferme `FERME-NORD`, variété `Roma`, récolte `$r`, réception le jour `$v`) et `R11-AUTRE-$s`, pour essayer de prendre le code d'un autre lot. R11-01, R11-02 et R11-07 avec `writer-test` ; les autres avec `supervisor-test`. `Correct-Lot` prend : code actuel, nouveau code, ferme, variété, jour de récolte, motif, commentaire. Le cas « un lot expédié peut être corrigé » est couvert par R10-03.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R11-01 | `New-Lot "R11-FICHE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` | API | Observé le 2026-11-25 |
| R11-02 | `New-Lot "R11-AUTRE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` | API | Observé le 2026-11-25 |
| R11-03 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-NORD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null`, puis `Read-Lot` | `201` ; statut et quantité du lot inchangés ; la correction garde l'ancienne et la nouvelle valeur | API | Observé le 2026-11-25 |
| R11-04 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-SUD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null` | `201` | API | Observé le 2026-11-25 |
| R11-05 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s-B" 'FERME-SUD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null` | `201` | API | Observé le 2026-11-25 |
| R11-06 | `Read-Lot "R11-FICHE-$s"` (l'ancien code) | `200` ; le lot, sous son code actuel `R11-FICHE-$s-B` | API | Observé le 2026-11-25 |
| R11-07 | `writer-test` : `Add-Movement "R11-FICHE-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"` (ancien code) | `404`, 50104 ; le message donne le code actuel | API | Observé le 2026-11-25 |
| R11-08 | `supervisor-test` : `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s-C" 'FERME-SUD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null` (ancien code) | `404`, 50104 | API | Observé le 2026-11-25 |
| R11-09 | `Correct-Lot "R11-FICHE-$s-B" "R11-AUTRE-$s" 'FERME-SUD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null` (code actuel d'un autre lot) | `409`, 50202 | API | Observé le 2026-11-25 |
| R11-10 | `Correct-Lot "R11-AUTRE-$s" "R11-FICHE-$s" 'FERME-NORD' 'Roma' $r 'DATA_ENTRY_ERROR' $null` (ancien code de l'autre lot) | `409`, 50203 | API | Observé le 2026-11-25 |
| R11-11 | `Correct-Lot "R11-FICHE-$s-B" "R11-FICHE-$s" 'FERME-SUD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null` (le lot reprend son ancien code) | `201` (un lot peut reprendre un code qu'il a eu) | API | Observé le 2026-11-25 |
| R11-12 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-SUD' 'Cherry' $r 'DATA_ENTRY_ERROR' $null` (valeurs identiques) | `422`, 50308 | API | Observé le 2026-11-25 |
| R11-13 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-SUD' 'cherry' $r 'DATA_ENTRY_ERROR' $null` (casse seule) | `201` | API | Observé le 2026-11-25 |
| R11-14 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-SUD' 'Roma' $r 'MEASUREMENT_ERROR' $null` | `400`, 50407 | API | Observé le 2026-11-25 |
| R11-15 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-SUD' 'Roma' $r 'OTHER' $null` | `400`, 50408 | API | Observé le 2026-11-25 |
| R11-16 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-SUD' 'cherry' ($d.ToString('yyyy-MM-dd')) 'DATA_ENTRY_ERROR' $null` (récolte le jour J, après la réception du jour `$v`) | `422`, 50309 | API | Observé le 2026-11-25 |
| R11-17 | `Correct-Lot "R11-FICHE-$s" "R11-FICHE-$s" 'FERME-SUD' 'cherry' $v 'DATA_ENTRY_ERROR' $null` (récolte le jour de la réception) | `201` | API | Observé le 2026-11-25 |

## 18. R12-HEURE : l'heure des mouvements (règle 12)

Lot `R12-HEURE-$s` (récolte `$r`). « Futur » veut dire maintenant + 10 minutes en UTC, recalculé juste avant chaque scénario concerné : `$f = (Get-Date).ToUniversalTime().AddMinutes(10).ToString('yyyy-MM-ddTHH:mm:ssZ')`. R12-01 à R12-07 et R12-12 à R12-14 avec `writer-test` ; R12-08 à R12-11 avec `supervisor-test`.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| R12-01 | `$f` recalculé, puis `New-Lot "R12-HEURE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' $f`, puis `Read-Lot "R12-HEURE-$s"` | `422`, 50310 ; `Read-Lot` donne `404` | API | Observé le 2026-11-25 |
| R12-02 | `New-Lot "R12-HEURE-$s" 'FERME-NORD' 'Roma' $r 100 'STA-RECEPTION' "${v}T06:00:00Z"` | `201` (une heure passée est acceptée) | API | Observé le 2026-11-25 |
| R12-03 | `Add-Movement "R12-HEURE-$s" 'STA-TRI' 'SORTING' 90 "${v}T06:00:00Z"` (égale à la réception) | `422`, 50311 | API | Observé le 2026-11-25 |
| R12-04 | `Add-Movement "R12-HEURE-$s" 'STA-TRI' 'SORTING' 90 "${v}T05:00:00Z"` (avant la réception) | `422`, 50311 | API | Observé le 2026-11-25 |
| R12-05 | `$f` recalculé, puis `Add-Movement "R12-HEURE-$s" 'STA-TRI' 'SORTING' 90 $f` | `422`, 50310 | API | Observé le 2026-11-25 |
| R12-06 | `Add-Movement "R12-HEURE-$s" 'STA-TRI' 'SORTING' 90 "${v}T07:00:00Z"`, puis `Read-Lot` (relever `<idT>`, le numéro du tri) | `201` ; `SORTED` | API | Observé le 2026-11-25 |
| R12-07 | `Add-Movement "R12-HEURE-$s" 'STA-EMBALLAGE' 'PACKING' 85 "${v}T08:00:00Z"` | `201` ; `PACKED` | API | Observé le 2026-11-25 |
| R12-08 | `supervisor-test` : `Replace-Movement "R12-HEURE-$s" <idT> 'STA-TRI' 90 "${v}T08:30:00Z" 'DATA_ENTRY_ERROR' $null` (après l'emballage) | `422`, 50311 | API | Observé le 2026-11-25 |
| R12-09 | `Replace-Movement "R12-HEURE-$s" <idT> 'STA-TRI' 90 "${v}T06:00:00Z" 'DATA_ENTRY_ERROR' $null` (égale à la réception) | `422`, 50311 | API | Observé le 2026-11-25 |
| R12-10 | `Replace-Movement "R12-HEURE-$s" <idT> 'STA-TRI' 90 "${v}T07:30:00Z" 'DATA_ENTRY_ERROR' $null` | `201` | API | Observé le 2026-11-25 |
| R12-11 | `$f` recalculé, puis `Replace-Movement "R12-HEURE-$s" <idT> 'STA-TRI' 90 $f 'DATA_ENTRY_ERROR' $null` | `422`, 50310 (le futur passe avant l'ordre) | API | Observé le 2026-11-25 |
| R12-12 | `writer-test` : `Add-Movement "R12-HEURE-$s" 'STA-EXPEDITION' 'SHIPMENT' 85 "${v}T09:00:00"` (sans `Z`) | `400`, sans `errorCode` (les heures doivent être en UTC) | API | Observé le 2026-11-25 |
| R12-13 | `Add-Movement "R12-HEURE-$s" 'STA-EXPEDITION' 'SHIPMENT' 85 "${v}T09:00:00Z"` | `201` ; `SHIPPED` | API | Observé le 2026-11-25 |
| R12-14 | `$f` recalculé, puis `Add-Movement "R12-HEURE-$s" 'STA-EXPEDITION' 'SHIPMENT' 85 $f` | `422`, 50300 (le lot expédié refuse d'abord, avant le contrôle de l'heure) | API | Observé le 2026-11-25 |

Ce que R12 ne prouve pas : la limite exacte de 5 minutes (le cahier prend +10 minutes pour être sûr du refus), deux appels simultanés sur le même lot, une horloge d'ordinateur en avance. Ce sont des points restés ouverts.

## 19. NOMINAL : le parcours complet de bout en bout

Lot `NOM-PARCOURS-$s`. Il reprend l'exemple de la section 6 de [fonctionnel.md](fonctionnel.md) : 500, 470, 465 et 465 kg. Tout se fait dans l'interface avec `writer-test`, sauf NOM-08 (API). Les heures sont celles du jour `$v` (06:00, 07:00, 08:00, 09:00) et la récolte celle de `$r`. Le groupe crée sa propre ferme et sa propre station : il ne dépend pas de R00. NOM-03 regroupe quatre ajouts de fonction, comme R00-02 pour sa station. Observé le 2026-11-25 sur le lot `NOM-PARCOURS2-261125` : le code `NOM-PARCOURS-261125` avait servi à un premier essai, créé par erreur de saisie avec l'heure du formulaire (25/11/2026 10:01) au lieu de `${v}T06:00` ; ce lot est resté `RECEIVED`.

| ID | Étapes | Attendu | Canal | Statut |
|---|---|---|---|---|
| NOM-01 | `/new-farm` : créer la ferme `NOM-FERME` | message de succès | Interface | Observé le 2026-11-25 |
| NOM-02 | `/new-station` : créer la station `NOM-STATION` | la page de la station s'ouvre | Interface | Observé le 2026-11-25 |
| NOM-03 | page de la station : ajouter les quatre fonctions (réception, tri, emballage, expédition) | les quatre fonctions apparaissent sur la page | Interface | Observé le 2026-11-25 |
| NOM-04 | `/new-batch` : créer le lot `NOM-PARCOURS-$s`, ferme `NOM-FERME`, station `NOM-STATION`, 500 kg | la page du lot s'ouvre ; statut `RECEIVED` | Interface | Observé le 2026-11-25 |
| NOM-05 | ajouter le tri à 470 kg (le formulaire propose l'étape suivante et la quantité actuelle) | `SORTED` | Interface | Observé le 2026-11-25 |
| NOM-06 | ajouter l'emballage à 465 kg | `PACKED` | Interface | Observé le 2026-11-25 |
| NOM-07 | ajouter l'expédition à 465 kg | `SHIPPED` ; plus de formulaire d'ajout | Interface | Observé le 2026-11-25 |
| NOM-08 | `reader-test` : `Read-Lot "NOM-PARCOURS-$s"` | les quatre mouvements dans l'ordre ; `SHIPPED` ; 465.00 kg ; comme dans l'interface | API | Observé le 2026-11-25 |
| NOM-09 | `/batches` : filtrer par statut `SHIPPED` et par la ferme `NOM-FERME` | le lot est dans la liste | Interface | Observé le 2026-11-25 |
