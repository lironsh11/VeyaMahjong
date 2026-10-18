extends SceneTree
## Builds levels 51-150 from validated generated boards, ordered by measured difficulty.
##   godot --headless --path . -s res://tools/build_levels.gd [-- --candidates=2400]
##
## Fully deterministic (seeded by BUILD_ID): re-running reproduces the same file. The output
## data/levels/levels_051_150_generated.json is committed content; the game never regenerates
## levels at runtime, so a level never changes under a player.
##
## Pipeline:
##   1. Candidate geometries: procedural layouts (varied size, stacking and support rules) plus
##      the larger pack layouts with brand-new face orders.
##   2. Faces by reverse play (BoardGenerator), then BoardValidator (witness replay + independent
##      solve). Anything not proven solvable is discarded.
##   3. DifficultyAnalyzer metrics.
##   4. Selection on TWO axes that ramp together from where levels 4-50 end:
##        - trickiness = random-play dead-end rate (what a player feels as "I got stuck")
##        - the composite score (adds size, layers, choice scarcity, solver effort)
##      Trickiness is the primary axis: ramping the composite score alone let small-but-tricky
##      boards follow big-but-forgiving ones and made trickiness jump at the world boundary.
##   5. Ordered by the combined progression value (stored as metrics.progression).
## Writes a report to docs/reports/levels_051_150.md.

const BUILD_ID := "levels-51-150-v6"  ## v6: identical-tiles-only rule
const OUT_PATH := "res://data/levels/levels_051_150_generated.json"
const EARLY_PATH := "res://data/levels/levels_004_050_regenerated.json"
const REPORT_PATH := "res://docs/reports/levels_051_150.md"
const FIRST_ID := 51
const COUNT := 100
const MIN_TILES := 56
const MAX_TILES := 144
const MAX_SPAN_TILES := 10   ## readability: at most 10 tiles across or down
const PLAYOUTS := 32
const SCORE_WEIGHT := 0.35   ## secondary axis weight relative to trickiness


func _initialize() -> void:
	await process_frame
	var n_candidates := 2400
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--candidates="):
			n_candidates = int(a.trim_prefix("--candidates="))
	var t0 := Time.get_ticks_msec()
	var layouts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/layouts_50.json"))
	# Starting point = the end of levels 4-50 (mean of their last 5, so one outlier can't skew it).
	var early: Array = JSON.parse_string(FileAccess.get_file_as_string(EARLY_PATH))
	var tail: Array = early.slice(early.size() - 5)
	var dead_start := 0.0
	var score_start := 0.0
	for e in tail:
		dead_start += float(e.metrics.dead_end_rate) / tail.size()
		score_start += float(e.metrics.score) / tail.size()

	var gen := BoardGenerator.new()
	var pool: Array = []
	var stats := {"tried": 0, "size_rejected": 0, "gen_rejected": 0, "invalid": 0}
	for k in n_candidates:
		stats.tried += 1
		var rng := SeededRng.new(SeededRng.hash_string("%s|cand|%d" % [BUILD_ID, k]))
		var positions: Array = []
		var layout_id := ""
		if rng.rand_float() < 0.3:
			var big: Array = layouts.filter(func(l: Dictionary) -> bool: return int(l.position_count) >= MIN_TILES)
			var l: Dictionary = big[rng.rand_int(0, big.size() - 1)]
			layout_id = str(l.id)
			for p in l.positions:
				positions.append(Vector3i(int(p[0]) * 2, int(p[1]) * 2, int(p[2])))
		else:
			var params := {
				"min_cols": 6, "max_cols": rng.rand_int(7, MAX_SPAN_TILES),
				"min_rows": 6, "max_rows": rng.rand_int(7, 9),
				"fill_base": 0.97, "fill_falloff": 0.35 + rng.rand_float() * 0.3,
				"upper_prob": 0.6 + rng.rand_float() * 0.35,
				"max_layers": rng.rand_int(3, 5),
				"support": "row" if rng.rand_float() < 0.5 else "cross",
				"cap_prob": 0.6,
			}
			positions = LayoutGenerator.generate_ex(rng, rng.rand_int(70, MAX_TILES), params)
			layout_id = "proc:%s:%d" % [LayoutGenerator.VERSION, k]
		# Mix pairing styles (far-apart -> nearer partners) so forgiving boards exist too.
		gen.spread_bias = [0.6, 0.3, 0.0][k % 3]
		if positions.size() < MIN_TILES or positions.size() > MAX_TILES or not _readable(positions):
			stats.size_rejected += 1
			continue
		var seed_text := "%s|board|%d" % [BUILD_ID, k]
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
	var dead_top: float = deads[int(deads.size() * 0.92)]
	var score_top: float = scores[int(scores.size() * 0.97)]
	var dead_span := maxf(0.05, dead_top - dead_start)
	var score_span := maxf(1.0, score_top - score_start)
	var progression := func(an: Dictionary) -> float:
		return ((float(an.dead_end_rate) - dead_start) / dead_span + SCORE_WEIGHT * (float(an.score) - score_start) / score_span) / (1.0 + SCORE_WEIGHT)
	var chosen: Array = []
	var used := {}
	var layout_uses := {}
	for i in COUNT:
		var u := float(i) / float(COUNT - 1)
		var dead_target := lerpf(dead_start, dead_top, u)
		var score_target := lerpf(score_start, score_top, u)
		var best: Variant = null
		var best_d := INF
		for c in pool:
			if used.has(c.k):
				continue
			if not str(c.layout_id).begins_with("proc:") and int(layout_uses.get(c.layout_id, 0)) >= 1:
				continue
			var d := absf(float(c.an.dead_end_rate) - dead_target) / dead_span + SCORE_WEIGHT * absf(float(c.an.score) - score_target) / score_span
			if d < best_d:
				best_d = d
				best = c
		if best == null:
			break
		used[best.k] = true
		layout_uses[best.layout_id] = int(layout_uses.get(best.layout_id, 0)) + 1
		chosen.append(best)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return progression.call(a.an) < progression.call(b.an))
	if chosen.size() != COUNT:
		push_error("only %d boards selected" % chosen.size())
		quit(1)
		return

	# --- output ------------------------------------------------------------------------
	var out: Array = []
	var md := PackedStringArray()
	md.append("# Levels 51-150 (generated, ordered by measured difficulty)")
	md.append("")
	md.append("Built by `tools/build_levels.gd` (`%s`, deterministic). Levels 1-3 are supplied pack levels; 4-50 are pack shapes with re-scattered faces (`docs/reports/levels_004_050.md`)." % BUILD_ID)
	md.append("")
	md.append("- Candidates tried: %d; rejected for size/readability: %d; geometry not clearable: %d; failed validation: %d; validated pool: %d." % [stats.tried, stats.size_rejected, stats.gen_rejected, stats.invalid, pool.size()])
	md.append("- Start = mean of levels 46-50: dead-end rate **%.2f**, score **%.1f**. Targets ramp to dead-end %.2f (pool p92) and score %.1f (pool p97)." % [dead_start, score_start, dead_top, score_top])
	md.append("- Order: progression = (normalised dead-end rate + %.2f x normalised score) / %.2f, ascending." % [SCORE_WEIGHT, 1.0 + SCORE_WEIGHT])
	md.append("- Every board: witness replayed legally AND independently solved by the engine solver.")
	md.append("")
	md.append("| Level | World | Tiles | Layers | Opening pairs | Dead-end rate | Avg choices | Score | Progression | Layout |")
	md.append("|---|---|---|---|---|---|---|---|---|---|")
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		var L: LevelDefinition = c.L
		var id := FIRST_ID + i
		var world := "pearl_coast" if id <= 100 else "crystal_nocturne"
		var prog: float = progression.call(c.an)
		var d := L.to_dict()
		d.id = id
		d.world = world
		d.difficulty_band = str(c.an.band)
		d["build"] = BUILD_ID
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
	for r in [[51, 75], [76, 100], [101, 125], [126, 150]]:
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
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", false))
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/reports"))
	var fr := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	fr.store_string("\n".join(md) + "\n")
	fr.close()
	print("BUILT %d levels, dead %.2f->%.2f score %.1f->%.1f, pool %d, %s" % [out.size(), dead_start, dead_top, score_start, score_top, pool.size(), stats])
	quit(0)


func _readable(positions: Array) -> bool:
	var geo := BoardGeometry.from_positions(positions)
	if not geo.errors.is_empty():
		return false
	return geo.width_half_units() / 2 <= MAX_SPAN_TILES and geo.height_half_units() / 2 <= MAX_SPAN_TILES
