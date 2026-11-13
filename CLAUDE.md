# KeyDo (formerly EzMe): how changes ship

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

## Shipping fast

Swift cannot be compiled in the Claude workspace (Linux, no Swift), so GitHub's Mac build is the only compile check. Waiting for it is most of the time a change takes.

- Open a PR from a branch. Both workflows run on it: "Build and release EzMe for Mac" (about 10 minutes, compile check only on a PR) and "Test EzMe on a Mac" (about 20 minutes, launch, updater and crash checks).
- **Merge as soon as the build job is green.** Let the smoke test keep running on the PR and read its result afterwards; if it fails, fix forward with a new PR. Do not wait for it before merging.
- GitHub sometimes cancels a Mac job with "The job was not acquired by Runner". That is runner capacity, not the code: re-run it (`POST /repos/werethinkers/jay-ezme/actions/runs/<id>/rerun`).
- Several small changes at once cost one build, so batch them when the person has more than one.
- A change that touches only `CLAUDE.md`, `index.html`, `assets/` or `backend/` does not trigger a release and can go straight to `main`.
- Never use a PR that has a failing build job. Compiler errors are in the job log: `gh api repos/werethinkers/jay-ezme/actions/jobs/<job id>/logs | grep "error:"`.

## Code map

`app/Sources/EzMe/` is about 19,000 lines. `EzMe.swift` holds most of it, in long dense lines, so search by symbol name and never read it top to bottom. Put new features in their own file (the `EzMeCelebration*.swift` and `EzMePromptBuilder.swift` files are the pattern) and wire them in with a few small edits.

| What | Where (search for this) |
|---|---|
| Shortcut (`Clip`), collection record, storage (`DB`) | `struct Clip`, `struct CollectionRecord`, `final class DB` in `EzMe.swift` |
| AppBuilder: gallery, built-in apps (Collection Builder, MyDatabase, Prompt Builder), user apps | `struct AIBuildersWorkspace` (`builderApps`, `userApps`, the landing grid, the `selectedApp` view chain) |
| One user-made AppBuilder app: its form, settings and run | `struct AIUtilityBuilderView`; the run path is the code that handles `.ezmeBuilderGenerateShortcut` |
| Typing a command such as `hbd-Rahul` into a prefix | `func customBuilderCommand` (first matching app wins, so prefixes must be unique) |
| Starter and preset apps | `seedViralStarterApps` (rewrites the app list: it must keep `celebrationPresets`), `EzMeCelebrationApps.swift` (`CelebrationApps.ensureInstalled`, runs every launch from `seedDefaultShortcuts`) |
| HBD and HWA cards | `EzMeCelebrationCard.swift` (PNG and web page, drawn locally) |
| Prompt Builder and sending a prompt to an AI site in the side panel | `EzMePromptBuilder.swift` (`PromptBuilderView`, `PromptComposer`, `PromptTargets`, `PromptDispatcher`) |
| Backslash popup | `final class MiniJPickerPanel` (show, hide, idle close), `struct FloatingPickerView`, `final class PickerSearch`, the key tap `miniJSlashTap` |
| Voice (dictation, "open popup", continuous listening) | `EzMeVoice.swift` (`KeyDoVoice`), `VoiceDictationButton`, `openVoiceDestination` in `EzMe.swift` (spoken "open ..." commands) |
| In-app browser, tabs and side panel | `final class EzMeBrowserTabs` (`newTab`, `webViews`, `browserMessage`), `struct BrowserWorkspace`, `browserSidePanelVisible` in the root view; open requests in `EzMeButter.swift` (`EzMeOpenRequests`) |
| AI calls and keys | `enum SharedAIClient` (`generate`, `generateImage`, `generateVideo`), `AIModelProfileStore`, `KeyStore` |
| WishStudio | `EzMeWish*.swift` |
| Updater | `EzMeUpdater.swift` |
| Launch and smoke test | `app/tests/mac-smoke-test.sh` (checks resources such as `KeyDoLogo.png`; update it when a resource is renamed) |

Settings live in `UserDefaults` with keys such as `ezmeBuilderPrefix.<app name>`, `ezmeBuilderEngine.<app name>`, `ezmeCustomBuilderAppsJSON`, `ezmeAIBuilderApp` (the app AppBuilder opens on). Notification names are declared as `Notification.Name` extensions near the code that uses them.

## Known

- The product is now called KeyDo (renamed 2026-11-12). Only what people see changed. The repo, bundle id (`com.ezme.mac`), executable, `EzMe.app` file name, `EzMe-*.zip` release files, workflow names, the site address and the Lovable project keep their EzMe names so installed copies update in place. Logo, icon and brand rules are in `brand/`.

- 3.41 adds cloud sync with email-and-password accounts (Supabase Auth in the EzMe Marketing Backend). Google sign-in was tried and dropped on 2026-11-07. The Mac smoke test checks that email sign-in is enabled.
