extends SceneTree
## Builds generated levels from validated boards, ordered by measured difficulty.
##   godot --headless --path . -s res://tools/build_levels.gd [-- --range=51-150|151-300|w1..w6 --candidates=N]
##
## Ranges, each its own committed source file (tools/build_catalog.gd turns the sources into the
## shipped data/levels/world_N.json; LevelCatalog explains the numbering):
##   51-150  : 1.0 levels 51-150 (levels_051_150_generated.json), from the end of 1.0 levels 4-50
##   151-300 : 1.0 levels 151-300 (levels_151_300_generated.json), from the end of 51-150
##   w1..w6  : 1.1.0, the second half of world N = levels 100(N-1)+51 .. 100N
##             (levels_wN_051_100_generated.json, final ids). See WORLD_HALVES.
##
## Fully deterministic (seeded by BUILD_ID): re-running reproduces the same file. The output is
## committed content; the game never regenerates levels at runtime, so a level never changes
## under a player.
##
## Pipeline:
##   1. Candidate geometries: layered template structures (LayoutTemplates.pick: pyramid, brick,
##      terraces, ridge, twin, bridge, turtle, frame..., 5-6 columns, the rows that fill the play
##      area, several layers with half-tile offsets), kept only if they cover >= MIN_FILL of the
##      play area's width AND height with big tiles.
##   2. Faces by reverse play (BoardGenerator), then BoardValidator (witness replay + independent
##      solve). Anything not proven solvable is discarded.
##   3. DifficultyAnalyzer metrics.
##   4. Selection on TWO axes that ramp together from where the previous range ends:
##        - trickiness = random-play dead-end rate (what a player feels as "I got stuck")
##        - the composite score (adds size, layers, choice scarcity, solver effort)
##      Trickiness is the primary axis: ramping the composite score alone let small-but-tricky
##      boards follow big-but-forgiving ones and made trickiness jump at the world boundary.
##   5. Ordered by the combined progression value (stored as metrics.progression).
##   Tile floor: a board below LevelCatalog.min_tiles for the level its progression would put it
##   at never enters the selection, so boards grow along the journey instead of a small-but-
##   tricky board landing late.
## Writes a report to docs/reports/levels_<first>_<last>.md.
##
## 151-300 keeps the same tile size and screen fill; it gets harder through traps: more layers,
## twins placed far apart, and a higher score weight because the dead-end rate is already near
## its ceiling at level 150.

const RANGES := {
	"51-150": {
		"build_id": "levels-51-150-v10",  ## v10: layered template boards (v9: tile floor; v8: dense boards filling the screen)
		"out": "res://data/levels/levels_051_150_generated.json",
		"prev": "res://data/levels/levels_004_050_regenerated.json",
		"report": "res://docs/reports/levels_051_150.md",
		"first": 51, "count": 100, "candidates": 2400,
		"min_tiles": 64, "max_tiles": 144, "layers": [3, 5],
		"spread": [0.6, 0.3, 0.0],
		"dead_q": 0.92, "score_q": 0.97, "score_weight": 0.35, "legacy": true,
	},
	"151-300": {
		"build_id": "levels-151-300-v3",  ## v3: layered template boards (v2: tile floor rising with the level)
		"out": "res://data/levels/levels_151_300_generated.json",
		"prev": "res://data/levels/levels_051_150_generated.json",
		"report": "res://docs/reports/levels_151_300.md",
		"first": 151, "count": 150, "candidates": 3600,
		"min_tiles": 112, "max_tiles": 144, "layers": [4, 5],
		"spread": [0.6, 0.6, 0.3],
		"dead_q": 0.98, "score_q": 0.99, "score_weight": 0.6, "legacy": true,
	},
}
## 1.1.0: the second half of each world (its levels 51-100). Each starts where the world's 1.0
## level 50 ends (mean of 1.0 levels 50w-4..50w) and ramps TOWARD_NEXT of the way to where the
## next world's 1.0 levels end (the last world extrapolates its own climb), so every world ends
## a little harder than before and the next world opens with a short breather (a sawtooth).
## Axes [dead-end rate, score, skilled fail rate] with per-world weights: random play is stuck
## on nearly every board from world 3 on, so the later worlds ramp on the careful-player rate
## (DifficultyAnalyzer.skilled_fail_rate) and the score instead.
## The last worlds' 1.0 boards were the hardest few percent of thousands of candidates, so their
## second halves draw from bigger, deeper candidates and more of them.
const WORLD_HALVES := {
	1: {"candidates": 1400, "min_tiles": 60, "max_tiles": 120, "layers": [2, 4], "spread": [0.6, 0.3, 0.0], "weights": [1.0, 0.35, 0.0]},
	2: {"candidates": 1600, "min_tiles": 84, "max_tiles": 144, "layers": [3, 5], "spread": [0.6, 0.3, 0.0], "weights": [1.0, 0.35, 0.0]},
	3: {"candidates": 2400, "min_tiles": 112, "max_tiles": 144, "layers": [4, 5], "spread": [0.85, 0.85, 0.6], "weights": [1.0, 0.6, 0.5]},
	4: {"candidates": 3000, "min_tiles": 120, "max_tiles": 144, "layers": [4, 5], "spread": [0.85, 0.85, 1.0], "weights": [0.3, 0.6, 1.0]},
	5: {"candidates": 3600, "min_tiles": 124, "max_tiles": 144, "layers": [5, 5], "spread": [1.0, 1.0, 0.85], "weights": [0.3, 0.6, 1.0]},
	6: {"candidates": 4800, "min_tiles": 128, "max_tiles": 144, "layers": [5, 5], "spread": [1.0, 1.0, 1.0], "weights": [0.3, 0.6, 1.0]},
}
const HALF_BUILD_VERSION := "v1"
const TOWARD_NEXT := 0.4
const HALF_QUANTILES := [0.97, 0.98, 0.95]  ## a ramp never ends above these pool quantiles
const AXES := ["dead_end_rate", "score", "skill_fail_rate"]
const SKILL_PLAYOUTS := 32
const WORLDS_PATH := "res://data/config/worlds.json"
const MIN_FIT_TILE := 84.0  ## min tile width (px) on BoardFit.REFERENCE_AREA - big, readable tiles
const MIN_FILL := 0.88      ## share of the play area's width AND height the board covers
const PLAYOUTS := 32


const MIN_SPANS := [0.05, 1.0, 0.05]


func _initialize() -> void:
	await process_frame
	var range_key := "51-150"
	var n_candidates := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--candidates="):
			n_candidates = int(a.trim_prefix("--candidates="))
		elif a.begins_with("--range="):
			range_key = a.trim_prefix("--range=")
	var cfg := _config(range_key)
	if cfg.is_empty():
		push_error("unknown --range=%s (have %s, w1..w6)" % [range_key, RANGES.keys()])
		quit(1)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spread="):  # experiments: one pairing spread for every candidate
			var sp := float(a.trim_prefix("--spread="))
			cfg.spread = [sp, sp, sp]
		elif a.begins_with("--report="):  # experiments: write the report (and levels) elsewhere
			cfg.report = a.trim_prefix("--report=")
			cfg.out = cfg.report.get_basename() + ".json"
	var half: bool = not cfg.get("legacy", false)
	var build_id: String = cfg.build_id
	var first_id: int = cfg.first
	var count: int = cfg.count
	var last_id: int = first_id + count - 1
	if n_candidates < 0:
		n_candidates = cfg.candidates
	var weights: Array = cfg.weights
	var t0 := Time.get_ticks_msec()
	# Starting point = mean of the 5 levels before the range (so one outlier can't skew it).
	var start := _axes_mean(cfg.start_levels, weights)
	var toward: Array = cfg.get("toward", [])
	var floor_at := func(level: float) -> int:
		return LevelCatalog.min_tiles(level) if half else LevelCatalog.legacy_min_tiles(level)

	var gen := BoardGenerator.new()
	var pool: Array = []
	var caps := {}
	var stats := {"tried": 0, "no_template": 0, "size_rejected": 0, "gen_rejected": 0, "invalid": 0, "below_floor": 0}
	for k in n_candidates:
		stats.tried += 1
		var rng := SeededRng.new(SeededRng.hash_string("%s|cand|%d" % [build_id, k]))
		# Mostly 6 columns (the most tiles at ~93 px); some 5-column boards stay in the mix.
		var cols := 6 if rng.rand_float() < 0.8 else 5
		var target := 2 * rng.rand_int(int(cfg.min_tiles) >> 1, int(cfg.max_tiles) >> 1)
		var t := LayoutTemplates.pick(rng, target, cols, cfg.layers[0], cfg.layers[1], caps)
		if t.is_empty():
			stats.no_template += 1
			continue
		var positions: Array = t.positions
		var layout_id := "tpl:%s:%s:%d" % [LayoutTemplates.VERSION, t.family, k]
		# Mix pairing styles (far-apart -> nearer partners).
		gen.spread_bias = cfg.spread[k % 3]
		if not _fits_screen(positions):
			stats.size_rejected += 1
			continue
		var seed_text := "%s|board|%d" % [build_id, k]
		var L := gen.generate_level(positions, seed_text, {"layout_id": layout_id, "key": "build:%d" % k})
		if not L.is_valid():
			stats.gen_rejected += 1
			continue
		var rep := BoardValidator.validate(L, 200000)
		if not rep.ok or not rep.witness_legal:
			stats.invalid += 1
			continue
		var an := DifficultyAnalyzer.analyze(L, PLAYOUTS, 11)
		if half:
			an["skill_fail_rate"] = DifficultyAnalyzer.skilled_fail_rate(L, SKILL_PLAYOUTS)
		pool.append({"k": k, "L": L, "an": an, "layout_id": layout_id})
		if k % 200 == 0:
			print("candidate %d / %d, pool %d" % [k, n_candidates, pool.size()])

	# --- selection ---------------------------------------------------------------------
	# Each axis ramps from `start` to `ends`: the pool quantile (1.0 ranges), or the world's
	# TOWARD_NEXT target capped by that quantile (second halves).
	var ends: Array = []
	var spans: Array = []
	var wsum := 0.0
	for a in AXES.size():
		wsum += float(weights[a])
		if float(weights[a]) <= 0.0:
			ends.append(start[a])
		else:
			var axis: String = AXES[a]
			var vals: Array = pool.map(func(c: Dictionary) -> float: return float(c.an.get(axis, 0.0)))
			vals.sort()
			var top: float = vals[int(vals.size() * float(cfg.quantiles[a]))]
			ends.append(top if toward.is_empty() else maxf(start[a], minf(float(toward[a]), top)))
		spans.append(maxf(MIN_SPANS[a], float(ends[a]) - float(start[a])))
	var progression := func(an: Dictionary) -> float:
		var p := 0.0
		for a in AXES.size():
			if float(weights[a]) > 0.0:
				p += float(weights[a]) * (float(an.get(AXES[a], 0.0)) - float(start[a])) / float(spans[a])
		return p / wsum
	# Tile floor: progression ~ the share of the range a board lands at, so it sets the minimum size.
	var sized: Array = []
	for c in pool:
		var u := clampf(progression.call(c.an), 0.0, 1.0)
		if int(c.an.tiles) >= int(floor_at.call(first_id + u * (count - 1))):
			sized.append(c)
		else:
			stats.below_floor += 1
	pool = sized
	var chosen: Array = []
	var used := {}
	var layout_uses := {}
	for i in count:
		var u := float(i) / float(count - 1)
		var best: Variant = null
		var best_d := INF
		for c in pool:
			if used.has(c.k):
				continue
			if not str(c.layout_id).begins_with("proc:") and int(layout_uses.get(c.layout_id, 0)) >= 1:
				continue
			var d := 0.0
			for a in AXES.size():
				if float(weights[a]) > 0.0:
					d += float(weights[a]) * absf(float(c.an.get(AXES[a], 0.0)) - lerpf(start[a], ends[a], u)) / float(spans[a])
			if d < best_d:
				best_d = d
				best = c
		if best == null:
			break
		used[best.k] = true
		layout_uses[best.layout_id] = int(layout_uses.get(best.layout_id, 0)) + 1
		chosen.append(best)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return progression.call(a.an) < progression.call(b.an))
	if chosen.size() != count:
		push_error("only %d boards selected" % chosen.size())
		quit(1)
		return
	for i in count:
		var floor_tiles: int = int(floor_at.call(first_id + i)) - LevelCatalog.TILE_FLOOR_SLACK
		if int(chosen[i].an.tiles) < floor_tiles:
			push_error("level %d has %d tiles, floor %d" % [first_id + i, chosen[i].an.tiles, floor_tiles])
			quit(1)
			return

	# --- output ------------------------------------------------------------------------
	var worlds: Array = JSON.parse_string(FileAccess.get_file_as_string(WORLDS_PATH))
	var out: Array = []
	var md := PackedStringArray()
	if half:
		md.append("# World %d (%s), levels %d-%d: second half added in 1.1.0" % [cfg.world, worlds[cfg.world - 1].name, first_id, last_id])
		md.append("")
		md.append("Built by `tools/build_levels.gd --range=%s` (`%s`, deterministic), ordered by measured difficulty. The world's first 50 levels are its 1.0 levels %d-%d (see `LevelCatalog`). Every board is a layered LayoutTemplates structure and fills >= 88%% of the play area both ways with tiles >= 84 px." % [range_key, build_id, (cfg.world - 1) * LevelCatalog.LEGACY_PER_WORLD + 1, cfg.world * LevelCatalog.LEGACY_PER_WORLD])
	else:
		md.append("# Levels %d-%d (generated, ordered by measured difficulty)" % [first_id, last_id])
		md.append("")
		md.append("Built by `tools/build_levels.gd --range=%s` (`%s`, deterministic). 1.0 numbering (50 levels per world; `LevelCatalog` maps them to 1.1.0 ids). Levels 1-3 are supplied pack levels; 4-50 are layered template boards too (`docs/reports/levels_004_050.md`). Every board is a layered LayoutTemplates structure and fills >= 88%% of the play area both ways with tiles >= 84 px." % [range_key, build_id])
	md.append("")
	md.append("- Candidates tried: %d (%d-%d tiles, %d-%d layers); no template for the size: %d; rejected for size/readability: %d; geometry not clearable: %d; failed validation: %d; below the tile floor for their progression: %d; pool: %d." % [stats.tried, cfg.min_tiles, cfg.max_tiles, cfg.layers[0], cfg.layers[1], stats.no_template, stats.size_rejected, stats.gen_rejected, stats.invalid, stats.below_floor, pool.size()])
	md.append("- Tile floor (`LevelCatalog`): %d tiles at level %d rising to %d at level %d." % [floor_at.call(first_id), first_id, floor_at.call(last_id), last_id])
	md.append("- Start = mean of %s." % cfg.start_label)
	for a in AXES.size():
		if float(weights[a]) > 0.0:
			var note := "" if toward.is_empty() else ", aimed at %.2f, capped at pool p%d" % [toward[a], int(round(float(cfg.quantiles[a]) * 100))]
			md.append("  - %s: **%.2f** -> %.2f (weight %.2f%s)" % [AXES[a], start[a], ends[a], weights[a], note])
	md.append("- Order: progression = weighted mean of each axis's normalised distance from its start, ascending.")
	md.append("- Every board: witness replayed legally AND independently solved by the engine solver.")
	md.append("")
	md.append("| Level | World | Tiles | Layers | Opening pairs | Dead-end rate | Avg choices | Skilled fail | Score | Progression | Layout |")
	md.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		var L: LevelDefinition = c.L
		var id := first_id + i
		var world: String = str(worlds[LevelCatalog.world_of(id) - 1].id) if half else str(worlds[(id - 1) / LevelCatalog.LEGACY_PER_WORLD].id)
		var prog: float = progression.call(c.an)
		var d := L.to_dict()
		d.id = id
		d.world = world
		d.difficulty_band = str(c.an.band)
		d["build"] = build_id
		d["analysis_key"] = L.key
		d["metrics"] = {
			"score": c.an.score, "dead_end_rate": c.an.dead_end_rate, "layers": c.an.layers,
			"opening_pairs": c.an.opening_pairs, "avg_choices": c.an.avg_choices,
			"stacked_ratio": c.an.stacked_ratio, "solver_nodes": c.an.solver_nodes,
			"progression": snappedf(prog, 0.0001),
		}
		var skill_text := "-"
		if half:
			d.metrics["skill_fail_rate"] = snappedf(float(c.an.skill_fail_rate), 0.0001)
			skill_text = "%.2f" % float(c.an.skill_fail_rate)
		out.append(d)
		md.append("| %d | %s | %d | %d | %d | %.2f | %.2f | %s | %.1f | %.3f | %s |" % [id, world, c.an.tiles, c.an.layers, c.an.opening_pairs, c.an.dead_end_rate, c.an.avg_choices, skill_text, c.an.score, prog, c.layout_id])
	md.append("")
	md.append("| Range | Avg tiles | Avg layers | Avg dead-end rate | Avg skilled fail | Avg score |")
	md.append("|---|---|---|---|---|---|")
	var step := 25 if count > 50 else 10
	for r0 in range(first_id, last_id + 1, step):
		var r := [r0, mini(r0 + step - 1, last_id)]
		var rows: Array = out.filter(func(x: Dictionary) -> bool: return x.id >= r[0] and x.id <= r[1])
		var st := 0.0
		var sl := 0.0
		var sd := 0.0
		var sk := 0.0
		var ss := 0.0
		for x in rows:
			st += x.tile_count
			sl += x.metrics.layers
			sd += x.metrics.dead_end_rate
			sk += float(x.metrics.get("skill_fail_rate", 0.0))
			ss += x.metrics.score
		var sk_text := "%.2f" % (sk / rows.size()) if half else "-"
		md.append("| %d-%d | %.1f | %.2f | %.2f | %s | %.1f |" % [r[0], r[1], st / rows.size(), sl / rows.size(), sd / rows.size(), sk_text, ss / rows.size()])
	md.append("")
	md.append("Build time: %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open(cfg.out, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", false))
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/reports"))
	var fr := FileAccess.open(cfg.report, FileAccess.WRITE)
	fr.store_string("\n".join(md) + "\n")
	fr.close()
	print("BUILT %d levels %s, start %s -> end %s, pool %d, %s" % [out.size(), range_key, start, ends, pool.size(), stats])
	quit(0)


func _config(range_key: String) -> Dictionary:
	## The build settings for a range, with its start levels resolved.
	if RANGES.has(range_key):
		var legacy_cfg: Dictionary = (RANGES[range_key] as Dictionary).duplicate(true)
		legacy_cfg.weights = [1.0, float(legacy_cfg.score_weight), 0.0]
		legacy_cfg.quantiles = [float(legacy_cfg.dead_q), float(legacy_cfg.score_q), 0.0]
		var prev: Array = JSON.parse_string(FileAccess.get_file_as_string(legacy_cfg.prev))
		legacy_cfg.start_levels = prev.slice(prev.size() - 5)
		legacy_cfg.start_label = "levels %d-%d" % [int(legacy_cfg.first) - 5, int(legacy_cfg.first) - 1]
		return legacy_cfg
	if not (range_key.length() == 2 and range_key.begins_with("w") and WORLD_HALVES.has(int(range_key.substr(1)))):
		return {}
	var w := int(range_key.substr(1))
	var errs := PackedStringArray()
	var legacy := LevelCatalog.load_legacy(errs)
	if legacy.is_empty():
		push_error("1.0 levels unavailable: %s" % [errs])
		return {}
	var cfg: Dictionary = (WORLD_HALVES[w] as Dictionary).duplicate(true)
	var per := LevelCatalog.LEGACY_PER_WORLD
	var tail_of := func(world: int) -> Array: return legacy.slice(world * per - 5, world * per)
	cfg.world = w
	cfg.build_id = "levels-w%d-51-100-%s" % [w, HALF_BUILD_VERSION]
	cfg.out = LevelCatalog.HALF_PATH % w
	cfg.report = "res://docs/reports/levels_w%d_051_100.md" % w
	cfg.first = (w - 1) * LevelCatalog.PER_WORLD + per + 1
	cfg.count = LevelCatalog.PER_WORLD - per
	cfg.quantiles = HALF_QUANTILES
	cfg.start_levels = tail_of.call(w)
	cfg.start_label = "1.0 levels %d-%d (this world's levels %d-%d)" % [w * per - 4, w * per, (w - 1) * LevelCatalog.PER_WORLD + per - 4, (w - 1) * LevelCatalog.PER_WORLD + per]
	var all_axes := [1.0, 1.0, 1.0]
	var here := _axes_mean(cfg.start_levels, all_axes)
	var toward: Array = []
	if w < LevelCatalog.WORLDS:
		var nxt := _axes_mean(tail_of.call(w + 1), all_axes)
		for a in AXES.size():
			toward.append(here[a] + TOWARD_NEXT * (nxt[a] - here[a]))
	else:
		var before := _axes_mean(tail_of.call(w - 1), all_axes)
		for a in AXES.size():
			toward.append(here[a] + TOWARD_NEXT * (here[a] - before[a]))
	cfg.toward = toward
	return cfg


func _axes_mean(levels: Array, weights: Array) -> Array:
	## Mean of each axis over these level dicts; the skilled fail rate is measured when it is
	## weighted and not stored (the 1.0 levels predate it).
	var out := [0.0, 0.0, 0.0]
	for d in levels:
		out[0] += float(d.metrics.dead_end_rate) / levels.size()
		out[1] += float(d.metrics.score) / levels.size()
		if float(weights[2]) > 0.0:
			var v: Variant = d.metrics.get("skill_fail_rate")
			if v == null:
				v = DifficultyAnalyzer.skilled_fail_rate(LevelDefinition.from_dict(d, str(d.get("analysis_key", ""))), SKILL_PLAYOUTS)
			out[2] += float(v) / levels.size()
	return out


func _fits_screen(positions: Array) -> bool:
	var geo := BoardGeometry.from_positions(positions)
	if not geo.errors.is_empty():
		return false
	var fr := LayoutGenerator.fill_ratio(positions)
	return BoardFit.fit_tile_width(geo, BoardFit.REFERENCE_AREA) >= MIN_FIT_TILE and fr.x >= MIN_FILL and fr.y >= MIN_FILL
