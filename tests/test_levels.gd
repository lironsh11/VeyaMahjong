extends TestCase
## Content validation for the shipped journey:
##   1-3 supplied pack levels (unchanged), 4-50 pack shapes with re-scattered faces,
##   51-150 generated boards. 4-150 are ordered by measured difficulty.

const MAX_SCORE_STEP := 5.0
const MAX_TRICKINESS_STEP := 0.08   ## moving-average (window 7) dead-end rate change per level


func _merged() -> Array:
	return LevelCatalog.load_merged()


func test_all_150_shipped_levels_valid() -> void:
	var errs := PackedStringArray()
	var raw := LevelCatalog.load_merged(errs)
	check(errs.is_empty(), "catalog loads without fallback: %s" % [errs])
	check_eq(raw.size(), 150, "150 levels")
	var bad := 0
	for i in raw.size():
		var L := LevelDefinition.from_dict(raw[i])
		check_eq(L.id, i + 1, "ids are contiguous")
		var rep := BoardValidator.validate(L, 300000)
		if not rep.ok or not rep.witness_legal:
			bad += 1
			fail("level %d: %s witness=%s" % [L.id, ", ".join(rep.errors), rep.witness_legal])
	check_eq(bad, 0, "invalid levels")


func test_levels_1_3_are_the_supplied_pack_levels() -> void:
	# Same geometry and witness as the pack; only bonus partners copied to make identical pairs.
	var pack: Array = JSON.parse_string(FileAccess.get_file_as_string(LevelCatalog.PACK_PATH))
	var merged := _merged()
	for i in 3:
		var a: Dictionary = merged[i]
		var b: Dictionary = pack[i]
		check(JSON.stringify(a.verified_solution) == JSON.stringify(b.verified_solution), "level %d witness unchanged" % (i + 1))
		for k in a.tiles.size():
			var ta: Dictionary = a.tiles[k]
			var tb: Dictionary = b.tiles[k]
			check(ta.x == tb.x and ta.y == tb.y and ta.z == tb.z, "level %d tile %d same position" % [i + 1, k])
			if ta.face != tb.face:
				check(MahjongRules.is_bonus(str(tb.face)), "level %d: only bonus faces adjusted" % (i + 1))


func test_every_pair_is_identical() -> void:
	# Owner rule: each match key appears an even number of times = each face, so every pair
	# in every shipped board is two identical tiles.
	for d in _merged():
		var counts := {}
		for t in d.tiles:
			counts[t.face] = int(counts.get(t.face, 0)) + 1
		for f in counts:
			check(counts[f] % 2 == 0, "level %d face %s appears %d times" % [d.id, f, counts[f]])


func test_levels_4_50_keep_pack_shapes() -> void:
	# Each of levels 4-50 uses exactly one pack level's geometry (4..50, each once), same world.
	var pack: Array = JSON.parse_string(FileAccess.get_file_as_string(LevelCatalog.PACK_PATH))
	var merged := _merged()
	var sources := {}
	for i in range(3, 50):
		var d: Dictionary = merged[i]
		var src := int(d.get("source_level", -1))
		check(src >= 4 and src <= 50, "level %d has a pack source" % d.id)
		if src < 4 or src > 50:
			continue
		sources[src] = true
		var a := LevelDefinition.from_dict(d).positions()
		var b := LevelDefinition.from_dict(pack[src - 1]).positions()
		a.sort()
		b.sort()
		check(a == b, "level %d has the exact geometry of pack level %d" % [d.id, src])
		check_eq(str(d.world), "aurora_garden")
	check_eq(sources.size(), 47, "every pack shape 4-50 used exactly once")


func _mirror_rate(L: LevelDefinition) -> float:
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


func test_no_mirrored_twin_pattern() -> void:
	# The pack placed ~74% of tiles opposite their identical twin. Shipped levels 4-150 must not.
	var merged := _merged()
	var total := 0.0
	for i in range(3, 150):
		var r := _mirror_rate(LevelDefinition.from_dict(merged[i]))
		total += r
		check(r < 0.4, "level %d mirrored twins %.0f%%" % [i + 1, r * 100.0])
	check(total / 147.0 < 0.15, "average mirrored twins %.0f%%" % (total / 147.0 * 100.0))


func test_generated_levels_metadata() -> void:
	var merged := _merged()
	for i in range(3, 150):
		var d: Dictionary = merged[i]
		check_eq(str(d.get("unit")), "half", "level %d half units" % d.id)
		check(str(d.get("generator_version", "")) == BoardGenerator.VERSION, "level %d generator version" % d.id)
		check(str(d.get("build", "")) != "" and str(d.get("seed", "")) != "", "level %d build + seed recorded" % d.id)
		check(typeof(d.get("metrics")) == TYPE_DICTIONARY, "level %d metrics" % d.id)
		var tc := int(d.tile_count)
		check(tc % 2 == 0 and tc <= 144, "level %d tile count %d" % [d.id, tc])
		if i >= 50:
			check(tc >= 56, "level %d at least 56 tiles" % d.id)


func test_levels_4_50_ordered_and_smooth() -> void:
	var merged := _merged()
	var prev := -INF
	var max_step := 0.0
	for i in range(3, 50):
		var s := float(merged[i].metrics.score)
		check(s >= prev, "level %d score %.1f not below previous %.1f" % [merged[i].id, s, prev])
		if prev > -INF:
			max_step = maxf(max_step, s - prev)
		prev = s
	check(max_step <= MAX_SCORE_STEP, "no sudden spikes in 4-50 (max step %.1f)" % max_step)


func test_levels_51_150_ordered() -> void:
	var merged := _merged()
	var prev := -INF
	for i in range(50, 150):
		var p := float(merged[i].metrics.progression)
		check(p >= prev, "level %d progression not below previous" % merged[i].id)
		prev = p


func test_trickiness_has_no_cliff() -> void:
	# What players feel as getting stuck must ramp smoothly across 4-150, incl. the 50/51 boundary.
	var merged := _merged()
	var dr: Array = []
	for i in range(3, 150):
		dr.append(float(merged[i].metrics.dead_end_rate))
	var ma: Array = []
	for i in dr.size():
		var lo := maxi(0, i - 3)
		var hi := mini(dr.size(), i + 4)
		var t := 0.0
		for k in range(lo, hi):
			t += dr[k]
		ma.append(t / (hi - lo))
	for i in range(1, ma.size()):
		check(absf(ma[i] - ma[i - 1]) <= MAX_TRICKINESS_STEP, "trickiness step at level %d is %.3f" % [i + 4, ma[i] - ma[i - 1]])


func test_worlds_get_progressively_harder() -> void:
	var merged := _merged()
	var avg := func(a: int, b: int, key: String) -> float:
		var t := 0.0
		for i in range(a - 1, b):
			t += float(merged[i].metrics[key])
		return t / float(b - a + 1)
	for key in ["dead_end_rate", "score"]:
		var w1: float = avg.call(21, 50, key)
		var w2: float = avg.call(51, 100, key)
		var w3: float = avg.call(101, 150, key)
		check(w2 > w1, "%s: Pearl Coast (%.2f) above levels 21-50 (%.2f)" % [key, w2, w1])
		check(w3 > w2, "%s: Crystal Nocturne (%.2f) above Pearl Coast (%.2f)" % [key, w3, w2])


func test_stored_metrics_reproduce() -> void:
	var merged := _merged()
	for id in [4, 30, 51, 120, 150]:
		var d: Dictionary = merged[id - 1]
		var L := LevelDefinition.from_dict(d, str(d.analysis_key))
		var an := DifficultyAnalyzer.analyze(L, 32, 11)
		check(is_equal_approx(float(an.score), float(d.metrics.score)), "level %d score reproduces (%.1f vs %.1f)" % [id, an.score, d.metrics.score])
		check(is_equal_approx(float(an.dead_end_rate), float(d.metrics.dead_end_rate)), "level %d dead-end rate reproduces" % id)


func test_pack_fallback_stays_valid_under_identical_rule() -> void:
	# If a generated file were missing, LevelCatalog falls back to pack boards normalised to
	# identical pairs; those must still be legal.
	var pack: Array = JSON.parse_string(FileAccess.get_file_as_string(LevelCatalog.PACK_PATH))
	check_eq(pack.size(), 150)
	for d in pack:
		var L := LevelDefinition.from_dict(LevelCatalog.identical_pairs(d))
		check(L.is_valid() and BoardSolver.replay_is_legal(L.build_state(), L.solution), "normalised pack level %d witness" % L.id)


func test_level_worlds_match_world_ranges() -> void:
	var worlds: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/config/worlds.json"))
	for d in _merged():
		var id := int(d.id)
		var expected := ""
		for w in worlds:
			if id >= int(w.levels[0]) and id <= int(w.levels[1]):
				expected = w.id
		check_eq(str(d.world), expected, "level %d world" % id)


func test_no_repeated_layout_back_to_back() -> void:
	var merged := _merged()
	for i in range(4, 150):
		check(str(merged[i].layout_id) != str(merged[i - 1].layout_id) or str(merged[i].layout_id).begins_with("proc:"), "levels %d/%d differ in layout" % [i, i + 1])


func test_invalid_json_rejected_gracefully() -> void:
	check(not LevelDefinition.from_dict({}).is_valid(), "empty")
	check(not LevelDefinition.from_dict({"tiles": "nope"}).is_valid(), "bad tiles type")
	check(not LevelDefinition.from_dict({"tiles": [{"x": 0.5, "y": 0, "z": 0, "face": "circle_1"}, {"x": 1, "y": 0, "z": 0, "face": "circle_1"}]}).is_valid(), "fractional coordinate")
	check(not LevelDefinition.from_dict({"tiles": [{"x": 0, "y": 0, "z": 0, "face": "circle_1"}]}).is_valid(), "odd count")
	var odd_faces := LevelDefinition.from_dict({"tiles": [{"x": 0, "y": 0, "z": 0, "face": "circle_1"}, {"x": 1, "y": 0, "z": 0, "face": "circle_2"}]})
	check(not BoardValidator.validate(odd_faces).ok, "incompatible face counts rejected")
