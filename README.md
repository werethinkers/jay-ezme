# KeyDo website

Static marketing site for the KeyDo macOS app (current version in `update/latest.json`). Live at https://ezme.ezyourlife.com

- `index.html`: the whole site in one file (HTML, CSS and a small demo script inline). Fonts load from Google Fonts.
- `assets/`: logo, reference document layouts, favicon and social image.
- `app/`: the Mac app source, build script and release notes. See `app/README.md`.
- `update/latest.json`: the update feed. GitHub Actions rewrites it on every app release; the Download button and the app's updater both read it.
- `downloads/EzMe-3.38-macOS.zip`: the last hand-built release, kept as the fallback download until the first automatic release exists.
- `CNAME`: custom domain for GitHub Pages. DNS: `ezme` CNAME to `werethinkers.github.io`.

## Run locally

    python3 -m http.server 8000

Then open http://localhost:8000. No build step and no dependencies.

## Deploy

GitHub Pages serves the `main` branch from the repository root. Push to `main` and the site updates.

## Backend

The site writes to a Supabase database (Lovable Cloud project `jay-ezme`, id `5f041390-5f8c-439b-9bad-1b179e055700`) using the public publishable key in `index.html`.

- `leads`: rows from the "Hear about new releases" form.
- `download_events`: one row per click on the Download button.

Both tables have Row Level Security on and allow INSERT only for the public role. Rows can be read only from the Lovable/Supabase dashboard or with the service role. Never put the service role key in this repo.
