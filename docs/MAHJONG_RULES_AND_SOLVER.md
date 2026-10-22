# Mahjong rules, solver and content generation

All rules code is pure GDScript in `scripts/core/` (no nodes), so it runs identically in the
game, on worker threads and in the headless tests/tools.

## Data model

| Class | Role |
|---|---|
| `TileModel` | Stable instance id, logical position `(gx, gy, z)` and face. Never holds sprite/visual data. |
| `BoardGeometry` | Immutable relationships computed once per layout: who covers whom, left/right neighbours, Zobrist keys, the back-to-front draw order. Shared read-only between state clones and threads. |
| `BoardFit` / `BoardProjection` | The stacked projection: where each tile's face, sides and sprite are drawn for a tile width, board bounds and fitting, touch hit-testing. Pure, so tools and tests use the game's exact numbers. |
| `LayoutTemplates` | Layered structures (pyramid, turtle, bridge, cross, ...) for generated levels and daily boards. |
| `BoardState` | Mutable: current faces, removed set, incremental blocker counters, remaining count per match key. |
| `LevelDefinition` | Validated, typed level (pack or generated), including its witness solution and generator metadata (`generator_version`, `seed`). |
| `GameSession` | A board being played: the tray, history (picks, shuffles, send-backs), score, stats, solvable checkpoint, save/restore. |
| `TrayRules` / `TraySolver` | The 4-slot tray helpers and the solver for tray play (one pick per move). |

### Coordinates

Positions are stored in **half-tile units**: a tile has a 2×2 footprint. The pack uses whole-tile
integers, which map to `gx = 2x`, `gy = 2y` (`unit: "tile"`). Generated content may use
`unit: "half"`, which allows rows offset by half a tile and caps placed over four tiles. The
engine does not assume tiles are stacked at exactly the same coordinates.

## Rules of play: the tray (since 2026-10-19)

The game plays like popular tile-match mahjong games. Classic pair play (below) is kept only
for content tools.

1. **Pickable** = free under the standard Mahjong Solitaire rule (classic rules 1-3 below): not
   removed, not covered, and the left **or** right side open. A tile with neighbours on both
   sides is blocked (owner request 2026-10-20; `BoardState.side_blocking` is true by default,
   `false` gives the top-cover-only rule for tests). A free tile always exists: the leftmost
   tile of the highest remaining layer has nothing on top and nothing to its left.
2. Tapping a pickable tile moves it off the board into the **tray** (`GameSession.tap`), which
   uncovers the tiles beneath it at once.
3. If the tray already holds an identical tile, both clear immediately (`Tap.MATCHED`). So the
   tray never holds two tiles of one key, and it is fully determined by the set of tiles off
   the board (the keys with an odd count taken).
4. Otherwise the tile takes the next slot (`Tap.TO_TRAY`). If that fills all **4** slots
   (`TrayRules.CAPACITY`), the board is lost (`Tap.FAILED`, `session.failed`). A 4th tile that
   completes a pair never loses.
5. The board is won when the board and the tray are both empty.
6. **Undo** reverses one pick. Undoing a match puts the twin back in its old slot.
7. **Send back** (the second chance, `GameSession.send_back(3)`) returns the newest tray tiles
   to their board places. They were uncovered when picked and nothing can be stacked on them
   since, so no match or score is lost.
8. **Score:** 10 points × the combo multiplier (capped at ×10). Matches less than 3 s apart
   build the combo (`BoardController.COMBO_WINDOW_MS`; time paused in dialogs doesn't count).
   Points and the previous best combo are stored on the history entry, so Undo takes both back.
9. **Stars (`Scoring`):** on a win, a clean board (no Undo, no full tray) adds 5 points per
   pair. The total is compared with the base score (10 per pair): any win is 1 star,
   1.6× base is 2 stars, 3× base is 3 stars.
10. **Extra slots:** `GameSession.add_slot()` raises the capacity for the rest of the board,
    up to `MAX_CAPACITY` (6): one from a win streak of 3+, one from the Extra Slot booster.
    It sits outside the history, so Undo keeps it. A full tray becomes playable again. More
    room never makes a board unsolvable.

**Why every existing board stays solvable.** A classic witness is a list of pairs whose two
tiles are free together. Picking a pair's tiles one after the other is legal in tray play
(the same freedom rule, and taking a tile only frees others), and the tray never holds more
than one tile. So
`TraySolver.flatten(witness)` is a tray witness. The validator checks this
(`BoardValidator`, "witness solution is not legal in tray play"), and a test checks it for all
150 levels.

## Classic rules (content tools)

1. **Covered:** a tile is covered when any tile on a *higher* layer overlaps its footprint
   (`|dx| < 2 and |dy| < 2` in half units).
2. **Side-blocked:** on the same layer, a tile's left (right) side is blocked by a tile whose
   footprint touches that edge (`dx == ∓2`) and shares vertical extent (`|dy| < 2`).
   A half-tile gap does not block, and neither do tiles in different rows without vertical overlap.
3. **Free** = not removed, not covered, and the left side **or** the right side is open.
4. **Matching (owner rule, 2026-10-18):** a tile matches **only an identical tile** (same picture
   and colour), Flowers and Seasons included. This deliberately departs from the traditional rule
   (and the asset pack's original rules file), where any Flower matched any Flower and any
   Season matched any Season. The engine still supports optional match groups through
   `data/levels/tile_match_rules.json` (`bonus_matching`), which is now empty. The pack's
   original file is kept unchanged in the pack folder. Levels 1-3 come from the pack, whose
   witness paired different bonus faces, so for those pairs the second tile takes the first
   tile's face (`LevelCatalog.identical_pairs`). Geometry and witness are unchanged.
5. A pair is removed only if both tiles are free and match (`BoardState.can_pair`). The state
   updates immediately; animations follow the state but never gate it.
6. A board is won only when `remaining == 0`.

Freedom is maintained **incrementally**. Each tile keeps counters of remaining covering, left
and right blockers, and removing or restoring a tile updates only its neighbours. Checking a
tap is O(1), and `available_pairs()` is O(n).

### Input to rules mapping

`BoardView.pick()` → `BoardProjection.pick()` hit-tests against each tile's *solid* (its top
face plus its right and bottom sides; never the drop shadow or the art's transparent padding),
walking the tiles front to back in draw order, so the tile under the finger is the one drawn on
top there and a covered tile is never selected through a tile above it. A tap on the visible
part of a covered tile picks that tile, which the rules then refuse (blocked feedback); the view
never redirects a tap to a different tile. If a tap lands in a gap, the nearest tile whose
solid, enlarged by 10%, contains the point is chosen. The board always lays out LTR, including
in Hebrew.

## Tray solver (`TraySolver`)

Depth-first search over single picks, used in play for the hint and the background check:
- **Pruning:** a pick that would fill the tray is never tried.
- **Memoised dead states** by the board's Zobrist hash alone, because the tray follows from the
  removed set (rule 3 above).
- **No pruning rule is assumed safe.** Move order does the work:
  1. a tile that clears a tray slot;
  2. the first tile of a pickable twin pair;
  3. tiles that uncover the most.
- **Same budgets and results** as `BoardSolver`.
- **Tested against an exhaustive search** on random small boards with tray sizes 2-4.

The hint shows the next 1-2 picks of a proven solution. If none is found in time, it falls back
to `BoardController.best_guess`, labelled as unverified.

## Solver (`BoardSolver`, classic rules, content tools)

Depth-first search with:
- **Safe-move rule:** if every remaining tile of a match key is free, removing them all can never
  hurt (removals only free tiles, and no partner choice remains), so the solver applies them
  without branching.
- **Memoised dead states** by a 64-bit Zobrist hash of the removed set (faces are fixed during
  a solve). A hash collision could only ever produce a false "unsolvable" result; the chance is
  about 2⁻⁶⁴ per state pair.
- **Move ordering:** prefer higher tiles and tiles that unblock more neighbours.
- **Budgets:** `max_nodes` and/or `time_budget_ms`. Exceeding either returns `BUDGET`
  ("unknown"). Callers never present BUDGET as solvable or unsolvable.

`BoardSolver.replay_is_legal()` independently replays any witness move by move.

### Where the solver runs

| Use | Budget | Thread |
|---|---|---|
| Hint: find a pair after which the board is still solvable | ≤ 700 ms total, ≤ 25k nodes per candidate | `WorkerThreadPool` via `Jobs` |
| Background solvability check after every pair | 40k nodes / 600 ms | worker |
| Daily puzzle generation + validation | generator attempts + validation | worker |
| Content validation tool / tests | 200k-400k nodes | headless |

No solver work runs on the main thread during play. Results from superseded moves are discarded
using a generation counter.

**Hint honesty.** If a pair is proven to keep the board solvable, it is shown silently. If time
runs out, the pair is shown with the message "There wasn't time to check further ahead". If
every pair is proven to dead-end, the player is told Undo/Shuffle can help.

## Generation (`BoardGenerator`, `LayoutGenerator`, `DailyGenerator`)

**Reverse play:** with every slot occupied, repeatedly pick two *currently free* slots and remove
them together. The sequence is a legal clearing order for any faces, so assigning a matching face
pair to each removed slot pair gives a board that this witness can solve. The witness is then
replayed through the real rules (forward validation) before the board is accepted. The removal
order is biased toward far-apart partners to avoid trivial adjacent twins.

- Faces are used in sets of four (two pairs), like a real set. Every pair is two identical faces;
  Flowers and Seasons contribute two identical pairs of two different bonus faces.
- **Determinism:** `SeededRng` (xorshift64* seeded by SplitMix64; FNV-1a for string seeds) is
  pinned in code, so seeds reproduce across engine versions. Unit tests check the first outputs
  and the FNV constants.
- **Versioning:** `BoardGenerator.VERSION = "gen-1"`, `LayoutGenerator.VERSION = "layout-1"`,
  `LayoutTemplates.VERSION = "tpl-1"` and `DailyGenerator.VERSION = "daily-5"` (layered template
  boards) are folded into every seed or layout id. Changing an algorithm requires bumping its
  version, so already-played boards never change silently.
- Physical layout difficulty (geometry) is separate from tile order (seeded face assignment).
- If a geometry cannot be cleared at all (for example two tiles stacked with nothing else), the
  generator returns an error rather than an unsolvable board.

## Shuffle and rescue (`ShuffleRescue`)

Only the faces of the tiles still **on the board** move; tray tiles keep theirs. The shuffle:
1. Builds a random legal pick order for the board tiles. One always exists: the leftmost tile
   of the highest layer is always free.
2. Gives the first picks the twins of the tray tiles.
3. Assigns the remaining faces in pairs to consecutive picks.
4. Replays the result through `TraySolver.replay_is_legal`.

Shuffle never changes which tiles are on the board, the tray, the face multiset, progress or
purchases, and it can be undone. Free alternatives remain: rewind to the last checkpoint proven
solvable (kept by the background check) or restart. A rewarded ad is never required. With the booster economy, Shuffle is a booster,
but one rescue Shuffle per board is free when no moves remain and rewinding/restarting stay free
(docs/MONETIZATION.md), so no board can be locked behind a price.

## Content validation

`tools/validate_content.gd` (headless) checks every pack level, measures difficulty, generates
a deterministic sample and the next 60 daily boards, and writes `docs/reports/`. Last run
(2026-10-18):

- **Shipped levels (pack 1-3 + re-scattered 4-50 + generated 51-150): 150/150 PASS**, and the original pack file
  (all 150) also still validates.
- **Pack levels: 150/150 PASS.** Each witness replays legally move by move, and the engine
  solver independently solves each board.
- **Generated sample:** 300/300 valid, 0 rejected, 0 invalid.
- **Daily 2026-10-01 + 59 days:** 60/60 valid.

### Measured difficulty (see `docs/reports/content_validation.md`)

| Levels | Avg tiles | Avg layers | Avg random-play dead-end rate |
|---|---|---|---|
| 1-5 | 24.0 | 1.00 | 0.00 |
| 6-20 | 59.3 | 1.87 | 0.00 |
| 21-50 | 70.5 | 2.63 | 0.08 |
| 51-100 (pack, no longer shipped) | 62.5 | 2.24 | 0.05 |
| 101-150 (pack, no longer shipped) | 62.5 | 2.24 | 0.02 |

**Finding (original pack):** the pack reused the same 50 layouts for levels 51-100 and 101-150,
so worlds 2 and 3 were *not* harder than levels 21-50 (pack averages 28.8 and 27.6; level 101 had
16 tiles).

**Second finding (original pack):** about 74% of tiles in pack levels 1-50 sat directly
opposite their identical twin (mirror-symmetric face placement), so boards largely solved
themselves. Real Mahjong Solitaire distributes faces randomly.

**Resolution (owner-approved):**

| Levels | Content | Built by |
|---|---|---|
| 1-3 | Supplied pack levels, unchanged (gentle follow-ups to the tutorial) | — |
| 4-50 | Layered template boards (all ten `LayoutTemplates` families, 2-3 layers, 30-70 tiles); ordered by composite score | `tools/build_early_levels.gd` (`levels-4-50-v6`): 1,200 candidates → 570 validated, 47 chosen to spread from level 3's difficulty upward (pairing spread 0.6/0.3/0.0). Earlier builds: the pack's own shapes (v1-v3), dense grids (v4-v5) |
| 51-150 | Layered template boards (pyramid, brick, ridge, terraces, frame, bridge, ziggurat, twin; 3-5 layers, 68-144 tiles) | `tools/build_levels.gd` (`levels-51-150-v10`): 2,400 candidates → 1,470 validated → 100 selected; dead-end 0.28 → 0.94. See `docs/reports/levels_051_150.md` |
| 151-300 | Layered template boards, harder through traps (116-144 tiles, 4-5 layers, twins far apart), continuing from level 150 | `tools/build_levels.gd -- --range=151-300` (`levels-151-300-v3`): 3,600 candidates → 2,101 validated → 150 selected; dead-end 0.93 → 1.00, score 96 → 104; dead-end target p98, score target p99, score weight 0.6. See `docs/reports/levels_151_300.md` |

Selection for 51-150 ramps **two axes together** from where level 50 ends: the random-play
dead-end rate (what a player feels as "getting stuck") is the primary axis, and the composite
score is secondary (weight 0.35). Ramping the composite score alone had placed small-but-tricky
boards right after big-but-forgiving ones, so the dead-end rate jumped from ~0.13 to ~0.6 at
level 51. The final order uses the stored `metrics.progression` value.

Every board in 4-300 has its witness replayed legally and is independently solved. Each file
stores seed, generator version, build id and metrics, and is committed data, so boards never
change at runtime. `LevelCatalog` merges the four sources for the game, tests and tools.
Both tools are deterministic.

Result (validator, 2026-10-18):

| Levels | Avg tiles | Avg layers | Avg dead-end rate | Avg score |
|---|---|---|---|---|
| 1-5 | 22.4 | 1.00 | 0.02 | 11.6 |
| 6-20 | 47.1 | 1.93 | 0.03 | 22.5 |
| 21-50 | 76.9 | 2.60 | 0.09 | 35.8 |
| 51-100 | 80.1 | 3.60 | 0.34 | 50.9 |
| 101-150 | 76.0 | 3.64 | 0.59 | 58.9 |

Tests enforce: levels 1-3 byte-identical to the pack; levels 4-50 use exactly the pack
geometries (each once); mirrored twins under 40% per level and under 15% on average (pack: 74%);
4-50 scores monotonic with steps ≤ 5; 51-150 progression monotonic; the 7-level moving average
of the dead-end rate changes ≤ 0.08 per level across 4-300 (no cliff at 50/51 or 150/151); each world is
harder than the previous one on both axes; stored metrics reproduce exactly.

*(The validator's table uses 24 playouts, seed 7; the stored build metrics use 32 playouts,
seed 11.)* The dead-end rate measures **random** play. Real players dead-end far less,
and helpers are now boosters (with free rescue paths), so tester feedback on worlds 2-3 should
calibrate both the top end and the economy numbers.

## Tests

`tests/test_rules.gd`, `tests/test_solver.gd`, `tests/test_levels.gd` cover: top cover,
left/right blocking, half-offset partial overlap, same-layer overlap rejection,
identical-only matching (incl. Flowers/Seasons), invalid picks, duplicate taps, mismatches, completion, exact undo
(counters and hash), no-move detection, the solver solving and proving unsolvable, budget
honesty, generator determinism and batch validity, procedural layout support, shuffle
invariants and impossible geometry, session save/restore and tamper rejection, rewinding to
the checkpoint, and all 150 pack levels.

## Board geometry and rendering (layered boards, since 2026-10-22)

Owner request (2026-10-22): boards must read as real Mahjong Solitaire stacks, like a classic
layered layout, not a flat grid. The fix is in the geometry, the content and the renderer, not
in cosmetic offsets.

### Data model

Every tile has a stable index/id (`TileModel.id`), a face (its type), logical integer
coordinates `gx`, `gy` in **half-tile units** (two units = one tile pitch, so half-tile offsets
are exact integers), a layer `z`, a removed flag and its blocking state (`BoardState`: covering
count and left/right neighbour counts, updated incrementally). Screen positions are never stored:
`BoardProjection` derives them from the logical geometry for the current tile width.

### Projection (`BoardFit`, `BoardProjection`)

The board is drawn as a stack seen from above and slightly to the front-right:
- **Face and sides.** Each tile shows its top face (`BoardFit.FACE`, 0.915 × 1.025 tile widths)
  plus a bottom side (the thickness band painted in the tile art, 0.135) and a right side
  (0.05, drawn by `TileView` as two tinted copies of the tile: an ivory lip and the jade back).
  Sides are darker than the face.
- **Lift.** A tile on layer z is drawn `z × LIFT` up-left, with `LIFT == SIDE`. A tile resting on
  another shows the lower tile's sides beneath its own; a tile half a tile off its supports
  visibly straddles them.
- **Pitch.** Same-layer neighbours sit one face apart plus a hairline gap (`GAP`, 0.02), so a
  layer reads as one floor and the row behind shows a sliver of its lip.
- **Shadows.** A raised tile drops a soft contact shadow past its right and bottom sides onto the
  tiles below it. Lower layers are shaded slightly darker (6% per layer, at most 16%).
- **Draw order** (`BoardGeometry.draw_order`): layer by layer, lowest first; within a layer by
  `gx + gy`, so a right or lower neighbour is drawn over the side it hides. Because `LIFT ==
  SIDE`, a higher tile never reaches onto a lower tile in front of it; it can hide at most a
  lift's strip (about 11% of the face per layer of height difference) of a tile directly behind
  it, as in a real stack. `z_index` is used only to raise a hinted tile.
- **Bounds and fit.** `BoardFit.bounds` is the union of every tile's face and sides (including
  each layer's lift) plus room for shadows. The whole board is scaled uniformly to the play area
  and centred; tiles never stretch. Bounds come from the layout, not the remaining tiles, so the
  board does not move as tiles leave.

### Debug view

Debug builds only: `--board-debug` (or `BoardView.debug_overlay = true`) outlines every face
and labels it with its state and layer: green `F` free, amber `S` both sides blocked, red `C`
covered. Release builds never create it.

## Layout templates (`LayoutTemplates`, "tpl-1")

Levels 4-300 and daily boards (`daily-5`) are built in three deterministic steps:

1. **Ground** on a 5- or 6-column grid with the rows that fill the play area
   (`BoardFit.rows_to_fill`), shaped by the family.
2. **Layers**, each derived from the one below by an explicit rule:
   - `stagger`: half a tile across and down, each tile on the corner of four;
   - `stagger_x` / `stagger_y`: half a tile one way, each tile straddling two;
   - `chain`: stagger where four meet, else half a tile along thin runs;
   - `shrink`: aligned, only over tiles with neighbours all round;
   - `same`: aligned, straight on top (towers, walls).

   A tile is placed only where it rests on the layer below (all four quarters; two for a
   bridge deck) and overlaps nothing on its own layer. Shifts alternate direction, so tiers stay
   centred, and every rule keeps the board mirror-symmetric.
3. **Carve** to the wanted tile count: mirror pairs of uncovered tiles are removed, from the top
   (`top`: lower, flatter) or from the outside in (`edge`: eroded terraces). A tile something
   rests on, or the last tile on an edge of the board, is never removed.

| Family | Ground | Layers |
|---|---|---|
| `pyramid` | full grid | staggered pyramid: every tier on the corners of the one below |
| `ziggurat` | full grid | aligned tiers, each a ring smaller, with a staggered cap |
| `turtle` | body, head and tail on the centre line, flippers half a row off the body | the shell straight on the body, then staggered tiers to a cap |
| `bridge` | two piers and a centre channel | decks resting half on a pier, staggered pier tops |
| `cross` | two crossing bars | `chain` tiers along the bars, highest at the centre |
| `twin` | full grid | two staggered pyramids, upper and lower half |
| `frame` | a ring around an open courtyard | `chain`, then walls |
| `brick` | full grid | alternately straddling pairs sideways and lengthways |
| `terraces` | full grid | staggered tiers, each two tiles high |
| `ridge` | full grid | straddling pairs sideways, rising to a roof ridge |

`LayoutTemplates.pick` chooses a family and height whose full structure holds the wanted tiles
without carving away more than about half of it, and rejects boards that end up lower than the
range's minimum (2 layers in 4-50, 3 in 51-150, 4 in 151-300). Faces are then assigned by
reverse play (`BoardGenerator`), so every board is solvable by construction, and validated as
before.

**Screen fit gates.** Levels 4-300 and the daily accept a board only if it covers ≥ 88% of the
play area's width and height with tiles ≥ 84 px (`REFERENCE_AREA` = `PLAY_AREA` = 528 × 893,
the board area in tray play on a 540 × 1200 canvas). A 6-column board gets 93 px tiles, a
5-column one 105-112 px. On a 16:9 phone (about 240 px shorter) the same board scales down
uniformly. Levels 1-3 keep the supplied pack layouts (flat, single layer; their witness depends
on them).

`tests/test_board_layout.gd` covers half-offset cover of two and four tiles, partial overlap,
side blocking, exposure after removal, lift == side, draw order and depth (no tile drawn over one
physically in front of it, checked on shipped boards), touch priority (pure and through the
node), board centring, the debug overlay default, every family's structure, the 32-tile
three-layer example, carving, undo, shuffle and hints on layered boards.
