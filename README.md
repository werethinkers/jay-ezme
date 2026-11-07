# EzMe website

Static marketing site for the EzMe macOS app (v3.38). Live at https://ezme.ezyourlife.com

- `index.html`: the whole site (HTML, CSS and a small demo script inline). Fonts load from Google Fonts.
- `assets/`: logo, reference document layouts, favicon and social image.
- `downloads/EzMe-3.38-macOS.zip`: the app build the Download buttons point to. Replace the file and update the version text in `index.html` for a new release.
- `CNAME`: custom domain for GitHub Pages. DNS: `ezme` CNAME to `werethinkers.github.io`.

## Run locally

    python3 -m http.server 8000

Then open http://localhost:8000. No build step and no dependencies.

## Deploy

GitHub Pages serves the `main` branch from the repository root. Push to `main` and the site updates.
