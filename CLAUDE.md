# EzMe: how changes ship

Repo `werethinkers/jay-ezme` is the single source of truth. Work on `main` only.

## What lives where

| Thing | Where | How it goes live |
|---|---|---|
| Mac app | `app/Sources/EzMe/` (SwiftUI) | Push to `main` touching `app/**`: GitHub Actions builds, publishes a Release, rewrites `update/latest.json`, records the build in the database. Installed copies update through "Check for updates". |
| Website | `index.html`, `assets/` | Push to `main`: GitHub Pages serves it at ezme.ezyourlife.com. Version and build on the page are filled from `update/latest.json`. |
| Database | Lovable Cloud project "EzMe Marketing Backend", id `5f041390-5f8c-439b-9bad-1b179e055700` | Run SQL with the Lovable `query_database` tool, then save the same SQL as the next file in `backend/`. |

## Rules

- Never spend Lovable credits: do not use Lovable `send_message` or `create_project`. Database changes use `query_database` only.
- Never put the service role key or any secret in the repo.
- Do not edit `update/latest.json` by hand; the release workflow owns it.

## Checklist for every change

1. Make the change on `main`.
2. App change: write `app/RELEASE_NOTES.md` for this change (it is shown in the update window and on the Release). Bump `app/VERSION` only for a real new version; the build number is automatic.
3. Database change: `query_database` first, then add `backend/000N_<name>.sql` with the same SQL. Check the result with a SELECT.
4. Push to `main`.
5. Confirm: the "Build and release EzMe for Mac" run succeeded, `update/latest.json` shows the new build, and the build is listed in `app_releases`.
6. Tell the user what changed, the new version and build, and what you could not verify (the app is not opened from here).

## Known

- 3.41 adds cloud sync with email-and-password accounts (Supabase Auth in the EzMe Marketing Backend). Google sign-in was tried and dropped on 2026-11-07. The Mac smoke test checks that email sign-in is enabled.
