extends SceneTree
## Builds generated levels from validated boards, ordered by measured difficulty.
##   godot --headless --path . -s res://tools/build_levels.gd [-- --range=51-150|151-300 --candidates=N]
##
## Two ranges, each its own committed file (RANGES below; the default is 51-150):
##   51-150  : data/levels/levels_051_150_generated.json, continues from the end of levels 4-50
##   151-300 : data/levels/levels_151_300_generated.json, continues from the end of 51-150
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
		"dead_q": 0.92, "score_q": 0.97, "score_weight": 0.35,
	},
	"151-300": {
		"build_id": "levels-151-300-v3",  ## v3: layered template boards (v2: tile floor rising with the level)
		"out": "res://data/levels/levels_151_300_generated.json",
		"prev": "res://data/levels/levels_051_150_generated.json",
		"report": "res://docs/reports/levels_151_300.md",
		"first": 151, "count": 150, "candidates": 3600,
		"min_tiles": 112, "max_tiles": 144, "layers": [4, 5],
		"spread": [0.6, 0.6, 0.3],
		"dead_q": 0.98, "score_q": 0.99, "score_weight": 0.6,
	},
}
const WORLDS_PATH := "res://data/config/worlds.json"
const MIN_FIT_TILE := 84.0  ## min tile width (px) on BoardFit.REFERENCE_AREA - big, readable tiles
const MIN_FILL := 0.88      ## share of the play area's width AND height the board covers
const PLAYOUTS := 32


func _initialize() -> void:
	await process_frame
	var range_key := "51-150"
	var n_candidates := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--candidates="):
			n_candidates = int(a.trim_prefix("--candidates="))
		elif a.begins_with("--range="):
			range_key = a.trim_prefix("--range=")
	if not RANGES.has(range_key):
		push_error("unknown --range=%s (have %s)" % [range_key, RANGES.keys()])
		quit(1)
		return
	var cfg: Dictionary = RANGES[range_key]
	var build_id: String = cfg.build_id
	var first_id: int = cfg.first
	var count: int = cfg.count
	var last_id: int = first_id + count - 1
	if n_candidates < 0:
		n_candidates = cfg.candidates
	var score_weight: float = cfg.score_weight
	var t0 := Time.get_ticks_msec()
	# Starting point = the end of the previous range (mean of its last 5, so one outlier can't skew it).
	var prev: Array = JSON.parse_string(FileAccess.get_file_as_string(cfg.prev))
	var tail: Array = prev.slice(prev.size() - 5)
	var dead_start := 0.0
	var score_start := 0.0
	for e in tail:
		dead_start += float(e.metrics.dead_end_rate) / tail.size()
		score_start += float(e.metrics.score) / tail.size()

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
		pool.append({"k": k, "L": L, "an": an, "layout_id": layout_id})
		if k % 200 == 0:
			print("candidate %d / %d, pool %d" % [k, n_candidates, pool.size()])

	# --- selection ---------------------------------------------------------------------
	var deads: Array = pool.map(func(c: Dictionary) -> float: return float(c.an.dead_end_rate))
	var scores: Array = pool.map(func(c: Dictionary) -> float: return float(c.an.score))
	deads.sort()
	scores.sort()
	var dead_top: float = deads[int(deads.size() * float(cfg.dead_q))]
	var score_top: float = scores[int(scores.size() * float(cfg.score_q))]
	var dead_span := maxf(0.05, dead_top - dead_start)
	var score_span := maxf(1.0, score_top - score_start)
	var progression := func(an: Dictionary) -> float:
		return ((float(an.dead_end_rate) - dead_start) / dead_span + score_weight * (float(an.score) - score_start) / score_span) / (1.0 + score_weight)
	# Tile floor: progression ~ the share of the range a board lands at, so it sets the minimum size.
	var sized: Array = []
	for c in pool:
		var u := clampf(progression.call(c.an), 0.0, 1.0)
		if int(c.an.tiles) >= LevelCatalog.min_tiles(first_id + u * (count - 1)):
			sized.append(c)
		else:
			stats.below_floor += 1
	pool = sized
	var chosen: Array = []
	var used := {}
	var layout_uses := {}
	for i in count:
		var u := float(i) / float(count - 1)
		var dead_target := lerpf(dead_start, dead_top, u)
		var score_target := lerpf(score_start, score_top, u)
		var best: Variant = null
		var best_d := INF
		for c in pool:
			if used.has(c.k):
				continue
			if not str(c.layout_id).begins_with("proc:") and int(layout_uses.get(c.layout_id, 0)) >= 1:
				continue
			var d := absf(float(c.an.dead_end_rate) - dead_target) / dead_span + score_weight * absf(float(c.an.score) - score_target) / score_span
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
		var floor_tiles := LevelCatalog.min_tiles(first_id + i) - LevelCatalog.TILE_FLOOR_SLACK
		if int(chosen[i].an.tiles) < floor_tiles:
			push_error("level %d has %d tiles, floor %d" % [first_id + i, chosen[i].an.tiles, floor_tiles])
			quit(1)
			return

	# --- output ------------------------------------------------------------------------
	var worlds: Array = JSON.parse_string(FileAccess.get_file_as_string(WORLDS_PATH))
	var out: Array = []
	var md := PackedStringArray()
	md.append("# Levels %d-%d (generated, ordered by measured difficulty)" % [first_id, last_id])
	md.append("")
	md.append("Built by `tools/build_levels.gd --range=%s` (`%s`, deterministic). Levels 1-3 are supplied pack levels; 4-50 are layered template boards too (`docs/reports/levels_004_050.md`). Every board is a layered LayoutTemplates structure and fills >= 88%% of the play area both ways with tiles >= 84 px." % [range_key, build_id])
	md.append("")
	md.append("- Candidates tried: %d (%d-%d tiles, %d-%d layers); no template for the size: %d; rejected for size/readability: %d; geometry not clearable: %d; failed validation: %d; below the tile floor for their progression: %d; pool: %d." % [stats.tried, cfg.min_tiles, cfg.max_tiles, cfg.layers[0], cfg.layers[1], stats.no_template, stats.size_rejected, stats.gen_rejected, stats.invalid, stats.below_floor, pool.size()])
	md.append("- Tile floor (`LevelCatalog.min_tiles`): %d tiles at level %d rising to %d at level %d." % [LevelCatalog.min_tiles(first_id), first_id, LevelCatalog.min_tiles(last_id), last_id])
	md.append("- Start = mean of levels %d-%d: dead-end rate **%.2f**, score **%.1f**. Targets ramp to dead-end %.2f (pool p%d) and score %.1f (pool p%d)." % [first_id - 5, first_id - 1, dead_start, score_start, dead_top, int(round(cfg.dead_q * 100)), score_top, int(round(cfg.score_q * 100))])
	md.append("- Order: progression = (normalised dead-end rate + %.2f x normalised score) / %.2f, ascending." % [score_weight, 1.0 + score_weight])
	md.append("- Every board: witness replayed legally AND independently solved by the engine solver.")
	md.append("")
	md.append("| Level | World | Tiles | Layers | Opening pairs | Dead-end rate | Avg choices | Score | Progression | Layout |")
	md.append("|---|---|---|---|---|---|---|---|---|---|")
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		var L: LevelDefinition = c.L
		var id := first_id + i
		var world := _world_for(worlds, id)
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
		out.append(d)
		md.append("| %d | %s | %d | %d | %d | %.2f | %.2f | %.1f | %.3f | %s |" % [id, world, c.an.tiles, c.an.layers, c.an.opening_pairs, c.an.dead_end_rate, c.an.avg_choices, c.an.score, prog, c.layout_id])
	md.append("")
	md.append("| Range | Avg tiles | Avg layers | Avg dead-end rate | Avg score |")
	md.append("|---|---|---|---|---|")
	for r0 in range(first_id, last_id + 1, 25):
		var r := [r0, mini(r0 + 24, last_id)]
		var rows: Array = out.filter(func(x: Dictionary) -> bool: return x.id >= r[0] and x.id <= r[1])
		var st := 0.0
		var sl := 0.0
		var sd := 0.0
		var ss := 0.0
		for x in rows:
			st += x.tile_count
			sl += x.metrics.layers
			sd += x.metrics.dead_end_rate
			ss += x.metrics.score
		md.append("| %d-%d | %.1f | %.2f | %.2f | %.1f |" % [r[0], r[1], st / rows.size(), sl / rows.size(), sd / rows.size(), ss / rows.size()])
	md.append("")
	md.append("Build time: %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open(cfg.out, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", false))
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/reports"))
	var fr := FileAccess.open(cfg.report, FileAccess.WRITE)
	fr.store_string("\n".join(md) + "\n")
	fr.close()
	print("BUILT %d levels %s, dead %.2f->%.2f score %.1f->%.1f, pool %d, %s" % [out.size(), range_key, dead_start, dead_top, score_start, score_top, pool.size(), stats])
	quit(0)


func _world_for(worlds: Array, id: int) -> String:
	for w in worlds:
		if id >= int(w.levels[0]) and id <= int(w.levels[1]):
			return str(w.id)
	push_error("no world covers level %d" % id)
	return ""


func _fits_screen(positions: Array) -> bool:
	var geo := BoardGeometry.from_positions(positions)
	if not geo.errors.is_empty():
		return false
	var fr := LayoutGenerator.fill_ratio(positions)
	return BoardFit.fit_tile_width(geo, BoardFit.REFERENCE_AREA) >= MIN_FIT_TILE and fr.x >= MIN_FILL and fr.y >= MIN_FILL
