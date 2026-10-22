extends TestCase
## Content validation for the shipped journey:
##   1-3 supplied pack levels (unchanged), 4-50, 51-150 and 151-300 generated dense boards,
##   each range ordered by measured difficulty, with a tile floor that rises with the level.

const MAX_SCORE_STEP := 5.0
const MAX_TRICKINESS_STEP := 0.08   ## moving-average (window 7) dead-end rate change per level


func _merged() -> Array:
	return LevelCatalog.load_merged()


func test_all_shipped_levels_valid() -> void:
	var errs := PackedStringArray()
	var raw := LevelCatalog.load_merged(errs)
	check(errs.is_empty(), "catalog loads without fallback: %s" % [errs])
	check_eq(raw.size(), LevelCatalog.TOTAL, "%d levels" % LevelCatalog.TOTAL)
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


func test_levels_after_3_use_dense_layouts() -> void:
	# Since 2026-10-19 every level after the 3 pack levels is a dense, screen-filling board.
	var merged := _merged()
	for i in range(3, merged.size()):
		var d: Dictionary = merged[i]
		check(str(d.get("layout_id", "")).begins_with("dense:"), "level %d uses a dense layout" % d.id)
		if int(d.id) <= 50:
			check_eq(str(d.world), "aurora_garden")


func test_boards_fill_the_screen() -> void:
	# Owner request: boards use the phone screen as fully as possible, in width AND height, with
	# big tiles (BoardFit.PLAY_AREA = the measured board area in tray play, no banner).
	# Levels 1-3 are the small supplied pack boards: only a size floor applies to them.
	var merged := _merged()
	var worst := 999.0
	var worst_fill := 9.0
	for d in merged:
		var pos := LevelDefinition.from_dict(d).positions()
		var geo := BoardGeometry.from_positions(pos)
		var fit := BoardFit.fit_tile_width(geo, BoardFit.PLAY_AREA)
		if int(d.id) <= 3:
			check(fit >= 66.0, "pack level %d tiles only %.0f px" % [d.id, fit])
			continue
		var best := BoardFit.fit_tile_width(BoardGeometry.from_positions(BoardFit.best_orientation(pos)), BoardFit.PLAY_AREA)
		check(fit >= best - 0.01, "level %d not in its best orientation (%.0f vs %.0f px)" % [d.id, fit, best])
		var fr := LayoutGenerator.fill_ratio(pos, BoardFit.PLAY_AREA)
		check(fit >= 84.0, "level %d tiles only %.0f px" % [d.id, fit])
		check(fr.x >= 0.88 and fr.y >= 0.88, "level %d fills only %.0f%% x %.0f%% of the screen" % [d.id, fr.x * 100, fr.y * 100])
		worst = minf(worst, fit)
		worst_fill = minf(worst_fill, minf(fr.x, fr.y))
	print("  levels 4-%d: smallest tile %.1f px, least fill %.0f%%" % [merged.size(), worst, worst_fill * 100])


func test_daily_boards_fill_the_screen() -> void:
	var start := Time.get_unix_time_from_datetime_string("2026-10-01T12:00:00")
	for day in 30:
		var L := DailyGenerator.build(Time.get_date_string_from_unix_time(start + day * 86400))
		var pos := L.positions()
		var geo := BoardGeometry.from_positions(pos)
		var fit := BoardFit.fit_tile_width(geo, BoardFit.PLAY_AREA)
		var best := BoardFit.fit_tile_width(BoardGeometry.from_positions(BoardFit.best_orientation(pos)), BoardFit.PLAY_AREA)
		var fr := LayoutGenerator.fill_ratio(pos, BoardFit.PLAY_AREA)
		check(fit >= best - 0.01, "daily %s not in its best orientation" % L.key)
		check(fit >= 84.0, "daily %s tiles only %.0f px" % [L.key, fit])
		check(fr.x >= 0.88 and fr.y >= 0.88, "daily %s fills only %.0f%% x %.0f%%" % [L.key, fr.x * 100, fr.y * 100])


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
	# The pack placed ~74% of tiles opposite their identical twin. Shipped levels 4+ must not.
	var merged := _merged()
	var total := 0.0
	for i in range(3, merged.size()):
		var r := _mirror_rate(LevelDefinition.from_dict(merged[i]))
		total += r
		check(r < 0.4, "level %d mirrored twins %.0f%%" % [i + 1, r * 100.0])
	var n := float(merged.size() - 3)
	check(total / n < 0.15, "average mirrored twins %.0f%%" % (total / n * 100.0))


func test_generated_levels_metadata() -> void:
	var merged := _merged()
	for i in range(3, merged.size()):
		var d: Dictionary = merged[i]
		check_eq(str(d.get("unit")), "half", "level %d half units" % d.id)
		check(str(d.get("generator_version", "")) == BoardGenerator.VERSION, "level %d generator version" % d.id)
		check(str(d.get("build", "")) != "" and str(d.get("seed", "")) != "", "level %d build + seed recorded" % d.id)
		check(typeof(d.get("metrics")) == TYPE_DICTIONARY, "level %d metrics" % d.id)
		var tc := int(d.tile_count)
		check(tc % 2 == 0 and tc <= 144, "level %d tile count %d" % [d.id, tc])
		var floor_tiles := LevelCatalog.min_tiles(int(d.id)) - LevelCatalog.TILE_FLOOR_SLACK
		check(tc >= floor_tiles, "level %d has %d tiles, floor %d" % [d.id, tc, floor_tiles])


func test_tile_count_grows_with_level() -> void:
	# Owner request 2026-10-22: later levels must not fall back to small boards. Each world's
	# average board is bigger than the previous world's.
	var merged := _merged()
	var prev := 0.0
	for w in ContentService.worlds:
		var a := maxi(int(w.levels[0]), 4)
		var b := int(w.levels[1])
		var t := 0.0
		for i in range(a - 1, b):
			t += float(merged[i].tile_count)
		var avg := t / float(b - a + 1)
		check(avg > prev, "world %s averages %.1f tiles, previous %.1f" % [w.id, avg, prev])
		prev = avg


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


func test_generated_ranges_ordered() -> void:
	# 51-150 and 151-300 are separate builds, each ordered by its own progression value.
	var merged := _merged()
	for r in [[50, 150], [150, merged.size()]]:
		var prev := -INF
		for i in range(r[0], r[1]):
			var p := float(merged[i].metrics.progression)
			check(p >= prev, "level %d progression not below previous" % merged[i].id)
			prev = p


func test_trickiness_has_no_cliff() -> void:
	# What players feel as getting stuck must ramp smoothly across 4-300, incl. the 50/51 and
	# 150/151 boundaries.
	var merged := _merged()
	var dr: Array = []
	for i in range(3, merged.size()):
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
	# Aurora Garden is compared from level 21 (its first levels are the gentle introduction).
	var ranges := [[21, 50]]
	for w in ContentService.worlds.slice(1):
		ranges.append([int(w.levels[0]), int(w.levels[1])])
	for key in ["dead_end_rate", "score"]:
		for k in range(1, ranges.size()):
			var lo: float = avg.call(ranges[k - 1][0], ranges[k - 1][1], key)
			var hi: float = avg.call(ranges[k][0], ranges[k][1], key)
			check(hi > lo, "%s: levels %d-%d (%.2f) above %d-%d (%.2f)" % [key, ranges[k][0], ranges[k][1], hi, ranges[k - 1][0], ranges[k - 1][1], lo])


func test_stored_metrics_reproduce() -> void:
	var merged := _merged()
	for id in [4, 30, 51, 120, 150, 151, 220, 300]:
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
	for i in range(4, merged.size()):
		check(str(merged[i].layout_id) != str(merged[i - 1].layout_id) or str(merged[i].layout_id).begins_with("proc:"), "levels %d/%d differ in layout" % [i, i + 1])


func test_invalid_json_rejected_gracefully() -> void:
	check(not LevelDefinition.from_dict({}).is_valid(), "empty")
	check(not LevelDefinition.from_dict({"tiles": "nope"}).is_valid(), "bad tiles type")
	check(not LevelDefinition.from_dict({"tiles": [{"x": 0.5, "y": 0, "z": 0, "face": "circle_1"}, {"x": 1, "y": 0, "z": 0, "face": "circle_1"}]}).is_valid(), "fractional coordinate")
	check(not LevelDefinition.from_dict({"tiles": [{"x": 0, "y": 0, "z": 0, "face": "circle_1"}]}).is_valid(), "odd count")
	var odd_faces := LevelDefinition.from_dict({"tiles": [{"x": 0, "y": 0, "z": 0, "face": "circle_1"}, {"x": 1, "y": 0, "z": 0, "face": "circle_2"}]})
	check(not BoardValidator.validate(odd_faces).ok, "incompatible face counts rejected")
