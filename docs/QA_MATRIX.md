# QA matrix

Status values: **PASS** (executed and passed), **FAIL**, **NOT TESTED**, **BLOCKED** (cannot run
here; reason given). "Editor/desktop" means the Windows desktop build. "Emulator" means Android 16
(API 36) x86_64 AVD, 1080×2400 at 420 dpi, debug APK. A mock or desktop run never counts as a
platform PASS for native features.

Environment: Godot 4.7.stable, Windows 11, 2026-10-18.

## Automated suites

| Command | Result |
|---|---|
| `godot --headless --path . -s res://tests/run_tests.gd -- --save-dir=user://test_run` | **75 passed, 0 failed** (~19 s) |
| `godot --headless --path . -s res://tools/validate_content.gd -- --generated=300` | **PASS:** shipped 150/150, generated 300/300, daily 60/60 |
| `godot --headless --path . -s res://tools/build_levels.gd` | Deterministic rebuild of levels 51-150 (report: docs/reports/levels_051_150.md) |
| `godot --headless --path . -s res://tools/build_early_levels.gd` | Deterministic re-scatter of levels 4-50 (report: docs/reports/levels_004_050.md) |
| `godot --headless --path . -s res://tools/check_scripts.gd` | **PASS:** all scripts compile |
| `node tools/asset_usage_report.js` | Generates ASSET_USAGE_REPORT.md; 0 missing bound assets |

## Spec test list (section 27)

| # | Area | How | Status |
|---|---|---|---|
| 1 | All 150 levels have legal step-by-step solutions | `test_levels` + validator (witness replay and independent solve); levels 4-150 also checked for pack-geometry preservation (4-50), no mirrored-twin pattern, monotonic order, a smooth trickiness ramp across the 50/51 boundary, and reproducible metrics; screenshots of the largest/deepest/half-offset boards in `docs/screenshots/levels/` | **PASS** |
| 2 | Matching: identical tiles only, incl. Flowers/Seasons (owner rule) | `test_matching_semantics`, `test_flower_season_pairs_in_play` (different flowers rejected), `test_every_pair_is_identical` (all 150 boards) | **PASS** |
| 3 | Free-tile geometry: left/right/covered/stacked/partial overlap | `test_row_left_right_blocking`, `test_top_cover_blocks`, `test_partial_overlap_half_units`, `test_half_row_offset_side_blocking`, `test_cover_released_after_removal` | **PASS** |
| 4 | Selection state, duplicate taps, removals | `test_tap_flow_and_invalid_picks`, `test_mismatch_moves_selection`; emulator blocked-tap toast | **PASS** |
| 5 | Undo restoration across repeated moves | `test_undo_restores_exact_state` (counters + hash), `test_shuffle_preserves_faces_and_is_solvable` (undo shuffle); emulator undo | **PASS** |
| 6 | Rescue/shuffle verified or free fallback | `test_shuffle_*`, `test_undo_to_checkpoint`; desktop rescue dialog screenshot | **PASS** |
| 7 | Seeded generation deterministic and validated at scale | `test_generator_*`, `test_procedural_layout_deterministic`, `test_rng_stable_values`, validator 300 boards | **PASS** |
| 8 | Completion rewards exactly once, also after reload | `test_level_completion_is_idempotent`, `test_full_state_persists_through_reload`, `test_daily_claim_once_per_date` | **PASS** |
| 9 | Pause/background/crash/reload restores the exact board | `test_session_roundtrip`; emulator force-stop mid-board → identical board, 18 tiles, undo history intact | **PASS** (emulator) |
| 10 | Date changes, DST, leap days, double daily claims | `test_daily_dates_and_archive`, `test_daily_claim_once_per_date`, `test_daily_tasks_claim` | **PASS** |
| 11 | Save migration, corruption, backup recovery | `test_migration_from_v0`, `test_corrupt_primary_recovers_backup`, `test_tmp_recovery_after_interrupted_rename`, `test_save_roundtrip_and_checksum` | **PASS** |
| 12 | 10 locales: same keys, valid placeholders, no missing strings | `test_localization` (7 tests) | **PASS** |
| 13 | Hebrew RTL menus and mixed text, visual review | `docs/screenshots/he/` reviewed (Home, Settings, Daily, Gameplay) | **PASS (desktop)**; device NOT TESTED |
| 14 | Font coverage ru/ja/ko/zh-TW/he | ru, he (Rubik) and ja (system fallback) rendered on desktop | **PASS (desktop, ru/he/ja)**; ko/zh desktop not captured; Android/iOS device **NOT TESTED** |
| 15 | Settings persist and apply (sound, graphics, accessibility) | `test_full_state_persists_through_reload`; high contrast and locale rebuild verified on desktop | **PASS (desktop)**; device NOT TESTED |
| 16 | Offline: full journey, progress, audio, daily, collectibles | No INTERNET permission in the manifest (verified with aapt); emulator run needed no network | **PASS** (by construction + emulator) |
| 17 | Ads: no-fill, timeout, consent declined, SDK disabled, duplicate rewards | `test_ads_*`, `test_rewarded_*`, `test_interstitial_policy` (QA mock) | **PASS (mock)**; real SDK **BLOCKED** (not integrated) |
| 18 | IAP: cancel, pending, restore, unverified, refund/revocation | `test_iap_*`, `test_local_reset_keeps_store_restorable` (QA mock) | **PASS (mock)**; Play/App Store sandbox **BLOCKED** (no plugin, products or accounts) |
| 19 | Layout: small, long, tablet, foldable | Desktop 540×960 (16:9), 540×1200 (20:9), 720×960 (4:3); emulator 1080×2400 | **PASS** for those; small (<5") phones, foldables and notch insets on hardware **NOT TESTED** |
| 20 | Repeated sessions, thermal, budgets | Emulator perf log (no object growth across 16 cycles) | **PARTIAL.** 20-minute thermal runs on hardware **NOT TESTED** |
| 21 | Layered boards (2026-10-22): half-tile offsets, partial overlap, blocking, depth order, touch priority, templates | `test_board_layout` (20 tests: cover of two/four tiles, partial overlap, side blocking, exposure after removal, lift == side, no tile drawn over one in front of it on shipped boards, topmost pick pure and through the node, board centred, debug overlay off by default, every family supported/symmetric/screen-filling, the 32-tile 3-layer example, carving, undo/shuffle/hint), `test_levels_after_3_use_layered_templates`, validator 300/300 + 60 dailies; desktop captures at 540×1200, 540×1170, 540×960, 720×960 and in Hebrew in `docs/screenshots/layered_boards/` (before/after, debug overlay, uncovering after picks) | **PASS (desktop)**; Android/iOS hardware **NOT TESTED** |

## Device matrix

| Device class | OS | Locales | Expected | Status |
|---|---|---|---|---|
| Android emulator 1080×2400 @420 dpi | Android 16 | en | Full journey, persistence | **PASS** (tutorial, level 1 complete, level 2 resume) |
| 2 GB-RAM Android phone (Android Go) | 11-14 | en, ru | 30 FPS Low profile, memory | **NOT TESTED** (no device) |
| Mid-range Android phone | 13-16 | ja, ko, zh-TW | CJK fonts, Standard profile | **NOT TESTED** |
| Android tablet 4:3 / foldable unfolded | 14-16 | de, fr | Layout | **NOT TESTED** (desktop 720×960 PASS) |
| Notch / punch-hole phone | any | he | Safe-area insets, RTL | **NOT TESTED** (code path only) |
| iPhone (current) | iOS 26 | en, ja | Build, safe areas, haptics | **BLOCKED** (no macOS/Xcode/Apple account) |
| Older supported iPhone | iOS 15-17 | es, pt-BR | Performance | **BLOCKED** |
| iPad | iPadOS 26 | ko | Layout | **BLOCKED** |

## Accessibility

| Item | Status |
|---|---|
| Large touch targets (≥ 64 logical px for primary controls; tiles use enlarged hit areas) | PASS (by design, desktop) |
| High contrast, Reduce Motion, Dim Blocked Tiles, Large Tiles (with drag-pan), Soften Background, Vibration off, volume sliders | Implemented; desktop PASS for high contrast and dimming; others NOT TESTED visually |
| Screen readers: `accessibility_name` set on icon buttons, tiles board, level nodes, calendar days (property confirmed present in Godot 4.7) | **NOT TESTED** with TalkBack/VoiceOver. Godot mobile screen-reader bridging must be verified; tiles are not individually exposed |
| Keyboard/gamepad focus rings | PASS (desktop); hidden on touch screens |
| No time pressure anywhere | PASS (no timers; optional play-time stat off by default) |

## Logs

- Emulator logcat during the run: no `SCRIPT ERROR`/`USER ERROR` lines.
- Exit-time "ObjectDB instances leaked / resources still in use" warnings appear only when
  headless tools quit while autoloads hold resources. They are benign and are not runtime leaks
  (the in-game object count stays flat).
