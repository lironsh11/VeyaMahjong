extends SceneTree
## Builds levels 4-50 (world 1) from dense, screen-filling boards.
##   godot --headless --path . -s res://tools/build_early_levels.gd [-- --candidates=600]
##
## v4 (owner request 2026-10-19): every board fills the phone's play area in BOTH directions
## (LayoutGenerator.generate_dense, 5-6 columns, the rows that fit the screen, 1-4 layers), so
## tiles are drawn big (about 90-112 px on a 20:9 phone) instead of narrow pack shapes.
## Levels 1-3 stay exactly as supplied as gentle follow-ups to the tutorial.
##
## Each candidate: dense layout -> faces by reverse play (BoardGenerator) -> BoardValidator
## (witness replay + independent solve; tray witness too) -> DifficultyAnalyzer. The 47 chosen
## boards spread their measured scores evenly from level 3 up to TARGET_TOP, then are ordered by
## score. Deterministic: re-running reproduces the same file.

const BUILD_ID := "levels-4-50-v4"  ## v4: dense boards that fill the screen (v3: pack shapes)
const OUT_PATH := "res://data/levels/levels_004_050_regenerated.json"
const REPORT_PATH := "res://docs/reports/levels_004_050.md"
const FIRST_ID := 4
const LAST_ID := 50
const PLAYOUTS := 32
const TARGET_TOP := 45.0  ## where world 1 ends (levels 51-150 continue from here)
const MIN_FIT_TILE := 84.0   ## px at BoardFit.REFERENCE_AREA
const MIN_FILL := 0.88       ## share of the play area's width AND height the board covers


func _initialize() -> void:
	await process_frame
	var n_candidates := 600
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--candidates="):
			n_candidates = int(a.trim_prefix("--candidates="))
	var t0 := Time.get_ticks_msec()
	var pack: Array = JSON.parse_string(FileAccess.get_file_as_string(LevelCatalog.PACK_PATH))
	# Level 3 as shipped (bonus pairs made identical), not the raw pack board.
	var lo: float = DifficultyAnalyzer.analyze(LevelDefinition.from_dict(LevelCatalog.identical_pairs(pack[2])), PLAYOUTS, 11).score
	# Fixed top target. Levels 51-150 are built AFTER this file and start from its tail, so this
	# tool must not read their output (that circular dependency made rebuilds drift).
	var hi: float = TARGET_TOP
	var gen := BoardGenerator.new()
	var pool: Array = []
	var stats := {"tried": 0, "fit_rejected": 0, "invalid": 0}
	for k in n_candidates:
		stats.tried += 1
		var rng := SeededRng.new(SeededRng.hash_string("%s|cand|%d" % [BUILD_ID, k]))
		# Small, gentle boards first (5 columns, few layers), up to 6-column 3-4 layer boards.
		var cols := 5 if rng.rand_float() < 0.6 else 6
		var layers := rng.rand_int(1, 3 if cols == 5 else 4)
		var target := rng.rand_int(20, 40) if layers == 1 else rng.rand_int(28, 30 + layers * 22)
		var positions := LayoutGenerator.generate_dense(rng, target, cols, layers, {"offset_prob": 0.3 + rng.rand_float() * 0.4})
		positions = BoardFit.best_orientation(positions)
		if not _fills_screen(positions):
			stats.fit_rejected += 1
			continue
		gen.spread_bias = [0.6, 0.3, 0.0][k % 3]
		var L := gen.generate_level(positions, "%s|board|%d" % [BUILD_ID, k], {
			"layout_id": "dense:early:%d" % k, "key": "early:%d" % k, "world": "aurora_garden"})
		if not L.is_valid():
			stats.invalid += 1
			continue
		var rep := BoardValidator.validate(L, 200000)
		if not rep.ok or not rep.witness_legal:
			stats.invalid += 1
			continue
		pool.append({"k": k, "L": L, "an": DifficultyAnalyzer.analyze(L, PLAYOUTS, 11)})
		if k % 100 == 0:
			print("candidate %d / %d, pool %d" % [k, n_candidates, pool.size()])

	# Pick boards so the set spreads evenly over [lo, hi].
	var count := LAST_ID - FIRST_ID + 1
	var chosen: Array = []
	var used := {}
	for i in count:
		var target := lerpf(lo + 1.0, hi - 0.5, float(i) / float(count - 1))
		var best: Variant = null
		var best_d := INF
		for c in pool:
			if used.has(c.k):
				continue
			var s: float = c.an.score
			var d := absf(s - target) + (100.0 if s > hi else 0.0)  # never above level 51
			if d < best_d:
				best_d = d
				best = c
		if best == null:
			push_error("pool too small: %d boards" % pool.size())
			quit(1)
			return
		used[best.k] = true
		chosen.append(best)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.an.score < b.an.score)

	var out: Array = []
	var md := PackedStringArray()
	md.append("# Levels 4-50 (dense screen-filling boards, ordered by measured difficulty)")
	md.append("")
	md.append("Built by `tools/build_early_levels.gd` (`%s`, deterministic, %d candidates, pairing spread 0.6/0.3/0.0). Levels 1-3 are the supplied pack levels, unchanged." % [BUILD_ID, n_candidates])
	md.append("")
	md.append("- Range: level 3 score %.1f -> level 51 score %.1f. Pool %d; rejected for screen fit %d; invalid %d." % [lo, hi, pool.size(), stats.fit_rejected, stats.invalid])
	md.append("- Every board fills >= %d%% of the play area's width and height with tiles >= %d px (`BoardFit.REFERENCE_AREA`), and its witness is replayed legally AND independently solved." % [int(MIN_FILL * 100), int(MIN_FIT_TILE)])
	md.append("")
	md.append("| Level | Layout | Tiles | Layers | Tile px | Fill w/h | Dead-end rate | Mirrored twins | Score |")
	md.append("|---|---|---|---|---|---|---|---|---|")
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		var L: LevelDefinition = c.L
		var an: Dictionary = c.an
		var id := FIRST_ID + i
		var d := L.to_dict()
		d.id = id
		d.world = "aurora_garden"
		d.difficulty_band = str(an.band)
		d["build"] = BUILD_ID
		d["analysis_key"] = L.key
		d["metrics"] = {
			"score": an.score, "dead_end_rate": an.dead_end_rate, "layers": an.layers,
			"opening_pairs": an.opening_pairs, "avg_choices": an.avg_choices,
			"stacked_ratio": an.stacked_ratio, "solver_nodes": an.solver_nodes,
		}
		out.append(d)
		var pos := L.positions()
		var fr := LayoutGenerator.fill_ratio(pos)
		var tw := BoardFit.fit_tile_width(BoardGeometry.from_positions(pos), BoardFit.REFERENCE_AREA)
		md.append("| %d | %s | %d | %d | %.0f | %.2f/%.2f | %.2f | %d%% | %.1f |" % [id, L.layout_id, an.tiles, an.layers, tw, fr.x, fr.y, an.dead_end_rate, int(round(mirror_rate(L) * 100)), an.score])
	md.append("")
	md.append("Build time: %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", false))
	f.close()
	var fr2 := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	fr2.store_string("\n".join(md) + "\n")
	fr2.close()
	print("BUILT %d levels lo %.1f hi %.1f first %.1f last %.1f pool %d %s" % [out.size(), lo, hi, out[0].metrics.score, out.back().metrics.score, pool.size(), stats])
	quit(0)


static func _fills_screen(positions: Array) -> bool:
	var geo := BoardGeometry.from_positions(positions)
	if not geo.errors.is_empty() or positions.size() < 16:
		return false
	var fr := LayoutGenerator.fill_ratio(positions)
	return BoardFit.fit_tile_width(geo, BoardFit.REFERENCE_AREA) >= MIN_FIT_TILE and fr.x >= MIN_FILL and fr.y >= MIN_FILL


static func mirror_rate(L: LevelDefinition) -> float:
	## Share of tiles whose identical twin sits at the left-right mirror position.
	var at := {}
	var mn := 1 << 30
	var mx := -(1 << 30)
	for t in L.tiles:
		at[Vector3i(t.gx, t.gy, t.z)] = t.face
		mn = mini(mn, t.gx)
		mx = maxi(mx, t.gx)
	var n := 0
	var m := 0
	for t in L.tiles:
		if t.gx * 2 == mn + mx:
			continue
		n += 1
		if at.get(Vector3i(mn + mx - t.gx, t.gy, t.z), "") == t.face:
			m += 1
	return float(m) / float(maxi(1, n))
