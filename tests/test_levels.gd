extends TestCase
## Content validation for the shipped journey (LevelCatalog): 6 worlds x 100 levels. Each world
## holds its 1.0 levels (1-3 supplied pack levels, the rest generated layered boards), then the 50
## levels 1.1.0 added, each build ordered by measured difficulty, with a tile floor that rises
## along the journey.

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


func test_levels_after_3_use_layered_templates() -> void:
	# Since 2026-10-22 every level after the 3 pack levels is a layered LayoutTemplates structure:
	# at least two layers (three from 1.0 level 51, four from 1.0 level 151, LevelCatalog
	# .legacy_position), real half-tile offsets, and the journey
	# mixes many families rather than one shape. Aligned tiers (a ziggurat) are a legitimate layout,
	# but nearly every board staggers somewhere.
	var merged := _merged()
	var families := {}
	var staggered := 0
	for i in range(3, merged.size()):
		var d: Dictionary = merged[i]
		var lid := str(d.get("layout_id", ""))
		check(lid.begins_with("tpl:%s:" % LayoutTemplates.VERSION), "level %d uses a layered template (%s)" % [d.id, lid])
		var fam := lid.get_slice(":", 2)
		check(LayoutTemplates.FAMILIES.has(fam), "level %d family %s" % [d.id, fam])
		families[fam] = int(families.get(fam, 0)) + 1
		var pos := LevelDefinition.from_dict(d).positions()
		var lp := LevelCatalog.legacy_position(int(d.id))
		var min_layers := 2 if lp < 51.0 else (3 if lp < 151.0 else 4)
		check(LayoutTemplates.layer_count(pos) >= min_layers, "level %d has %d layers" % [d.id, LayoutTemplates.layer_count(pos)])
		var half := 0
		for p in pos:
			if p.x % 2 != 0 or p.y % 2 != 0:
				half += 1
		if half > 0:
			staggered += 1
		if int(d.id) <= LevelCatalog.PER_WORLD:
			check_eq(str(d.world), "aurora_garden")
	check(families.size() >= 6, "levels use %d template families: %s" % [families.size(), families])
	check(staggered >= (merged.size() - 3) * 0.9, "%d of %d boards have half-tile offsets" % [staggered, merged.size() - 3])
	print("  template families: ", families)


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
	# Each build is ordered by its own progression value: 1.0 levels 51-150 and 151-300 (now the
	# first halves of worlds 2-6) and every world's second half.
	var merged := _merged()
	for w in range(1, LevelCatalog.WORLDS + 1):
		var base := (w - 1) * LevelCatalog.PER_WORLD
		var halves := [[base + LevelCatalog.LEGACY_PER_WORLD, base + LevelCatalog.PER_WORLD]]
		if w > 1:
			halves.append([base, base + LevelCatalog.LEGACY_PER_WORLD])
		for r in halves:
			var prev := -INF
			for i in range(r[0], r[1]):
				var p := float(merged[i].metrics.progression)
				check(p >= prev, "level %d progression not below previous" % merged[i].id)
				prev = p


func test_second_halves_continue_each_world() -> void:
	# 1.1.0: a world's levels 51-100 start about where its level 50 ends and finish harder, so the
	# next world opens with a short breather (a sawtooth), never with a jump.
	var merged := _merged()
	var avg := func(a: int, b: int, key: String) -> float:
		var t := 0.0
		for i in range(a - 1, b):
			t += float(merged[i].metrics[key])
		return t / float(b - a + 1)
	for w in range(1, LevelCatalog.WORLDS + 1):
		var base := (w - 1) * LevelCatalog.PER_WORLD
		var end_first: float = avg.call(base + 46, base + 50, "score")
		var start_second: float = avg.call(base + 51, base + 55, "score")
		var end_second: float = avg.call(base + 91, base + 100, "score")
		check(start_second >= end_first - 4.0, "world %d: levels 51-55 (%.1f) close to 46-50 (%.1f)" % [w, start_second, end_first])
		check(end_second >= end_first, "world %d: levels 91-100 (%.1f) not easier than 46-50 (%.1f)" % [w, end_second, end_first])
		if w < LevelCatalog.WORLDS:
			var next_start: float = avg.call(base + 101, base + 105, "score")
			check(next_start <= end_second + 2.0, "world %d opens (%.1f) no harder than world %d ends (%.1f)" % [w + 1, next_start, w, end_second])
		for i in range(base + LevelCatalog.LEGACY_PER_WORLD, base + LevelCatalog.PER_WORLD):
			check(merged[i].metrics.has("skill_fail_rate"), "level %d stores the skilled fail rate" % (i + 1))


func test_shipped_world_files_match_sources() -> void:
	# The game reads data/levels/world_N.json; tools/build_catalog.gd writes them from the source
	# files. Every 1.0 board keeps its order under its new number (LevelCatalog.new_id).
	var errs := PackedStringArray()
	var built := LevelCatalog.assemble(errs)
	check(errs.is_empty(), "sources load: %s" % [errs])
	var shipped := _merged()
	check_eq(built.size(), shipped.size(), "same level count")
	var differ := 0
	for i in mini(built.size(), shipped.size()):
		# Through JSON once, as the shipped file was (new ids are ints until then).
		if JSON.stringify(JSON.parse_string(JSON.stringify(built[i]))) != JSON.stringify(shipped[i]):
			differ += 1
			if differ <= 3:
				fail("level %d differs from its source: run tools/build_catalog.gd" % (i + 1))
	check_eq(differ, 0, "levels differing from their sources")
	var legacy := LevelCatalog.load_legacy()
	check_eq(legacy.size(), LevelCatalog.LEGACY_TOTAL, "1.0 levels")
	for o in [1, 4, 50, 51, 100, 101, 150, 151, 200, 201, 250, 251, 300]:
		var n := LevelCatalog.new_id(o)
		check_eq(LevelCatalog.world_of(n), (o - 1) / LevelCatalog.LEGACY_PER_WORLD + 1, "1.0 level %d stays in its world" % o)
		check(JSON.stringify(legacy[o - 1].tiles) == JSON.stringify(shipped[n - 1].tiles), "1.0 level %d is level %d with the same tiles" % [o, n])


func test_trickiness_has_no_cliff() -> void:
	# What players feel as getting stuck must change smoothly across the whole journey, incl. the
	# joins between a world's halves and the breather at each world's start.
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
	var ranges := [[21, LevelCatalog.PER_WORLD]]
	for w in ContentService.worlds.slice(1):
		ranges.append([int(w.levels[0]), int(w.levels[1])])
	for key in ["dead_end_rate", "score"]:
		for k in range(1, ranges.size()):
			var lo: float = avg.call(ranges[k - 1][0], ranges[k - 1][1], key)
			var hi: float = avg.call(ranges[k][0], ranges[k][1], key)
			check(hi > lo, "%s: levels %d-%d (%.2f) above %d-%d (%.2f)" % [key, ranges[k][0], ranges[k][1], hi, ranges[k - 1][0], ranges[k - 1][1], lo])


func test_stored_metrics_reproduce() -> void:
	var merged := _merged()
	for id in [4, 30, 75, 101, 160, 220, 250, 290, 301, 399, 420, 480, 550, 600]:
		var d: Dictionary = merged[id - 1]
		var L := LevelDefinition.from_dict(d, str(d.analysis_key))
		var an := DifficultyAnalyzer.analyze(L, 32, 11)
		check(is_equal_approx(float(an.score), float(d.metrics.score)), "level %d score reproduces (%.1f vs %.1f)" % [id, an.score, d.metrics.score])
		check(is_equal_approx(float(an.dead_end_rate), float(d.metrics.dead_end_rate)), "level %d dead-end rate reproduces" % id)
		if d.metrics.has("skill_fail_rate"):
			var sk := DifficultyAnalyzer.skilled_fail_rate(L, 32)
			check(is_equal_approx(snappedf(sk, 0.0001), float(d.metrics.skill_fail_rate)), "level %d skilled fail rate reproduces (%.4f vs %.4f)" % [id, sk, d.metrics.skill_fail_rate])


func test_pack_levels_stay_valid_under_identical_rule() -> void:
	# Levels 1-3 are pack boards normalised to identical pairs (LevelCatalog.identical_pairs); the
	# whole pack must stay legal under that rule.
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
