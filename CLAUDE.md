# CLAUDE.md — traceability-api-dotnet

## Projet
API ASP.NET Core + SQL Server de traçabilité (fermes, lots, stations, mouvements).
Projet d'apprentissage : scénario simplifié et inventé.
Il donne une base, pas de l'expérience. Le README dit ce que le projet ne prouve pas.

## Façon de travailler
- Claude écrit le code et la doc, seulement après un plan détaillé approuvé par Mohamed.
- Claude n'écrit que les fichiers du plan, montre le diff et explique en mots simples.
- Étape d'explication avant chaque commit : Claude explique, pose 2-3 questions,
  Mohamed répond avec ses propres mots.
- Mohamed lance les scripts SQL (SSMS) et les tests, relit, valide et commit.
- Un lot = une branche = une PR. Une seule étape à la fois, commandes PowerShell précises.

## Commandes
Depuis la racine du dépôt, dans PowerShell (la solution est `Traceability.slnx`) :
- Compiler : `dotnet build Traceability.slnx`
- Tests unitaires, sans base : `dotnet test tests/Traceability.UnitTests`
- Tests d'intégration : `dotnet test tests/Traceability.IntegrationTests`. Attention : au début de chaque exécution, ils vident les 5 tables de `TraceabilityTest` (5 `DELETE` sans `WHERE`, précédés d'un contrôle du nom de la base). Ils lisent `ConnectionStrings__Test`.
- Tous les tests : `dotnet test Traceability.slnx`
- Lancer l'API : `dotnet run --project src/Traceability.Api --launch-profile https`, puis ouvrir `https://localhost:7080/swagger` à la main (`dotnet run` n'ouvre pas le navigateur). Elle lit `ConnectionStrings__Default`. Arrêt : Ctrl+C.
- Certificat de développement HTTPS, une fois, lancé par Mohamed : `dotnet dev-certs https --trust`.
- Variables d'environnement, définies par Mohamed au niveau de son compte Windows : `ConnectionStrings__Default` (base `TraceabilityDev`) et `ConnectionStrings__Test` (base `TraceabilityTest`). Authentification Windows, aucun mot de passe. Avec .NET, `TrustServerCertificate=True` est nécessaire en local (le certificat de SQL Server n'est pas approuvé, observé le 2026-10-20) : jamais pour un serveur distant. Les valeurs ne sont écrites nulle part dans le dépôt. Un programme déjà ouvert ne voit pas une variable créée après son démarrage : rouvrir VS Code.
- Interface web, dans `web/`, lancée par Mohamed (le texte affiché est en français) : `npm install` (une fois), `npm run dev` (serveur Vite sur `http://localhost:5173/`, port fixé ; il demande l'API lancée dans un autre terminal), `npm run lint`, `npm run build` (vérifie les types, écrit `dist/`) et `npm test` (Vitest, 178 tests, sans API ni base). Aucun fichier `.env` n'est créé par Claude ; l'adresse de l'API est `https://localhost:7080`, ou `VITE_API_URL`.
- Arrêter l'API (Ctrl+C) avant `dotnet test`, qui doit pouvoir recompiler. Après avoir remis un fichier par copie (casse volontaire), mettre à jour sa date de modification, sinon `dotnet` peut ne pas recompiler (observé au lot 4a).
- CI : `.github/workflows/ci.yml`, lancée à chaque push et à chaque pull request (tâches `backend` et `frontend`). Pour la rejouer : onglet Actions de GitHub, « Re-run all jobs ». Une CI verte ne remplace pas les essais à la main décrits dans `docs/verification.md`.
Scripts SQL numérotés dans `database/`, exécutés par Mohamed dans SSMS.

## Secrets
- Ne jamais lire, créer ni afficher : `.env`, `appsettings.*.json` locaux, user-secrets,
  chaînes de connexion avec identifiants.
- Connexion locale en authentification Windows (pas de mot de passe). La CI utilise l'authentification SQL (voir ci-dessous).
- La CI (`.github/workflows/ci.yml`) se connecte à SQL Server avec le secret de dépôt `MSSQL_SA_PASSWORD`. Claude ne lit, ne crée, ne modifie ni n'affiche jamais ce secret ni sa valeur : Mohamed le gère dans les réglages de GitHub.

## Vérité
- Ne jamais dire que ça marche sans l'avoir exécuté et observé.
- L'avancement (« Prévu », « Prouvé », « Terminé ») vit dans le README et dans `docs/verification.md`. « Prouvé » seulement après tests exécutés et observés.
- Les docs de conception (`docs/fonctionnel.md`, `docs/modele-de-donnees.md`) décrivent l'intention : elles n'ont pas de statut et ne changent que si une décision de conception change.
- ADR seulement pour une vraie décision avec alternatives. Le corps d'un ADR est un
  enregistrement : seuls le statut et les notes changent.

## SQL
- Procédures stockées pour les règles métier (ordre des statuts, quantité qui ne monte pas).
- Claude signale tout DROP / TRUNCATE / DELETE sans WHERE avant exécution.

## Git
- Pas de `git commit` ni `git push` par Claude (lecture seule OK : status, diff, log).
- Rester sur la branche courante : Mohamed crée et supprime les branches.
- Ne pas toucher à `.github/` ni à la config racine sans demande explicite et nommée.
- `main` est protégée (ruleset `protect-main`, voir l'ADR 0010) : pas de poussée directe, tout passe par une pull request, et `backend` et `frontend` doivent être verts pour fusionner. Mohamed fusionne.
- Messages de commit : courts, impératif, anglais, sans Co-Authored-By.

## Langues
Docs en français. Code, noms SQL, commits et erreurs d'API en anglais. Chat en français.
