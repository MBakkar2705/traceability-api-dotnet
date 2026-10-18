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
À compléter quand le projet .NET existera (dotnet build / dotnet test).
Scripts SQL numérotés dans `database/`, exécutés par Mohamed dans SSMS.

## Secrets
- Ne jamais lire, créer ni afficher : `.env`, `appsettings.*.json` locaux, user-secrets,
  chaînes de connexion avec identifiants.
- Connexion locale en authentification Windows (pas de mot de passe).

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
- Messages de commit : courts, impératif, anglais, sans Co-Authored-By.

## Langues
Docs en français. Code, noms SQL, commits et erreurs d'API en anglais. Chat en français.
