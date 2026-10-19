extends TestCase
## Mahjong Solitaire rule tests: freedom geometry, matching semantics, taps, undo.

func _half_level(tiles: Array) -> LevelDefinition:
	# tiles: [[gx, gy, z, face], ...] in half units
	var arr: Array = []
	for t in tiles:
		arr.append({"x": t[0], "y": t[1], "z": t[2], "face": t[3]})
	return LevelDefinition.from_dict({"id": 1, "unit": "half", "tiles": arr}, "half-test")


func test_row_left_right_blocking() -> void:
	# Classic rule, kept behind side_blocking for tools.
	var L := level_from_rows(["XXX"])
	var s := L.build_state()
	s.side_blocking = true
	check(s.is_free(0), "left end is free")
	check(not s.is_free(1), "middle tile blocked on both sides")
	check(s.is_free(2), "right end is free")
	check(s.clone().side_blocking, "clone keeps the rule")


func test_tray_rule_ignores_sides() -> void:
	var L := level_from_rows(["XXX"])
	var s := L.build_state()
	check(not s.side_blocking, "play uses the uncovered rule")
	check(s.is_free(0) and s.is_free(1) and s.is_free(2), "every uncovered tile is free, neighbours or not")


func test_single_side_open_is_enough() -> void:
	var L := level_from_rows(["XX"])
	var s := L.build_state()
	s.side_blocking = true
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
	check(not s.is_free(1), "middle covered")
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
	# Owner rule: identical tiles only - Flowers/Seasons included.
	check(not MahjongRules.can_match("flower_plum", "flower_orchid"), "different flowers never match")
	check(not MahjongRules.can_match("flower_plum", "flower_chrysanthemum"), "same shape, different colour: no match")
	check(not MahjongRules.can_match("season_spring", "season_winter"), "different seasons never match")
	check(not MahjongRules.can_match("flower_plum", "season_spring"), "flowers never match seasons")
	check(MahjongRules.can_match("flower_plum", "flower_plum"), "identical flowers match")
	check(MahjongRules.can_match("season_autumn", "season_autumn"), "identical seasons match")
	check(not MahjongRules.can_match("dragon_red", "dragon_green"), "dragons are distinct")
	check(not MahjongRules.can_match("bogus", "bogus"), "unknown faces never match")
	for f in MahjongRules.FACES:
		check(MahjongRules.can_match(f, f), "self match " + f)


func test_rules_json_matches_engine_defaults() -> void:
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/tile_match_rules.json"))
	check(typeof(rules) == TYPE_DICTIONARY, "rules json parses")
	check(MahjongRules.configure_from_rules_json(rules), "rules accepted")
	check(not MahjongRules.can_match("flower_bamboo_flower", "flower_chrysanthemum"), "no flower group in the game rules")
	check_eq(MahjongRules.key_count(), 42, "every one of the 42 faces is its own match key")
	check(MahjongRules.is_flower("flower_orchid") and MahjongRules.is_season("season_summer"), "families still known for stats")


func test_tap_flow_and_invalid_picks() -> void:
	# Row of four with a tile on top of tile 1 (index 7), and a second row of three.
	var faces := ["circle_1", "circle_2", "circle_2", "circle_1", "bamboo_4", "bamboo_4", "dragon_red", "dragon_red"]
	var L := level_from_rows(["XXXX", "....", "XXX."], [[".X.."]], faces)
	var g := GameSession.start(L)
	check_eq(g.tap(1).r, GameSession.Tap.BLOCKED, "covered tile blocked")
	check(g.tray.is_empty(), "blocked tap moves nothing")
	var r := g.tap(0)
	check_eq(r.r, GameSession.Tap.TO_TRAY, "free tile goes to the tray")
	check_eq(r.slot, 0)
	check_eq(g.tap(0).r, GameSession.Tap.IGNORED, "a tile in the tray cannot be tapped again")
	var r2 := g.tap(3)
	check_eq(r2.r, GameSession.Tap.MATCHED, "its twin clears both")
	check_eq(r2.partner, 0)
	check(g.tray.is_empty(), "matched pair leaves the tray")
	check_eq(g.stats.moves, 1, "one pair")
	check_eq(g.tap(7).r, GameSession.Tap.TO_TRAY, "top tile")
	check_eq(g.tap(1).r, GameSession.Tap.TO_TRAY, "uncovered once the top tile left")
	check_eq(g.tap(2).r, GameSession.Tap.MATCHED)
	check_eq(g.tap(6).r, GameSession.Tap.MATCHED)
	g.tap(4)
	var last := g.tap(5)
	check(last.won, "board cleared")
	check(g.completed, "completed flag")
	check_eq(g.tap(1).r, GameSession.Tap.IGNORED, "no input after completion")


func test_tray_slots_and_fail() -> void:
	var faces := ["circle_1", "circle_2", "circle_3", "circle_4", "circle_4", "circle_3", "circle_2", "circle_1"]
	var L := level_from_rows(["XXXXXXXX"], [], faces)
	var g := GameSession.start(L)
	for i in 3:
		check_eq(g.tap(i).r, GameSession.Tap.TO_TRAY, "unmatched tile %d fills slot" % i)
	check(g.tray_danger(), "one slot left")
	check_eq(g.tap(5).r, GameSession.Tap.MATCHED, "a 4th tile that matches never loses")
	check_eq(g.tray.size(), 2)
	g.tap(3)
	var r := g.tap(7)
	check_eq(r.r, GameSession.Tap.MATCHED)
	check_eq(g.tray, PackedInt32Array([1, 3]), "slots close up in arrival order")
	var g2 := GameSession.start(L)
	for i in 3:
		g2.tap(i)
	var f := g2.tap(3)
	check_eq(f.r, GameSession.Tap.FAILED, "4 unmatched tiles lose")
	check(g2.failed)
	check_eq(g2.stats.fails, 1)
	check_eq(g2.tap(4).r, GameSession.Tap.IGNORED, "no picks after a loss")
	check(not g2.has_moves())


func test_undo_restores_exact_state() -> void:
	var faces := ["circle_1", "circle_2", "circle_2", "circle_1", "bamboo_1", "bamboo_1"]
	var L := level_from_rows(["XXXX", ".XX."], [], faces)
	var g := GameSession.start(L)
	var before := g.state.clone()
	check(g.match_pair(0, 3), "ends")
	check(g.match_pair(1, 2), "middles")
	for k in 4:  # two picks per pair
		g.undo()
	check_eq(g.state.remaining, before.remaining, "remaining restored")
	check(g.state.removed == before.removed, "removed set restored")
	check(g.state.cover_cnt == before.cover_cnt and g.state.left_cnt == before.left_cnt and g.state.right_cnt == before.right_cnt, "blocker counters restored")
	check_eq(g.state.zhash, before.zhash, "hash restored")
	check(not g.can_undo(), "history empty")
	check_eq(g.stats.undos, 4)


func test_flower_season_pairs_in_play() -> void:
	var faces := ["flower_plum", "season_spring", "season_spring", "flower_plum"]
	var L := level_from_rows(["XX", "XX"], [], faces)
	var g := GameSession.start(L)
	check(not g.state.can_pair(0, 1), "flower vs season")
	check(g.match_pair(0, 3), "identical flowers")
	check(g.match_pair(1, 2), "identical seasons")
	var L2 := level_from_rows(["XX", "XX"], [], ["flower_plum", "flower_orchid", "flower_orchid", "flower_plum"])
	var g2 := GameSession.start(L2)
	g2.tap(0)
	check_eq(g2.tap(1).r, GameSession.Tap.TO_TRAY, "a different flower does not match")
	check_eq(g2.tray.size(), 2, "both wait in the tray")
	check_eq(g.stats.flowers_cleared, 2)
	check_eq(g.stats.seasons_cleared, 2)
	check(g.completed)


func test_no_moves_detection() -> void:
	var faces := ["circle_1", "circle_2", "circle_1", "circle_2"]
	var L := level_from_rows(["XXXX"], [], faces)
	var s := L.build_state()
	s.side_blocking = true
	check(not s.has_moves(), "ABAB row has no opening pair under the classic rule")
	check(s.available_pairs().is_empty())


func test_topmost_selection_semantics() -> void:
	# Covered tile under a free tile: tapping the covered one is BLOCKED even if same face.
	var L := level_from_rows(["X"], [["X"]], ["wind_east", "wind_east"])
	var g := GameSession.start(L)
	check_eq(g.tap(0).r, GameSession.Tap.BLOCKED, "covered tile cannot be picked")
	g.tap(1)
	check(not g.state.can_pair(1, 0), "cannot match a tile with the tile it covers")
