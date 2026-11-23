# Cahier de recette fonctionnelle

Ce cahier prouve, sur une base à part, que les règles de [fonctionnel.md](fonctionnel.md) sont tenues par l'application. Il se rejoue : chaque scénario a un identifiant, des étapes, un résultat attendu et un statut. Il doit évoluer avec l'application : chaque nouvelle règle ou modification fonctionnelle y ajoute ou y change des scénarios.

État au lot 13a (2026-11-23) : la base de recette, les outils et la préparation sont en place et essayés. Les scénarios des règles (R01 à R12 et NOMINAL) sont écrits et rejoués au lot 13b.

## 1. Principes

- **Base** : `TraceabilityAcceptance`, créée à part de `TraceabilityDev` et de `TraceabilityTest`. `dotnet test` ne la touche pas, et le script `900` accepte son nom (voir l'[ADR 0002](adr/0002-tests-sur-base-reelle.md), note du lot 13a).
- **Un groupe par règle** de `fonctionnel.md`, un lot par groupe. Les identifiants de scénario ont la forme `R01-01` (groupe, puis numéro). Deux groupes de service : `R00-PREPARATION` (données de référence) et `R99-OUTILS` (contrôle de l'outillage).
- **Code du lot** : `Rxx-GROUPE-aammjj`, par exemple `R01-ORDRE-261123`. Un lot rejoué le jour même reçoit un suffixe (`-2`, par exemple). Un code de lot contient 30 caractères au plus : des lettres sans accent, des chiffres, `-` et `_`.
- **Canal** : chaque scénario dit s'il est essayé par l'API, par l'interface, ou par les deux.
- **Statuts** : `Observé le AAAA-MM-JJ` (exécuté et relevé), `Non essayé`, `Échec` (avec ce qui a été vu). Un scénario n'est marqué observé qu'après son exécution.
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

Les autres fermes et stations dont les scénarios auront besoin seront ajoutées au lot 13b.

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
