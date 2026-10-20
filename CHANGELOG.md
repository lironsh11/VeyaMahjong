# Changelog

## 0.1.4 (build 5), 2026-10-20

- **Stacked tiles no longer look like they cover the row above:** higher layers shift only
  left now, not up, and the lower row is drawn in front whenever two tiles don't actually sit
  on each other. A free tile above a second-layer tile used to look half covered.
- **Tray tiles after coming back to a level:** tiles already in the tray were restored before
  the tray had its width and stayed invisible (near-zero size); they now take their real size.

## 0.1.3 (build 4), 2026-10-20

- **Debug APK installs next to the store app:** the `Android` preset now exports as
  `com.lishimahjong.app.debug` ("LiShi Debug"), so a QA build no longer replaces the Play Store
  install. Play Billing products don't exist for that ID (see docs/ANDROID_BUILD.md).
- **Match sound:** a pair now plays the asset pack's `select.wav` (copied unchanged as
  `sfx/match_select.wav`) instead of its `match.wav`. Every match now sounds the same: the
  pitch no longer climbs on streaks.
- **Bigger tray tiles:** tiles fill their slot's width and stand a little proud of its top and
  bottom, about 25% bigger than before.
- **Scrolling lists:** the shop and the other scrolling screens now drag from anywhere, cards
  and buttons included; a drag that scrolls never presses the button it started on.
- **Sharper tiles:** with tiles now 90-112 logical px (2-3x on phones), the 96 px atlas was
  upscaled and looked pixelated, especially in the tray and on phones the game treats as Low
  graphics. Board and tray now always draw the 192 px atlas (the pack's largest), and the tile
  atlases and state overlays are imported with mipmaps so small screens stay smooth.

## Unreleased

- **Match sound:** a pair now plays the owner's own asset-pack sound
  (`VeyaMahjong_AssetPack_v1/audio/sfx/match.wav`, copied unchanged as `sfx/match_pack.wav`),
  replacing the synthesized one. The generated `burst` layer no longer plays on top; the pitch
  still rises with the combo.

- **Boards fill the screen (owner request 2026-10-19).**
  - No bottom banner during gameplay or the tutorial (`AdsService.set_banner_suppressed`). It
    stays on the other screens; interstitials and rewarded ads are unchanged.
  - Compact gameplay chrome: 6 px side margins, a 52 px HUD, a 6 px progress bar and a lower
    toolbar.
  - Rows overlap for a 3D slab look (`BoardFit.STEP_Y` 0.885 → 0.82).
  - **Levels 4-150 rebuilt** as dense, screen-filling boards
    (`LayoutGenerator.generate_dense`):
    - 5-6 columns, the rows that fill the play area, 1-5 layers, some layers half-shifted.
    - Every board covers ≥ 88% of the play area's width AND height with tiles ≥ 84 px.
      Today's levels have 89-112 px tiles, against a 66 px median before.
    - Builds: `levels-4-50-v4` and `levels-51-150-v8`.
  - Daily puzzle `daily-4` uses the same boards.
  - Levels 1-3 (the supplied pack) are unchanged.
  - Saves: snapshots carry a layout fingerprint, and save schema v4 drops a level board saved
    mid-game, so it starts fresh on the new board. Progress, stars and coins are untouched.
- **Premium tray frame.** The owner's 5-slot design (jade, gold, sakura) is the only source.
  - `tools/make_tray_art.gd` builds the 4- and 6-slot frames from it: it cuts at the divider
    gems, repeats one slot segment, rebuilds the plain bands and re-centres the ornaments with
    feathered blends, so every size looks alike.
  - `tools/measure_tray_art.gd` records the slots in `data/config/tray_slots.json`.
  - The tray is now 128 px on screen, with tiles fitted inside the painted slots. The danger and
    full-tray red tint the painted slots, and the combo bar sits under the frame.
  - New test `test_tray_art_slots_fit_tiles`.

- **Stars and best score.**
  - On a win the score gets a clean-board bonus (+5 per pair with no Undo and no full tray).
  - It earns 1-3 stars against the board's base score: 1.6× for 2 stars, 3× for 3 (`Scoring`).
  - `ProgressionService.complete_level` keeps the best score and stars per level.
  - The win dialog pops the stars in and marks a new best; the level map shows stars under
    cleared levels. Levels cleared before stars keep their check mark.
- **Win streak.**
  - Counts consecutive first-try wins of new levels. Replays and the daily never change it.
  - A full tray ends it, and so does a fresh restart of the level being attempted (the restart
    dialog warns first). The full-tray dialog says when it ended.
  - At 3+ every new level starts with a free extra tray slot. Reaching 5 gives a Hint and
    reaching 7 a Shuffle: fixed, disclosed gifts paid once per streak (ledger id per run).
  - A drawn flame (`StreakFlame`) shows it in the HUD and on Home.
  - Save schema v3 (adds `streak`, with a migration).
- **Extra Slot booster.**
  - Adds a tray slot for the rest of the board (max 6 with the streak slot). It is not part of
    the history, so Undo keeps it.
  - Offered in a level-start dialog (shown only when you own one or the streak slot is on;
    "Play" stays the default) and first in the full-tray dialog.
  - Sold in the shop (200 / 5 for 800). Everyone gets 2 once (`intro_grants`).
- **Strings and tests.** New strings in 10 languages; new `tests/test_engagement.gd`; the
  screenshot tour shows the level-start dialog, map stars and the streak.

- **Tray play replaces classic pair play.**
  - Any tile with nothing on top can be tapped; side neighbours no longer block.
  - A tapped tile flies into a 4-slot tray above the board. Two identical tiles burst. A tray
    that fills with 4 unmatched tiles loses the board.
  - Second chance: "Send 3 tiles back" returns the newest tray tiles to their board places.
    The first use per board is free, then 100 and 200 coins (`economy.json: continue_costs`).
    Undo, Try again and Home are always offered.
- **Rules and solvers.**
  - New `TrayRules` and `TraySolver`.
  - `GameSession` is rebuilt around single picks (`Tap.TO_TRAY` / `MATCHED` / `FAILED`).
  - Hints name the next 1-2 picks.
  - Shuffle keeps the tray and stays solvable by construction.
  - The background check uses the tray solver.
- **Saves.** Saves are now `v:2` (tray, score, picks). In-progress `v:1` saves convert: each
  pair becomes two picks.
- **Content is unchanged.**
  - Generator, validator, analyzer and the classic `BoardSolver` keep the classic rules, so
    levels and daily puzzles are the same.
  - Every shipped witness is proven to be a tray witness (test + validator).
  - `DifficultyAnalyzer.tray_fail_rate` measures tray pressure for future "Hard" badges.
- **Juice.**
  - Arc flights with squash and stretch; twins pull together, flash, hit-stop, and burst
    (CPU particles, `match_sparkle` / `petal_pop` flipbooks, ring shockwave).
  - Floating `+points`; combo praise ("Good! / Great! / Amazing! / Incredible!") with a
    draining combo bar; board shake from combo 4.
  - Red pulsing last slot; tray shake on a loss; confetti on win; score count-up in the win
    dialog.
  - All of it respects Reduced Motion and Low graphics.
- **Score.** 10 × combo per pair; the score shows in the HUD and the best combo in the win
  dialog.
- **Audio.** New SFX `burst`, `tray_alert` and `fail` (D pentatonic, `tools/audio/make_audio.mjs
  --only=...` regenerates single effects). The match sound now plays at the burst. New haptics
  `combo` and `fail`.
- **Tutorial.** Rewritten for the tray: tray and burst, uncovered tiles, the 4-slot limit, and
  Flowers/Seasons. Strings are in 10 languages.
- **Board size.** The tray costs the board about 124 px on a 20:9 phone. Most levels keep
  64-66 px tiles; the tallest layouts drop to about 58 px (`BoardFit.PLAY_AREA`, new test
  `test_boards_stay_readable_with_the_tray`).

- Appetize run: Codemagic **iOS — Simulator (Appetize)** and GitHub Actions **iOS — Godot Appetize** build an unsigned x86_64 Simulator `.app` (Godot's simulator slice) with `LiShiMahjong.app` at the zip root. No App Store Connect secrets.
- iOS TestFlight CI on GitHub Actions and Codemagic (same three App Store Connect
  secrets as Riftstrike). See `.github/GITHUB_ACTIONS_SETUP.md`. The unsigned
  Simulator compile check in `.github/workflows/ios.yml` is unchanged.
- New app icon (v4, owner-supplied): blossom tile in a gold ring with "LiShi MAHJONG". Every size
  regenerated by tools/make_app_icons.gd from `assets/source_art/app_icon_v4_source.webp` (iOS,
  Play Store, Android adaptive + themed + legacy, project/window icon, favicon); no upscaling now.
  See docs/BRANDING.md.
- Layer shading: tiles below the board's top layer are drawn 7% darker per layer (floor 82%), and
  the raised-tile shadow is a little stronger, so the top of every stack stands out at a glance
  (`TileView.set_layer_depth`). It shows height only, not whether a tile is free.
- Clearer layers: each layer up is shifted further up-left (BoardFit `LAYER_DX/DY` -0.095/-0.085,
  was -0.07/-0.055) and raised tiles (layer > 0) cast a soft shadow on the tiles below
  (`TileView.set_depth_shadow`). Smallest level tile stays >= 66 px on the reference screen.
- Consent without Google UMP: UMP and every AdMob app id dependency removed from GDScript and
  both native plugins (Android plugin + gdap, iOS pod/podspec + Godot glue,
  `GADApplicationIdentifier` in the iOS plist, the UMP checks in the iOS CI). New in-game dialog
  (scripts/ui/ConsentDialog.gd, logic in PrivacyService): shown once at launch only where the
  device region (OS locale) is in the EEA/UK/Switzerland or the time zone is European
  (new native `device_time_zone()`); elsewhere consent is `not_required` (personalized, no
  dialog), re-asked if the device later moves into Europe/UK. Accept and Decline equally
  prominent; Decline = non-personalized ads, every format still runs. Settings > Privacy choices
  reopens it for everyone. iOS ATT follows the answer. Analytics event `ads_consent`, strings in
  10 languages. Not an IAB TCF CMP: fine while no Google demand is in the LevelPlay waterfall.
  Native API: `consent_request`, `privacy_options_required`, `show_privacy_options` and
  `consent_result` removed. Android AAR rebuilt; **the iOS plugin was not rebuilt or compiled**
  (needs the CI workflow). See docs/PRIVACY_AND_COMPLIANCE.md and docs/NATIVE_ADS_API.md.
- Rewarded ads and interstitials on: LevelPlay ad units `rewarded_bonus_coins`,
  `rewarded_bloom_bonus` and `interstitial_level_complete` on Android and iOS
  (data/config/levelplay.json). Meta Audience Network bidding is connected to those units and to
  the banners on both platforms (each instance only in that unit's All Countries group, with the
  ironSource bidder). The publisher API still cannot create Meta instances (ERR-1401); these were
  added in the LevelPlay dashboard.
- Booster economy (owner-approved): Hint, Shuffle and Undo are boosters with counts on the
  toolbar; coins from first clears (20/30/40), world completion (250), daily (50) and tasks (75)
  buy more (data/config/economy.json). Free ways forward stay: restart, rewind to the last
  solvable point, one free rescue Shuffle per board, the first 2 Undos per board; Hints are
  charged only when a useful pair is shown. Start pack for new players, welcome pack + one-time
  explanation for existing players (save schema v2). Shop rebuilt (boosters for coins, free coins
  by video, starter bundle, coin packs, Remove Ads). Rewarded placements win_double / booster /
  shop_coins / bloom_bonus and "balanced" interstitials (from level 6, every 2 levels, 90 s floor)
  in AdsService + LevelPlayAdProvider (flags off until the native plugin is verified). Consumable
  IAP with an idempotent ledger, UMP consent + ATT wiring, Privacy choices in Settings. Store
  listings no longer promise free helpers. See docs/MONETIZATION.md and docs/NATIVE_ADS_API.md.
- Blocked tiles are no longer dimmed by default (it gave away which tiles are free). "Dim Blocked
  Tiles" stays in Settings as an opt-in assist. Existing saves are switched off once (settings
  rev 1, `GameState.migrate`); a player who turns it back on keeps it.
- Graphics refresh (LiShi v2 pack, graphics only): new tiles in four themes, state overlays as
  separate nodes, buttons/panels/tabs/chips/switches/progress bars from text-free sprites with
  live localized text, new icons, level nodes, backgrounds (540x960 and pre-blurred boards for
  low profile), logo and splash, and Bloom props for Aurora Garden and Crystal Nocturne. Five
  miscounted pack faces (bamboo 5/6/8, circle 7/8) rebuilt at import. Theme ids, save data,
  rules, levels and translations unchanged; Pearl Coast stays on legacy art. New app icon: the
  pack's 發 tile, every size regenerated by tools/make_app_icons.gd (docs/BRANDING.md). See
  docs/LISHI_V2_GRAPHICS_MIGRATION.md; tests `test_art.gd`.
- Boards now fill a portrait phone screen: every generated level and daily board is portrait-shaped
  (best of original vs. turned layout, procedural layouts 5-8 columns x 8-11 rows) and must reach
  >= 66 px tiles on the reference phone area. Typical tile width went from 55-68 px to 76-77 px
  (level 7: 55 -> 109 px). Rebuilt `levels-4-50-v3`, `levels-51-150-v7`, daily `daily-3`. Shared
  fit math in `scripts/core/BoardFit.gd`; tests `test_boards_fill_a_portrait_screen`.
- New audio (all original, generated by tools/audio/make_audio.mjs): softer tile clacks with
  round-robin variants, a tuned match chime that climbs the pentatonic on streaks, a gentle
  in-key "blocked" sound, new jingles that duck the music, and two 2.5-3 min pieces per world
  with silence between them (was one 24 s loop). See docs/AUDIO.md.
- Rule change (owner): every tile, Flowers and Seasons included, matches only an identical tile.
  Levels 1-3 keep their pack geometry/witness with identical bonus pairs; levels 4-150 rebuilt
  (`levels-4-50-v2`, `levels-51-150-v6`); daily boards bumped to `daily-2` (completions are kept by
  date); tutorial step 4 now teaches the rule (10 languages).
- Renamed to **LiShi Mahjong** (was Veya Mahjong): app name, all 10 translations (LiShi Bloom,
  LiShi Light), new logo, store listing drafts and docs. Package/bundle ID changed to com.lishimahjong.app; ads re-registration
  checklist in docs/MONETIZATION.md.
- Levels 4-50: pack shapes kept, faces re-scattered (the pack placed ~74% of tiles opposite their
  identical twin), ordered by measured difficulty (`levels-4-50-v1`). Levels 1-3 unchanged.
- Levels 51-150 replaced by generated, validated boards; trickiness and score ramp together
  from where level 50 ends (`levels-51-150-v5`).
- Content version `pack-v1(1-3)+levels-4-50-v1+levels-51-150-v5+daily-1`.
- Daily-board fingerprints pinned by a test.
- New app icon (owner-supplied) on every surface: Android launcher (adaptive, legacy, themed),
  Android 12+ launch screen, iOS, Play listing icon, project/window icon. Generated by
  tools/make_app_icons.gd; see docs/BRANDING.md.
- Fixed (RTL / Hebrew): the selection and hint frames were drawn one tile to the left of the
  tapped tile; match sparkles, Bloom decorations and level checkmarks were affected by the same
  cause (a control positioned before being attached gets mirrored in RTL). Regression test:
  tests/test_ui_rtl.gd.

## 0.1.0 (build 1), 2026-10-18 — first playable

- Content version `pack-v1+gen-1+daily-1`.
- Complete Mahjong Solitaire engine, 150 pack levels, tutorial, all screens, LiShi Bloom, themes,
  daily puzzle and tasks, 10 locales (AI translations pending native review), accessibility
  options, crash-safe saves.
- Ads/IAP facades present and disabled; no third-party SDKs.
