# Progress tracker

Last updated 2026-10-18. Evidence is in the referenced files. "Done" means implemented **and**
exercised; anything mock-only or desktop-only is marked as such.

| Phase | Scope | Status | Evidence |
|---|---|---|---|
| A | Repo, asset import, project, boot | **Done** | `project.godot`, `assets/veya/` (605 files, 12 MB), `docs/ASSET_USAGE_REPORT.md` |
| B | Rules, freedom geometry, solver, validator, 300 levels | **Done** | 75 tests pass; validator shipped levels (pack 1-3, re-scattered 4-50, generated 51-150 and 151-300) + 300 generated + 60 daily |
| C | Tutorial, Home, World map, Gameplay, Pause/Win/Rescue, Hint/Undo/Shuffle, save/load, progression | **Done** | Screenshots `docs/screenshots/en`; emulator play-through + kill/resume |
| D | 4 tile themes, effects, audio, 6 worlds, Bloom, tile backs, Collections, responsive layout, accessibility | **Done (desktop + emulator)** | Screenshots at 540×960, 540×1200, 720×960, a11y set; device a11y pending |
| E | 10 languages, switching, fonts, RTL, localization tests | **Done; native review pending** | `data/localization/*.json` (302 keys each), `test_localization` |
| F | Daily puzzle, calendar/archive, daily tasks, share card, deterministic content pipeline | **Done** | `DailyGenerator`, `DailyService`, date/DST/leap tests |
| G | Ads/IAP/privacy facades, consent sequencing, catalogues, safe disabled states | **Done as facades; SDKs blocked** | `test_services` (mock), MONETIZATION.md |
| H | Android export + emulator test, AAB path, iOS project path, docs, listings | **Partly done** | Debug APK + AAB built; release signing, iOS build and physical devices blocked |

## Honest launch-readiness view

The core game is complete and verified: correct rules, all content, every screen, persistence,
localization and the Android build path. **It is not store-ready.** Remaining work is mostly
owner-side and hardware-dependent: legal links, signing, iOS build on a Mac, physical-device QA
in all locales, native translation review, playtest calibration of the rebuilt levels 4-150, and (optionally)
real ad/billing SDK integration.
