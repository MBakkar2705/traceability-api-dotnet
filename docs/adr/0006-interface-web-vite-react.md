# ADR 0006 : interface web en Vite, React et TypeScript

Statut : **Accepté** (2026-10-21)

## Contexte

Le lot 4 ajoute une interface web à l'API. Il a été coupé en deux : le lot 4a (lecture : 5 écrans) et le lot 4b (écriture : formulaires). Cet ADR garde les choix d'outils du lot 4a, faits un à un avant d'écrire le code.

## Décision

L'interface est dans le dossier `web/` du même dépôt. Les choix :

- **Vite + React, en partant de zéro** (modèle `react-ts`), sans framework. Versions installées : React 19.3.1, Vite 8.3.5, TypeScript 6.0.3.
- **TypeScript.** Les types des réponses de l'API sont écrits à la main (`src/api/types.ts`) : rien ne les garde synchronisés avec le code C#. Le script `build` lance `tsc -b` avant `vite build` (observé).
- **Tailwind CSS 4.3.3** (avec son plugin pour Vite). Les couleurs de l'interface sont définies une seule fois, comme variables de thème, dans `src/index.css`.
- **React Router 7.18.4, en mode « declarative »** : une adresse par écran, les filtres et la page dans l'adresse. La version 8.5.0 existait ; elle demande Node 22.22.0 ou plus, et la machine a Node 22.16.0 : la 7.18.4 a été retenue. Au lot 4b, Node a été mis à jour en 22.23.4, ce qui permet la 8.5.0 ; elle n'a pas été essayée (voir « à prendre en compte » du README).
- **Appels à l'API avec `fetch`, écrits à la main** : un seul module (`src/api/client.ts`, une fonction par route) et un crochet `useApi` qui annule l'appel devenu inutile avec `AbortController`.
- **Tests : Vitest 5.0.5 et React Testing Library 16.3.3** (avec `@testing-library/dom` 10.4.2 et `jsdom` pour simuler le navigateur). `fetch` est remplacé par `vi.stubGlobal`.
- **Linter : Oxlint 1.89.0** (le choix proposé par l'outil de création du projet). Les règles `react/rules-of-hooks` et `react/exhaustive-deps` (qui repère les dépendances oubliées d'un `useEffect`) sont activées dans `web/.oxlintrc.json`.
- **Gestionnaire de paquets : npm.**

## Alternatives écartées

- **Un framework** (par exemple Next.js, ou React Router en mode framework) : navigation et conventions fournies, mais plus de notions à apprendre d'un coup, alors que l'API fait déjà la partie serveur. Non essayé.
- **JavaScript au lieu de TypeScript** : aucun type à écrire, mais une faute de nom de champ ne se verrait qu'à l'exécution. Non essayé.
- **CSS simple** (fichiers `.css`) : aucune dépendance, mais tout le style à écrire à la main. Non essayé.
- **React Router en mode « data »** (les données d'un écran chargées par le routeur) ou **pas de routeur** (l'écran gardé dans l'état de React) : le premier demande plus de notions, le second ne donne ni adresse par écran, ni lien vers un lot, ni retour du navigateur. Non essayés.
- **Une bibliothèque de requêtes** (par exemple TanStack Query), qui fournit le cache et les états de chargement et d'erreur : une dépendance de plus. Non essayée.
- **Un faux serveur pour les tests** (par exemple MSW), **aucun test d'interface**, ou **un navigateur piloté par les tests** : non faits. Ces deux derniers restent dans « à prendre en compte » (voir le README).
- **ESLint** à la place d'Oxlint : non essayé.

## Conséquences

Positives :

- Les types, les appels à l'API et les couleurs sont chacun regroupés à un seul endroit.
- 79 tests de l'interface, qui tournent en environ 20 secondes sur cette machine (19,6 s à la dernière exécution).
- Le crochet `useApi` n'affiche jamais la réponse lente d'un appel remplacé : testé, et vu par la casse volontaire (voir [verification.md](../verification.md), section 11).
- Le linter a trouvé un vrai défaut dans le code de `useApi` (un `setState` appelé de façon synchrone dans un effet), corrigé.

Négatives :

- Les types de l'API sont recopiés à la main : un champ renommé côté C# ne se verrait qu'à l'exécution, ou dans les tests.
- Pas de cache des appels : la liste des lots refait l'appel, donc le calcul du total, à chaque changement de page (voir [verification.md](../verification.md), section 11.3).
- Navigation et appels sont écrits par nous : si l'écriture (lot 4b) s'y prête mal, le mode « data » de React Router ou une bibliothèque de requêtes seront à reconsidérer.
- L'interface est vérifiée dans Edge et dans le mode « mobile » de ses outils de développement (468 pixels de large), pas sur un vrai téléphone.

## Notes

- 2026-10-21 : lot 4a. Observé : lint propre (0 avertissement), `npm run build` réussi, 79 tests réussis (voir [verification.md](../verification.md), section 11). Non observé : un autre navigateur, un vrai téléphone, l'accessibilité (lecteur d'écran, contraste) et le comportement du mode « declarative » quand les formulaires du lot 4b seront ajoutés.
- 2026-10-22 : lot 4b. Observé : lint propre (0 avertissement), `npm run build` réussi, 178 tests réussis (voir [verification.md](../verification.md), section 12). Les formulaires ont été écrits avec les mêmes outils (`fetch`, hooks, mode « declarative ») : le mode « data » de React Router et une bibliothèque de requêtes n'ont pas été nécessaires ; le seul ajout est le paramètre `refresh` de `useApi`, pour relire après une écriture. Non observé : un autre navigateur, un vrai téléphone, l'accessibilité (lecteur d'écran, contraste).
