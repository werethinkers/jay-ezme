# EzMe for macOS: app source

The EzMe Mac app (SwiftUI, Apple silicon, macOS 14+). The website at the repository root serves the download and the update feed.

- `Sources/EzMe/EzMe.swift`: the app.
- `Sources/EzMe/EzMeUpdater.swift`: the in-app updater ("Check for updates" in the sidebar and in the EzMe menu).
- `Sources/EzMe/Resources/`: logo and document reference images bundled into the app.
- `VERSION`: the version people see, such as `3.39`.
- `RELEASE_NOTES.md`: what's new, shown in the update window and on the GitHub Release.
- `Info.plist`: bundle settings. `__VERSION__` and `__BUILD__` are filled in at build time.
- `build.sh`: builds `EzMe.app` and the zip on a Mac (`./app/build.sh`, output in `app/build/`).

## Releasing a change

1. Change the code, bump `VERSION` and write `RELEASE_NOTES.md`.
2. Merge to `main`.

GitHub Actions (`.github/workflows/release-app.yml`) then builds the app on a Mac, publishes a GitHub Release and rewrites `update/latest.json`. The site's Download button reads that file, and installed copies of EzMe find the new build the next time they check. Pull requests only build the app, so a broken change shows up before it ships. The build number is 168 plus the workflow run number, so every release is newer than the last.

## How the updater works

1. Fetches `https://ezme.ezyourlife.com/update/latest.json` at launch (at most every six hours) or when asked.
2. If `build` is higher than the installed build, it offers the update with the release notes.
3. Downloads the zip, checks its SHA-256, unpacks it, checks the bundle id, the build number and the code signature. When the installed copy is signed with a real identity, the new copy must be signed by the same one.
4. Quits, swaps the app bundle in place (restoring the old one if the copy fails) and reopens. Shortcuts and settings live outside the app bundle, so they are kept.

## Signing (recommended)

Without a certificate the build is ad-hoc signed. That works, but macOS treats every build as a new app, so people may need to turn Accessibility and Input Monitoring on again after an update. To keep permissions across updates, add two repository secrets:

- `MAC_CERT_P12`: a code-signing certificate and key (.p12), base64 encoded. A self-signed certificate is enough to keep permissions; an Apple Developer ID certificate also removes the "cannot verify" warning on first install (after notarization).
- `MAC_CERT_PASSWORD`: the .p12 password.
