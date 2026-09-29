# Hama Work - VS Code + GitHub Pages

## Local Run
Copy `.vscode/hama_work.env.example.json` to
`.vscode/hama_work.env.json` and put your real publishable key there.

Then use:
Run and Debug → Hama Work - Chrome

No Terminal command is required.

The local env file is ignored by Git and must not be committed.

## GitHub Actions
Add Repository Secrets:
- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY
- HAMA_AUTH_DOMAIN

Push to `main`. GitHub Actions will build Flutter Web and deploy `build/web` to GitHub Pages.

Never put a Supabase service-role key in Flutter or GitHub.
