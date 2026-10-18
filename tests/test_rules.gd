extends TestCase
## Mahjong Solitaire rule tests: freedom geometry, matching semantics, taps, undo.

func _half_level(tiles: Array) -> LevelDefinition:
	# tiles: [[gx, gy, z, face], ...] in half units
	var arr: Array = []
	for t in tiles:
		arr.append({"x": t[0], "y": t[1], "z": t[2], "face": t[3]})
	return LevelDefinition.from_dict({"id": 1, "unit": "half", "tiles": arr}, "half-test")


func test_row_left_right_blocking() -> void:
	var L := level_from_rows(["XXX"])
	var s := L.build_state()
	check(s.is_free(0), "left end is free")
	check(not s.is_free(1), "middle tile blocked on both sides")
	check(s.is_free(2), "right end is free")


func test_single_side_open_is_enough() -> void:
	var L := level_from_rows(["XX"])
	var s := L.build_state()
	check(s.is_free(0) and s.is_free(1), "both tiles of a 2-row have one open side")


func test_top_cover_blocks() -> void:
	var L := level_from_rows(["X"], [["X"]])
	var s := L.build_state()
	check(not s.is_free(0), "bottom tile covered")
	check(s.is_free(1), "top tile free")
	check(s.is_covered(0), "covered flag")


func test_cover_released_after_removal() -> void:
	# base: X X X  ; top layer over the middle tile
	var faces := ["circle_1", "circle_2", "circle_1", "circle_2"]
	var L := level_from_rows(["XXX"], [[".X."]], faces)
	var s := L.build_state()
	check(not s.is_free(1), "middle covered and side-blocked")
	check(s.remove_pair(0, 2), "ends match")
	check(not s.is_free(1), "middle still covered by tile 3")
	check(s.is_free(3), "top tile free")


func test_partial_overlap_half_units() -> void:
	# Two ground tiles side by side; a cap offset by half a tile covers BOTH.
	var L := _half_level([[0, 0, 0, "bamboo_1"], [2, 0, 0, "bamboo_2"], [1, 0, 1, "bamboo_3"]])
	var geo := L.build_geometry()
	check(geo.errors.is_empty(), "valid geometry")
	var s := L.build_state(geo)
	check(not s.is_free(0) and not s.is_free(1), "both ground tiles covered by half-offset cap")
	check(s.is_free(2), "cap free")
	check(geo.is_supported(2), "cap supported")


func test_half_row_offset_side_blocking() -> void:
	# B is half a row lower but still touches A's right edge -> blocks it.
	var L := _half_level([[0, 0, 0, "a"], [2, 1, 0, "b"], [-2, 0, 0, "c"]])
	# faces invalid on purpose -> errors; build geometry directly instead
	var geo := BoardGeometry.from_positions([Vector3i(0, 0, 0), Vector3i(2, 1, 0), Vector3i(-2, 0, 0)])
	check(geo.right[0].has(1), "half-offset neighbour touches right edge")
	check(geo.left[0].has(2), "left neighbour")
	var far := BoardGeometry.from_positions([Vector3i(0, 0, 0), Vector3i(2, 2, 0)])
	check(far.right[0].is_empty(), "no vertical overlap -> no blocking")
	var gap := BoardGeometry.from_positions([Vector3i(0, 0, 0), Vector3i(3, 0, 0)])
	check(gap.right[0].is_empty(), "half-tile gap -> not touching -> no blocking")
	check(not L.is_valid(), "unknown faces rejected by LevelDefinition")


func test_same_layer_overlap_is_error() -> void:
	var geo := BoardGeometry.from_positions([Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	check(not geo.errors.is_empty(), "overlapping tiles on one layer rejected")


func test_matching_semantics() -> void:
	check(MahjongRules.can_match("character_5", "character_5"), "identical faces match")
	check(not MahjongRules.can_match("character_5", "character_6"), "different faces don't")
	check(MahjongRules.can_match("flower_plum", "flower_orchid"), "any flower matches any flower")
	check(MahjongRules.can_match("season_spring", "season_winter"), "any season matches any season")
	check(not MahjongRules.can_match("flower_plum", "season_spring"), "flowers never match seasons")
	check(not MahjongRules.can_match("dragon_red", "dragon_green"), "dragons are distinct")
	check(not MahjongRules.can_match("bogus", "bogus"), "unknown faces never match")
	for f in MahjongRules.FACES:
		check(MahjongRules.can_match(f, f), "self match " + f)


func test_rules_json_matches_engine_defaults() -> void:
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/tile_match_rules.json"))
	check(typeof(rules) == TYPE_DICTIONARY, "rules json parses")
	check(MahjongRules.configure_from_rules_json(rules), "rules accepted")
	check(MahjongRules.can_match("flower_bamboo_flower", "flower_chrysanthemum"), "pack flower group")
	check_eq(MahjongRules.key_count(), 36, "34 normal faces + 2 bonus groups")


func test_tap_flow_and_invalid_picks() -> void:
	var faces := ["circle_1", "circle_2", "circle_2", "circle_1"]
	var L := level_from_rows(["XXXX"], [], faces)
	var g := GameSession.start(L)
	check_eq(g.tap(1).r, GameSession.Tap.BLOCKED, "middle tile blocked")
	check_eq(g.selected, -1, "blocked tap does not select")
	check_eq(g.tap(0).r, GameSession.Tap.SELECTED, "select free tile")
	check_eq(g.tap(0).r, GameSession.Tap.DESELECTED, "duplicate tap deselects")
	g.tap(0)
	var r := g.tap(3)
	check_eq(r.r, GameSession.Tap.MATCHED, "ends match")
	check_eq(g.tap(0).r, GameSession.Tap.IGNORED, "removed tile ignored (duplicate tap after match)")
	check_eq(g.state.remaining, 2)
	g.tap(1)
	var r2 := g.tap(2)
	check(r2.won, "board cleared")
	check(g.completed, "completed flag")
	check_eq(g.tap(1).r, GameSession.Tap.IGNORED, "no input after completion")


func test_mismatch_moves_selection() -> void:
	var faces := ["circle_1", "circle_2", "circle_2", "circle_1"]
	var L := level_from_rows(["XX", "XX"], [], faces)
	var g := GameSession.start(L)
	g.tap(0)
	var r := g.tap(1)
	check_eq(r.r, GameSession.Tap.RESELECTED, "non-matching free tile moves selection")
	check_eq(g.selected, 1)
	check_eq(g.state.remaining, 4, "nothing removed on mismatch")


func test_undo_restores_exact_state() -> void:
	var faces := ["circle_1", "circle_2", "circle_2", "circle_1", "bamboo_1", "bamboo_1"]
	var L := level_from_rows(["XXXX", ".XX."], [], faces)
	var g := GameSession.start(L)
	var before := g.state.clone()
	check(g.match_pair(0, 3), "ends")
	check(g.match_pair(1, 2), "middles")
	g.undo()
	g.undo()
	check_eq(g.state.remaining, before.remaining, "remaining restored")
	check(g.state.removed == before.removed, "removed set restored")
	check(g.state.cover_cnt == before.cover_cnt and g.state.left_cnt == before.left_cnt and g.state.right_cnt == before.right_cnt, "blocker counters restored")
	check_eq(g.state.zhash, before.zhash, "hash restored")
	check(not g.can_undo(), "history empty")
	check_eq(g.stats.undos, 2)


func test_flower_season_pairs_in_play() -> void:
	var faces := ["flower_plum", "season_spring", "season_autumn", "flower_orchid"]
	var L := level_from_rows(["XX", "XX"], [], faces)
	var g := GameSession.start(L)
	check(not g.state.can_pair(0, 1), "flower vs season")
	check(g.match_pair(0, 3), "flower vs flower")
	check(g.match_pair(1, 2), "season vs season")
	check_eq(g.stats.flowers_cleared, 2)
	check_eq(g.stats.seasons_cleared, 2)
	check(g.completed)


func test_no_moves_detection() -> void:
	var faces := ["circle_1", "circle_2", "circle_1", "circle_2"]
	var L := level_from_rows(["XXXX"], [], faces)
	var s := L.build_state()
	check(not s.has_moves(), "ABAB row has no opening move")
	check(s.available_pairs().is_empty())


func test_topmost_selection_semantics() -> void:
	# Covered tile under a free tile: tapping the covered one is BLOCKED even if same face.
	var L := level_from_rows(["X"], [["X"]], ["wind_east", "wind_east"])
	var g := GameSession.start(L)
	check_eq(g.tap(0).r, GameSession.Tap.BLOCKED, "covered tile cannot be picked")
	g.tap(1)
	check(not g.state.can_pair(1, 0), "cannot match a tile with the tile it covers")
