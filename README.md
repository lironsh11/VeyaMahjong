# LiShi Mahjong

*Match. Bloom. Relax.* An offline-first, traditional Mahjong Solitaire game for Android and iOS,
built with **Godot 4.7** (GDScript, GL Compatibility renderer) from the supplied
`VeyaMahjong_AssetPack_v1`.

## Open and play

1. Install Godot **4.7** (standard build, not .NET).
2. Open this folder in the editor, or import it from the command line:
   ```bash
   godot --headless --path . --import
   ```
3. Press Play (F5). The window opens at a phone-like 432×864. Mouse clicks act as touches.
   The first run starts the interactive tutorial; later runs open Home.

## What's in the game

- Tile-match Mahjong with a 4-slot tray: tap a free tile (nothing on top, and its left or right
  side open, the standard Mahjong Solitaire rule) and it flies into the tray; two identical tiles burst (every tile, Flowers and Seasons included, matches only an
  identical tile). Four unmatched tiles in the tray lose the board, with a second chance
  ("send 3 tiles back", first one free), Undo or Try again. Combos, score, juicy bursts.
- 150 verified levels in 3 worlds, solver-backed Hint, Undo and a solvable Shuffle as boosters
  (coins + inventory, docs/MONETIZATION.md) with free fallbacks (rewind to the last solvable
  point, a free rescue shuffle, the first continue, restart). Levels 1-3 are the supplied pack;
  4-50 keep the pack shapes with re-scattered tiles, and 51-150 are generated. All are
  validated (and proven clearable with the tray) and ordered by measured difficulty. No timers,
  lives or energy.
- LiShi Bloom: Lights from new levels unlock 30 discoveries in illustrated worlds.
- Four tile themes, a deterministic offline Daily Puzzle with a 30-day archive, and optional daily tasks.
- 10 languages, including Hebrew RTL, with instant switching. Accessibility options: Large Tiles,
  High Contrast, Reduce Motion, Dim Blocked Tiles, Soften Background, a Low graphics profile,
  volume and vibration settings.
- Crash-safe saves after every pair (resume exactly after an app kill).
- Ads and purchases are honest, tested facades that are **off and not integrated** (no SDKs).

## Tests and tools

```bash
godot --headless --path . -s res://tests/run_tests.gd -- --save-dir=user://test_run
```
```bash
godot --headless --path . -s res://tools/validate_content.gd -- --generated=300
```
```bash
godot --headless --path . -s res://tools/check_scripts.gd
```
```bash
godot --headless --path . -s res://tools/build_early_levels.gd
```
```bash
godot --headless --path . -s res://tools/build_levels.gd
```
```bash
node tools/asset_usage_report.js
```

Debug-build visual QA (saves a PNG of every screen; `--locale=` and `--set=key=value` are optional):
```bash
godot --path . --resolution 540x960 -- --tour=C:/tmp/shots --save-dir=user://tour --locale=he
```

## Build

- Android: see [docs/ANDROID_BUILD.md](docs/ANDROID_BUILD.md) (debug APK and Gradle AAB verified; release signing is the owner's).
- iOS: see [docs/IOS_BUILD.md](docs/IOS_BUILD.md) (needs macOS/Xcode and a Team ID).

## Documentation

| Doc | Contents |
|---|---|
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Layers, autoloads, event flow, threading |
| [MAHJONG_RULES_AND_SOLVER](docs/MAHJONG_RULES_AND_SOLVER.md) | Rules, solver, generator, validation results, difficulty findings |
| [LOCALIZATION](docs/LOCALIZATION.md) | Locales, fonts, RTL, review status, adding Arabic |
| [MONETIZATION](docs/MONETIZATION.md) | Ads/IAP facades, flags, integration plan |
| [PRIVACY_AND_COMPLIANCE](docs/PRIVACY_AND_COMPLIANCE.md) | Actual data flows, consent, store disclosures (draft) |
| [QA_MATRIX](docs/QA_MATRIX.md) | Tests and PASS / NOT TESTED / BLOCKED status |
| [PERFORMANCE_REPORT](docs/PERFORMANCE_REPORT.md) | Measured sizes, FPS, memory, start time |
| [ASSET_USAGE_REPORT](docs/ASSET_USAGE_REPORT.md) | Every pack file: used / replaced / unused |
| [RELEASE_CHECKLIST](docs/RELEASE_CHECKLIST.md) | Owner actions and gates |
| [KNOWN_ISSUES](docs/KNOWN_ISSUES.md) | Open problems and blocked dependencies |
| [PROGRESS](docs/PROGRESS.md) | Phase tracker |
| [DEPENDENCY_LOCK](docs/DEPENDENCY_LOCK.md) | Verified versions and store requirements |
| [BRANDING](docs/BRANDING.md) | App icon source, generated variants, regeneration |
| [AUDIO](docs/AUDIO.md) | Sound design, research basis, measurements, regeneration |
| [STORE_LISTINGS](docs/STORE_LISTINGS/README.md) | Draft listings in 10 languages |

## Layout

`scripts/core` pure rules · `scripts/gameplay` board view/controller · `scripts/services`
autoloads · `scripts/screens` screens · `scripts/ui` shared UI · `data/` levels/config/locales ·
`art/lishi_v2/` runtime art (LiShi v2 pack, imported by `tools/import_lishi_v2.gd`, see
docs/LISHI_V2_GRAPHICS_MIGRATION.md) · `assets/veya/` audio, effects, app icons and legacy
Pearl Coast art · `tests/` · `tools/` · `docs/`. The original pack in
`VeyaMahjong_AssetPack_v1/` is kept unmodified and excluded from import.
