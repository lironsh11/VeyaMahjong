# Branding: app icon

**Current icon (v2, 2026-10-18):** two blossom tiles on an illustrated lake, supplied by the
owner. It replaces the asset pack's original icon everywhere. The pack folder itself is left
unchanged.

Source: `assets/source_art/app_icon_v2_source.webp` (1254×1254, rounded-square art on white;
excluded from import and from builds by `.gdignore`).

## Generated files

All are produced by one deterministic tool. Replace the source and rerun it:

```bash
godot --headless --path . -s res://tools/make_app_icons.gd
```

| File (under `assets/veya/`) | Used by | Form |
|---|---|---|
| `app_icons/ios/AppIcon_1024.png` | iOS export preset (App Store + device) | Opaque full-bleed square; Apple applies the rounded mask |
| `app_icons/android/play_store_icon_512.png` | Google Play listing upload (manual) | Opaque full-bleed square; Play applies the mask |
| `app_icons/android/adaptive_foreground_432.png` | Android 8+ launcher **and** the Android 12+ system launch screen | Art filling the 72dp viewport on a transparent canvas |
| `app_icons/android/adaptive_background_432.png` | Android 8+ launcher | Blurred bleed behind the art (hidden unless the launcher animates) |
| `app_icons/android/adaptive_monochrome_432.png` | Android 13+ themed icons | White two-tile silhouette in the 66dp safe zone |
| `app_icons/android/mipmap-*/ic_launcher.png` (192 is in the preset) | Legacy Android launchers | Rounded art, transparent corners |
| `branding/app_icon_master_{180,192,512,1024}.png` | 192 = Godot project/window icon (`project.godot`); others for marketing | Rounded (1024 is full-bleed) |
| `app_icons/web/favicon_64.png`, `favicon.ico` | Web (not a target platform) | Rounded |

## Verified

- Android debug APK on the API 36 emulator: new icon in the app drawer and on the system launch
  screen. All densities and the themed-icon layer are packaged (`res/mipmap-*`).
- Previewed under circle (Pixel) and squircle (Samsung) masks. Circle masks trim the outer
  corners of the tiles slightly; squircle masks show both tiles fully.
- **Not verified:** iOS rendering (needs a Mac build), Android 13 themed-icon appearance on a
  device with themed icons enabled.

## Rights

The pack's LICENSE_AND_ORIGINS does not cover this icon. The owner must confirm they hold
commercial rights to the artwork (especially if it was AI-generated or commissioned) before
store submission.

## Name: LiShi Mahjong (renamed from Veya Mahjong, 2026-10-18)

Changed everywhere a player or store sees the name:

- App name under the icon (Android `package/name`) and the iOS/desktop name (`config/name`).
- All 10 in-game translations: `app_name`, "LiShi Bloom", "LiShi Light(s)" (CJK use the Latin
  brand: LiShiの光 / LiShi의 빛 / LiShi之光), the share text and the licences text.
- Logo on the launch splash, loading screen and Home: `branding/lishi_logo_stacked_{dark,light}.png`,
  rendered by `tools/make_logo.gd` (the pack's blossom + "LiShi" in Noto Serif, SIL OFL, and
  "MAHJONG" in Rubik). The old "Veya" logo files were removed from the build.
- Store listing drafts (10 languages), README and docs. Build outputs are now `LiShiMahjong-*`.

Package / bundle ID changed to **`com.lishimahjong.app`** (2026-10-18) in all export presets,
docs and the LevelPlay setup script's env metadata. An ID can never change after the first Play
upload, so this is the last free moment to choose it. Ads re-registration steps: MONETIZATION.md
→ "After the package ID change".

Deliberately **not** changed (not visible to players):

- LevelPlay dashboard app name "Veya Mahjong": `tools/setup_levelplay.mjs` finds the existing
  apps by that name. Renaming it in the dashboard and in the script must happen together.
- The banner plugin's Java namespace `com.veyamahjong.ads` (library-internal; it does not affect
  the app ID). It can be renamed the next time the plugin AAR is rebuilt.
- Internal identifiers: the `assets/veya/` folder, the `veya-save` save format (renaming it
  would orphan existing saves), `VEYA_*` environment variable names, the asset-pack folder name.
