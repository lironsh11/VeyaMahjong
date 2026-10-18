# Branding: app icon

**Current icon (v3, 2026-10-18):** the ivory 發 tile with a lotus, blossoms and a pagoda, from
the LiShi v2 graphics pack, chosen by the owner. It replaces the v2 two-blossom-tiles icon
(still in git history and at `assets/source_art/app_icon_v2_source.webp`).

Source: `assets/source_art/app_icon_v3_source.png` — cropped from the pack's
`00_sources/branding_master.png` (top-left icon). That is the largest copy of this art in the
pack: about 331 px including its gold frame, 309 px of painted art inside it. The pack's
`01_branding/isolated/app_icon_illustrated_a.png` is the same pixels with the right edge cut off,
and its `app_icons/android/adaptive_foreground_432.png` is the framed icon shrunk onto a 432
canvas (an icon inside an icon once a launcher masks it), so neither is used directly.
Excluded from import and from builds by `.gdignore`.

## Generated files

All are produced by one deterministic tool. Replace the source (and its measured constants) and
rerun it:

```bash
godot --headless --path . -s res://tools/make_app_icons.gd
```

| File (under `assets/veya/`) | Used by | Form |
|---|---|---|
| `app_icons/ios/AppIcon_1024.png` | iOS export preset (App Store + device) | Opaque full-bleed art; Apple applies the rounded mask |
| `app_icons/android/play_store_icon_512.png` | Google Play listing upload (manual) | Opaque full-bleed art; Play applies the mask |
| `app_icons/android/adaptive_foreground_432.png` | Android 8+ launcher **and** the Android 12+ system launch screen | Full-bleed art filling the 72dp viewport on a transparent canvas |
| `app_icons/android/adaptive_background_432.png` | Android 8+ launcher | Blurred bleed behind the art (hidden unless the launcher animates) |
| `app_icons/android/adaptive_monochrome_432.png` | Android 13+ themed icons | White tile silhouette with the 發 cut out |
| `app_icons/android/mipmap-*/ic_launcher.png` (192 is in the preset) | Legacy Android launchers | The framed art (gold frame), transparent corners |
| `branding/app_icon_master_{180,192,512,1024}.png` | 192 = Godot project/window icon (`project.godot`); others for marketing | Framed (1024 is full-bleed) |
| `app_icons/web/favicon_64.png`, `favicon.ico` | Web (not a target platform) | Framed |

Full-bleed versions use the art inside the gold frame; its rounded corners are painted in from
the neighbouring art (they sit under every store/launcher mask). Launcher icons and the
adaptive layers are at or below the art's native size. The 512/1024 store icons are upscaled
from 309 px (Lanczos plus a light unsharp mask): clean at icon sizes, slightly soft at 100%
zoom. A larger master from the artist would make them pixel-perfect.

`favicon.ico` wraps `favicon_64.png`: `ffmpeg -i favicon_64.png favicon.ico`.

## Verified

- Android debug APK on the API 36 emulator: the new icon in the app drawer (circle mask) and on
  the Android 12+ system launch screen (docs/screenshots/lishi_v2/android_emulator_icon_splash.png).
- Previewed under iOS, circle (Pixel) and squircle (Samsung) masks, plus the legacy framed icon
  and the themed silhouette.
- **Not verified:** iOS rendering (needs a Mac build), Android 13 themed-icon appearance on a
  device with themed icons enabled.

## Rights

The icon art comes from the LiShi v2 graphics pack; the owner must confirm they hold
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
