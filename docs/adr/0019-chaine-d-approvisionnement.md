# ADR 0019 : chaîne d'approvisionnement : licence MIT, images fixées par tag et empreinte, Dependabot sans regroupement avec délai, CodeQL par défaut

Statut : **Accepté** (2026-11-27)

## Contexte

Le dépôt est public et sert de projet d'apprentissage. Avant le lot 15 : aucune licence (le code était visible mais personne n'avait le droit de le réutiliser), aucune politique de sécurité, des images Docker désignées par des étiquettes qui bougent (`mssql/server:2025-latest`, `node:22-slim`, `dotnet/sdk:10.0`, `dotnet/aspnet:10.0`), aucune mise à jour de version automatique et CodeQL non configuré. Rien n'avertissait donc d'une dépendance en retard, ni d'une faille dans le code ou dans une bibliothèque, et une image pouvait changer de contenu sans que le dépôt change.

## Décision

- **Licence MIT**, `Copyright (c) 2026 Mohamed Bakkar`, et un `SECURITY.md` qui désigne le signalement privé de GitHub comme seul canal et dit honnêtement ce qu'est le projet (un seul mainteneur, pas de délai de réponse garanti, la pile Docker est une démonstration locale).
- **Images fixées par tag précis et par empreinte** (`tag@sha256:…`) : `Dockerfile`, `web/Dockerfile`, `compose.yaml` et le conteneur SQL Server de `ci.yml`. C'est la même méthode que pour les actions GitHub, fixées par empreinte de commit : Dependabot propose les mises à jour de façon visible.
- **Dependabot** (`.github/dependabot.yml`) : NuGet, npm, actions GitHub, `Dockerfile` et `compose.yaml`, chaque semaine, 3 pull requests ouvertes au plus par entrée, **sans regroupement**, avec un **délai de 7 jours** avant de proposer une nouvelle version (sauf pour les actions GitHub). Les mises à jour de sécurité de Dependabot sont activées, et le secret `MSSQL_SA_PASSWORD` existe aussi côté Dependabot.
- **CodeQL en réglage par défaut** (GitHub Actions, C#, JavaScript/TypeScript, requêtes « Default », push et pull request vers `main`, plus un scan hebdomadaire).
- **Deux mesures annexes** : le conteneur `web` tourne sous l'utilisateur `node`, et `.env*` est exclu des constructions d'images (`.dockerignore`).

## Alternatives écartées

- **Aucune licence.** Le code resterait visible mais personne n'aurait le droit de le réutiliser, ce qui n'a pas de sens pour un projet qu'on montre.
- **Une autre licence libre** (Apache 2.0, GPL). Non retenues : la MIT est la plus courte et n'impose que de garder la mention de copyright et le texte de la licence ; la GPL impose en plus que le code dérivé reste libre.
- **Étiquettes qui bougent** (`latest`, `22-slim`). Écartées : le contenu change sans que le dépôt change.
- **Tag précis seul, sans empreinte.** Écarté : un tag peut être déplacé ; l'empreinte désigne un contenu précis. Le tag précis reste dans le texte parce qu'une empreinte seule est illisible pour une personne.
- **Empreinte seule.** Écartée : illisible.
- **Dependabot avec regroupement** (une seule pull request pour plusieurs mises à jour). Écarté : plus difficile à relire et à annuler pour une seule dépendance. Le prix est le nombre de pull requests, non observé.
- **Pas de délai** avant de proposer une version. Écarté : le délai laisse le temps de voir une version piégée ou retirée.
- **CodeQL en réglage avancé** (un fichier de workflow dans le dépôt). Écarté : le réglage par défaut suffit au projet ; l'avancé serait versionné mais à maintenir.

## Conséquences

Positives :

- Une image construite aujourd'hui l'est de la même façon demain, et un changement d'image passe par une pull request visible.
- Une dépendance en retard ou une faille connue donne une pull request ou une alerte au lieu de rester inaperçue.
- CodeQL a analysé les trois langages sur `main` sans alerte ([verification.md](../verification.md), section 28, Q6).

Négatives :

- Les mises à jour de sécurité de Dependabot, CodeQL, la double authentification et les secrets sont des réglages de GitHub : ils ne sont pas dans les fichiers du dépôt et ne se rejouent pas depuis le code.
- La CI ne construit ni `compose.yaml` ni `web/Dockerfile` : avant de fusionner une pull request de Dependabot qui les touche, un `docker compose up -d --build` à la main est nécessaire, jusqu'au lot 17.
- Plus de pull requests à relire. Le volume au premier passage n'est pas observé.
- Non prouvé : que GitHub accepte l'empreinte dans `services:` de `ci.yml`, que Dependabot trouve `compose.yaml` et met à jour le tag et l'empreinte ensemble, que son délai vaut pour les actions GitHub.
- « 0 alerte » de CodeQL ne dit pas que le code est sans faille.

## Notes

- 2026-11-27 (lot 15) : décisions prises pendant le lot, sur les commits `9c41140`, `d5b6198` et `fa0aee7`. Constat et points non prouvés : [verification.md](../verification.md), section 28.
