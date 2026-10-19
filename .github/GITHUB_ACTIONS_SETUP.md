# CI/CD — LiShi Mahjong (iOS / Godot)

GitHub Actions and Codemagic run the **same** Godot → sign → IPA pipeline (shared `.github/scripts/`). Android stays a local Godot export. The existing `.github/workflows/ios.yml` is only an unsigned Simulator compile check and does not use these secrets.

## The only secrets

Copy the same three values already used by Riftstrike, Salino, and Tohav.

| Variable | GitHub Actions secret | Codemagic group `basic` |
|----------|------------------------|-------------------------|
| `APP_STORE_CONNECT_ISSUER_ID` | yes | yes |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | yes | yes |
| `APP_STORE_CONNECT_PRIVATE_KEY` | yes — full multiline `.p8`, including `BEGIN PRIVATE KEY` / `END PRIVATE KEY` | yes |

GitHub (this repo): [Settings → Secrets and variables → Actions](https://github.com/lironsh11/VeyaMahjong/settings/secrets/actions).

Codemagic: add the app as project type **Other**, point it at root `codemagic.yaml`, and attach environment group **`basic`**. If that group already exists on the Codemagic account, reuse it. Do not add an `ios_signing` identity — the script creates the distribution certificate and profile at build time.

No keystore, provisioning profile, or `.p8` file is committed.

## One-time App Store Connect app

The API key cannot invent the store record. In App Store Connect, create an iOS app with bundle id **`com.lishimahjong.app`** (name `LiShi Mahjong` is fine) before the first upload. The pipeline registers that bundle id in the developer portal if it is missing (`fetch-signing-files --create`).

Team id **`7BLH4NFZDD`** is the same Apple team as Riftstrike and PEND. It is a repo constant, not a secret. `export_presets.cfg` keeps `application/app_store_team_id=""` in git; CI patches the checkout only.

## How to run

**GitHub Actions:** Actions → **iOS — Godot TestFlight** → **Run workflow**. Leave the optional checkboxes off. The IPA is uploaded to App Store Connect and shows up in TestFlight after Apple finishes processing.

**Codemagic:** start workflow **iOS — Godot TestFlight**. Upload uses the YAML `publishing` block (the GitHub publish script is not used there). `submit_to_testflight` is **false** (upload only). After Beta App Information (feedback email + contact) is filled, set `submit_to_testflight: true`, or on GitHub check **Submit to external TestFlight beta review**.

There is no GitHub → Codemagic trigger. Start each host yourself.

## What the pipeline does

Script: `.github/scripts/godot-ios-testflight-run.sh`

1. Select Xcode 26 (GitHub: `macos-26`; Codemagic: `xcode: latest`).
2. Install Godot **4.7.2** and the matching export templates.
3. Build `LevelPlayBanner` and `LiShiStoreKit` (`native/*/ios/build.sh`).
4. Pick `CFBundleVersion` above the latest TestFlight/App Store build (`ios-resolve-versions.sh`). Marketing version comes from `project.godot` `config/version`.
5. Headless Godot export of preset **iOS** → `build/ios/LiShiMahjong.xcodeproj`.
6. `prepare_xcode_project.sh` (CocoaPods, localized ATT strings, shared scheme).
7. Create signing files and archive. Each TestFlight run revokes the team's iOS Distribution certificates and creates a new one (Apple's certificate quota — same as Riftstrike). Do not run this in parallel with another app's release build on this team.
8. Export the IPA and upload it.

Optional, off by default:

- **Upload IPA to GitHub Artifacts** — TestFlight does not need the artifact.
- **Also build an iOS Simulator zip for Appetize** — soft-fail, so a Simulator problem does not fail the upload.

## Appetize (separate run, no secrets)

Godot's iOS templates only include an **x86_64** simulator `libgodot`. This run links `ARCHS=x86_64` and does not sign or talk to App Store Connect. Same script on both hosts: `.github/scripts/godot-ios-appetize-run.sh`.

| Host | Where |
|------|--------|
| Codemagic | **iOS — Simulator (Appetize)** |
| GitHub Actions | **iOS — Godot Appetize** |

The zip has `LiShiMahjong.app/` at its root. That is the file Appetize accepts.

**Codemagic:** download the artifact `LiShiMahjong-simulator-appetize.zip` and upload that zip at [appetize.io](https://appetize.io/).

**GitHub Actions:** download one of these:

1. **`ios-simulator-appetize-<run>`** — unzip once so `LiShiMahjong.app` is at the root, then upload that zip to Appetize.
2. **`appetize-zip-<run>`** — this GitHub zip contains `LiShiMahjong-simulator-appetize.zip`. Upload **that inner zip**, not the GitHub wrapper. Uploading the wrapper produces "No .app folder found".

## Repo constants

| Variable | Value |
|----------|--------|
| `BUNDLE_ID` | `com.lishimahjong.app` |
| `APPLE_DEVELOPMENT_TEAM` | `7BLH4NFZDD` |
| `GODOT_VERSION` | `4.7.2` |
| iOS export preset | `iOS` |
| `ios/exportOptions.plist` | App Store manual-signing seed; `xcode-project use-profiles` rewrites the copy used for export |
