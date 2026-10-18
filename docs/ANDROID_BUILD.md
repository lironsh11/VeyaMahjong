# Android build

## Verified in this environment (2026-10-18)

| Step | Result |
|---|---|
| Debug APK export (`Android` preset, non-Gradle) | **PASS.** `build/android/VeyaMahjong-debug.apk`, 98 MB (debug engine for arm64-v8a + armeabi-v7a + x86_64), signed with the local Godot debug keystore |
| Install + run on Android 16 (API 36) x86_64 emulator, 1080×2400 @420 dpi | **PASS.** Tutorial, Home, level 1 played to completion with real taps, hint, blocked-tile feedback, Flower/Season matching, undo, force-stop and resume mid-board |
| Release-size check (`Android Release Size Check` preset, arm64 only, **unsigned**) | **PASS.** 38.1 MB APK download (92 MB uncompressed; the engine `.so` is 71 MB of that) |
| Gradle build template + AAB (`Android AAB (Gradle)` preset, debug-signed) | **PASS.** `build/android/VeyaMahjong-debug.aab`, 69 MB (debug engine, 2 ABIs) |
| Manifest | minSdk 24, targetSdk 36, compileSdk 36; permissions: `VIBRATE` only |
| 16 KB alignment (`zipalign -c -P 16 -v 4`) | **PASS** on the release-size APK |
| Physical device install | **NOT TESTED** (no physical device was connected) |
| Release-signed AAB | **BLOCKED.** Needs the owner's upload keystore |

## Prerequisites

- Godot 4.7 editor + 4.7 export templates (Editor → Manage Export Templates).
- JDK 17, Android SDK (platform 36, build-tools 36+), configured in Editor Settings → Export → Android.
- For the Gradle/AAB preset: `--install-android-build-template` (creates `android/build/`, git-ignored),
  network access for the first Gradle dependency download.

## Commands

```bash
godot --headless --path . --import
```
```bash
godot --headless --path . --export-debug "Android" build/android/VeyaMahjong-debug.apk
```
```bash
adb install -r build/android/VeyaMahjong-debug.apk
```
```bash
godot --headless --path . --install-android-build-template --export-release "Android AAB (Gradle)" build/android/VeyaMahjong.aab
```

The last command produces the Play-upload artifact once a release keystore is configured
(below). Note: Godot's exporter restarts the adb daemon, so a connected emulator may show
"offline" for a few seconds afterwards; `adb wait-for-device` before installing.

## Presets (`export_presets.cfg`, contains no secrets)

| Preset | Purpose |
|---|---|
| `Android` | Debug APK for QA: arm64-v8a, armeabi-v7a, x86_64 (emulator) |
| `Android AAB (Gradle)` | Store build: AAB, arm64-v8a + armeabi-v7a, Gradle (required for v2 plugins such as Play Billing/AdMob) |
| `Android Release Size Check (unsigned, arm64)` | Measures the release download size; not for distribution |

Application ID: `com.veyamahjong.app` is a **placeholder** that the owner must approve. Once a
release is uploaded to Play, it can never change. Version: name `0.1.0`, code `1`; increment
`version/code` on every upload.

## Release signing (owner)

1. Create an upload keystore (never commit it; `*.keystore`/`*.jks` are git-ignored):
   `keytool -genkeypair -v -keystore veya-upload.jks -alias veya -keyalg RSA -keysize 2048 -validity 10000`
2. Configure it in **Editor Settings** or via environment variables
   (`GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`,
   `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`) rather than in `export_presets.cfg`.
3. Enroll in Play App Signing and upload the AAB to **Internal testing** first.

## Play Console steps (owner)

1. Create the app, approve the package name, and fill the store listing (drafts in `docs/STORE_LISTINGS/`).
2. Content rating questionnaire; Data safety ("No data collected" for this build; see
   PRIVACY_AND_COMPLIANCE.md); Ads declaration "No ads" (until an ad SDK ships); target audience
   (not children).
3. Internal testing track, then closed testing, then production. Pre-launch report on real devices.
4. Screenshots: capture from the running game (`--tour` output or device captures), not concept art.
