# Architecture

Godot 4.7, GDScript (typed), GL Compatibility renderer, portrait 540×960 logical canvas
(`canvas_items` stretch, `expand` aspect). Low-processor mode is on, so the game redraws only
when something changes, which saves battery in a turn-based game.

## Layers

```
scripts/core/        Pure rules & content (no nodes; thread-safe on cloned data)
  MahjongRules  TileModel  BoardGeometry  BoardState  LevelDefinition
  BoardSolver   BoardGenerator  LayoutGenerator  ShuffleRescue  DailyGenerator
  BoardValidator  DifficultyAnalyzer  GameSession  SeededRng
scripts/gameplay/    BoardView (render + hit-test), TileView, BoardController (session<->view, async)
scripts/services/    Autoload singletons (below)
  ads/ iap/          Provider interfaces, QA mocks, Google Play Billing adapter
scripts/ui/          Screen base class, UIKit builders, ModalDialog
scripts/screens/     One script per screen (scenes/*/*.tscn are thin roots)
scripts/debug/       Debug-build-only tools: ScreenshotTour, PerfLogger
data/                levels, config (worlds, bloom, cosmetics, products, flags, analytics schema,
                     daily tasks, privacy links), localization (10 locales)
assets/veya/         Runtime copies of the pack (PNG/OGG/WAV/JSON); assets/fonts/ Rubik (OFL)
tests/               Headless test runner + suites
tools/               Headless validators, script checker, asset usage report
```

## Autoloads (order matters)

| Autoload | Responsibility |
|---|---|
| FeatureFlags | Local, typed flags with safe offline defaults; QA mocks only honoured in debug builds |
| SaveService | Versioned, checksummed, atomic save envelope; tmp/bak recovery; quarantine of corrupt files |
| GameState | Single owner of persistent data; defaults + migrations; settings change signals |
| ContentService | Levels/worlds/Bloom/cosmetics data; texture cache (atlas slicing); releases inactive textures on memory warnings |
| LocalizationService | 10 locales, plurals, placeholders, number/date formatting, RTL, TranslationServer registration |
| UITheme | Runtime Theme from pack sprites (0.5× nine-patches), fonts with CJK system fallback, high contrast |
| AccessibilityService | Reduced motion, haptics, Low/Standard profile (auto by RAM/CPU), accessibility names |
| AudioService | Pooled SFX, cross-faded looped music, Music/SFX/Ambience buses, pause on background |
| Jobs | WorkerThreadPool tasks with main-thread delivery (solver, generator) |
| AnalyticsService | Schema-validated, consent-gated, batched; no network provider shipped |
| PrivacyService | Consent state, legal links (blank = disabled with reason), ad-init gating |
| IAPService | Product catalogue, store adapters, entitlement ledger (transaction dedupe, pending, revocation) |
| EconomyService | Coins + booster inventory (data/config/economy.json): idempotent grant ledger, buy/consume, rewards, start/welcome packs |
| AdsService | Ad policy facade: per-placement rewarded caps, reward dedupe, interstitial pacing, consent gate, banner; providers in scripts/services/ads/ (LevelPlay native, QA mock) |
| ProgressionService | Idempotent Lights by source key; derived Bloom discoveries and theme unlocks |
| DailyService | Local-date daily boards (async generation), 30-day archive, optional tasks |
| Router | Navigation, back-button handling, modal stack, toasts, lifecycle saves, memory warnings |

## Event flow: one tap

```
touch -> BoardView._gui_input -> pick(point) [topmost body rect]
      -> BoardController._on_tap(i) -> GameSession.tap(i)       (rules; state updated now)
         BLOCKED   -> view shake/tint, invalid sfx, gentle one-time explanation toast
         SELECTED  -> ring + lift
         MATCHED   -> view.play_match (220 ms, skippable effects)
                      DailyService.record_match, controller.save()  -> GameState.active_session
                      won?        -> GameplayScreen._on_won: progress committed BEFORE celebration
                      no moves?   -> rescue dialog (free Shuffle / Undo / Restart)
                      otherwise   -> Jobs: bounded solvability check -> checkpoint or "stuck" banner
```

## Screens

Boot → (first run) Tutorial → Home ↔ Worlds / Daily / Collection / Shop (bottom nav), plus
Bloom, Settings and Gameplay. Every screen extends `Screen`, which applies safe-area insets
(notches, gesture bar), sets RTL/LTR from the locale, and rebuilds itself when the language or
theme changes, so language switching needs no restart. Gameplay keeps its `GameSession` outside
the rebuilt node tree, so a rebuild never loses the board.

Dialogs (`ModalDialog`): pause, restart confirmation, win, no-moves/rescue, shuffle-failed,
purchase results, reset confirmation and licences. Each blocks input beneath it, closes on
Android back or Escape when dismissible, and gives initial focus to keyboard/gamepad users only.

## Persistence

`GameState.data` (schema v1) holds settings, completed levels, Light sources, seen Bloom items,
cosmetics, entitlements (+ processed transaction ids), ad caps and grant ids, daily completions
and task stats, privacy choices, stats and the **active board snapshot** (faces, removed set,
undo history including shuffles, stats, checkpoint). It is saved after every pair, on
pause/background/close, and on progress events. See `SaveService` for the write protocol.

## Threading rules

Only `scripts/core` objects cross threads, and always as clones (`BoardState.clone()` shares the
read-only `BoardGeometry`). Worker results return through `Jobs` on the main thread and are
dropped if the board changed in the meantime (generation counter).

## Debug-only tooling (never active in release builds)

- `--tour=<dir> [--locale=xx] [--save-dir=user://x]`: visits every screen and saves PNGs.
- `--perf-log` or `user://perf_log.flag`: prints FPS, frame time, draws, nodes and memory every 2 s.
- `--save-dir=`: isolates save data for tests and tours.
