extends SceneTree
## Re-scatters the faces of levels 4-50 (owner decision, 2026-10-18).
##   godot --headless --path . -s res://tools/build_early_levels.gd [-- --variants=16]
##
## Why: the supplied pack placed ~74% of tiles directly opposite their identical twin
## (mirror-symmetric face placement), so boards largely solved themselves. Real Mahjong
## Solitaire distributes faces randomly.
##
## What is kept: each pack level's exact geometry (tile positions) and world. Levels 1-3 stay
## exactly as supplied as gentle, transparent follow-ups to the tutorial.
## What changes: faces are reassigned by reverse play (BoardGenerator) and every variant is
## validated (witness replay + independent solve). For each geometry several seeded variants are
## measured; one variant per geometry is chosen so the scores spread evenly from level 3 up to
## the start of the generated levels 51-150, and the 47 boards are then ordered by measured
## difficulty. Deterministic: re-running reproduces the same file.

const BUILD_ID := "levels-4-50-v1"
const OUT_PATH := "res://data/levels/levels_004_050_regenerated.json"
const REPORT_PATH := "res://docs/reports/levels_004_050.md"
const FIRST_ID := 4
const LAST_ID := 50
const PLAYOUTS := 32


func _initialize() -> void:
	await process_frame
	var variants := 24
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variants="):
			variants = int(a.trim_prefix("--variants="))
	var t0 := Time.get_ticks_msec()
	var pack: Array = JSON.parse_string(FileAccess.get_file_as_string(LevelCatalog.PACK_PATH))
	var later: Array = JSON.parse_string(FileAccess.get_file_as_string(LevelCatalog.GENERATED_PATH))
	var lo: float = DifficultyAnalyzer.analyze(LevelDefinition.from_dict(pack[2]), PLAYOUTS, 11).score
	var hi: float = float(later[0].metrics.score)  # level 51 must not be easier than level 50
	var gen := BoardGenerator.new()
	var per_geo: Array = []   # [{source_id, options: [{L, an, v}]}]
	var invalid := 0
	for src in range(FIRST_ID, LAST_ID + 1):
		var P := LevelDefinition.from_dict(pack[src - 1])
		var positions := P.positions()
		var opts: Array = []
		for v in variants:
			# Mix pairing styles: far-apart partners (harder) through nearer partners (gentler),
			# so even the big pack shapes have arrangements that fit early in the journey.
			gen.spread_bias = [0.6, 0.3, 0.0][v % 3]
			var seed_text := "%s|L%d|v%d" % [BUILD_ID, src, v]
			var L := gen.generate_level(positions, seed_text, {"layout_id": P.layout_id, "key": "early:%d:%d" % [src, v], "world": P.world})
			if not L.is_valid():
				invalid += 1
				continue
			var rep := BoardValidator.validate(L, 200000)
			if not rep.ok or not rep.witness_legal:
				invalid += 1
				continue
			opts.append({"L": L, "an": DifficultyAnalyzer.analyze(L, PLAYOUTS, 11), "v": v})
		per_geo.append({"source_id": src, "options": opts})
		if src % 10 == 0:
			print("geometry %d done" % src)

	# Pick one variant per geometry so the set spreads evenly over [lo, hi].
	var count := per_geo.size()
	var chosen: Array = []
	var used := {}
	for i in count:
		var target := lerpf(lo + 1.0, hi - 0.5, float(i) / float(count - 1))
		var best: Variant = null
		var best_d := INF
		for g in per_geo:
			if used.has(g.source_id):
				continue
			for o in g.options:
				var s: float = o.an.score
				var d := absf(s - target) + (100.0 if s > hi else 0.0)  # never above level 51
				if d < best_d:
					best_d = d
					best = {"g": g, "o": o}
		used[best.g.source_id] = true
		chosen.append(best)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.o.an.score < b.o.an.score)

	var out: Array = []
	var md := PackedStringArray()
	md.append("# Levels 4-50 (pack geometry, re-scattered faces, ordered by measured difficulty)")
	md.append("")
	md.append("Built by `tools/build_early_levels.gd` (`%s`, deterministic, %d variants per geometry, pairing spread 0.6/0.3/0.0). Levels 1-3 are the supplied pack levels, unchanged." % [BUILD_ID, variants])
	md.append("")
	md.append("- Range: level 3 score %.1f -> level 51 score %.1f. Invalid variants discarded: %d." % [lo, hi, invalid])
	md.append("- Every board: same tile positions as the named pack level; witness replayed legally AND independently solved.")
	md.append("")
	md.append("| Level | From pack level | Layout | Tiles | Layers | Dead-end rate | Mirrored twins | Score |")
	md.append("|---|---|---|---|---|---|---|---|")
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		var L: LevelDefinition = c.o.L
		var an: Dictionary = c.o.an
		var id := FIRST_ID + i
		var d := L.to_dict()
		d.id = id
		d.world = "aurora_garden"
		d.difficulty_band = str(an.band)
		d["build"] = BUILD_ID
		d["source_level"] = int(c.g.source_id)
		d["analysis_key"] = L.key
		d["metrics"] = {
			"score": an.score, "dead_end_rate": an.dead_end_rate, "layers": an.layers,
			"opening_pairs": an.opening_pairs, "avg_choices": an.avg_choices,
			"stacked_ratio": an.stacked_ratio, "solver_nodes": an.solver_nodes,
		}
		out.append(d)
		md.append("| %d | %d | %s | %d | %d | %.2f | %d%% | %.1f |" % [id, c.g.source_id, L.layout_id, an.tiles, an.layers, an.dead_end_rate, int(round(mirror_rate(L) * 100)), an.score])
	md.append("")
	md.append("Build time: %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", false))
	f.close()
	var fr := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	fr.store_string("\n".join(md) + "\n")
	fr.close()
	print("BUILT %d levels lo %.1f hi %.1f first %.1f last %.1f invalid %d" % [out.size(), lo, hi, out[0].metrics.score, out.back().metrics.score, invalid])
	quit(0)


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
