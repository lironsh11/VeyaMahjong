extends TestCase
## Solver, generator, shuffle/rescue and session persistence tests.

func test_solver_solves_simple() -> void:
	var L := level_from_rows(["XXXX"], [], ["circle_1", "circle_2", "circle_2", "circle_1"])
	var res := BoardSolver.new().solve(L.build_state())
	check_eq(res.result, BoardSolver.Result.SOLVED)
	check(BoardSolver.replay_is_legal(L.build_state(), res.solution), "solution legal")


func test_solver_proves_unsolvable() -> void:
	var L := level_from_rows(["XXXX"], [], ["circle_1", "circle_2", "circle_1", "circle_2"])
	check_eq(BoardSolver.new().solve(L.build_state()).result, BoardSolver.Result.UNSOLVABLE)
	# Same-face stack: top can never pair with the tile beneath it.
	var S := level_from_rows(["X"], [["X"]], ["wind_east", "wind_east"])
	check_eq(BoardSolver.new().solve(S.build_state()).result, BoardSolver.Result.UNSOLVABLE)


func test_solver_budget_is_reported_not_guessed() -> void:
	var L := LevelDefinition.from_dict(_pack_level(150))
	var res := BoardSolver.new(3).solve(L.build_state())
	check(res.result == BoardSolver.Result.BUDGET or res.result == BoardSolver.Result.SOLVED, "tiny budget -> BUDGET")
	if res.result == BoardSolver.Result.BUDGET:
		check(res.solution.is_empty(), "no partial solution claimed")


func test_solver_does_not_mutate_input() -> void:
	var L := LevelDefinition.from_dict(_pack_level(20))
	var s := L.build_state()
	var before := s.removed.duplicate()
	BoardSolver.new().solve(s)
	check(s.removed == before and s.remaining == L.tiles.size(), "input state untouched")


func test_generator_deterministic_and_valid() -> void:
	var layout := _pack_layout_positions(9)
	var gen := BoardGenerator.new()
	var a := gen.generate_level(layout, "seed-A")
	var b := gen.generate_level(layout, "seed-A")
	var c := gen.generate_level(layout, "seed-B")
	check(a.is_valid(), "generated level valid: %s" % [a.errors])
	check(a.faces() == b.faces(), "same seed -> same board")
	check(a.faces() != c.faces(), "different seed -> different board")
	var rep := BoardValidator.validate(a)
	check(rep.ok, "validator accepts generated board: %s" % [rep.errors])


func test_generator_sample_batch() -> void:
	# Deterministic sample across all 50 pack layouts and procedural layouts.
	var gen := BoardGenerator.new()
	var failures := 0
	var total := 0
	var layouts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/layouts_50.json"))
	for li in layouts.size():
		var pos: Array = []
		for p in layouts[li].positions:
			pos.append(Vector3i(int(p[0]) * 2, int(p[1]) * 2, int(p[2])))
		var L := gen.generate_level(pos, "batch-%d" % li)
		total += 1
		if not L.is_valid() or not BoardSolver.replay_is_legal(L.build_state(), L.solution):
			failures += 1
	for k in 20:
		var rng := SeededRng.new(1000 + k)
		var pos2 := LayoutGenerator.generate(rng, 72)
		var L2 := gen.generate_level(pos2, "proc-%d" % k)
		total += 1
		if not L2.is_valid():
			# Procedural geometry may be unclearable; generator must say so, never fake it.
			check(not L2.errors.is_empty(), "invalid result carries an error")
			continue
		if not BoardSolver.replay_is_legal(L2.build_state(), L2.solution):
			failures += 1
	check_eq(failures, 0, "all generated boards replay legally (%d boards)" % total)


func test_generator_never_mutates_shared_constants() -> void:
	# Regression: shuffling a view of MahjongRules.FLOWERS made generation alternate between runs.
	var before := [Array(MahjongRules.FLOWERS), Array(MahjongRules.SEASONS)]
	var layout := _pack_layout_positions(32)
	var gen := BoardGenerator.new()
	var fps: Array = []
	for k in 4:
		fps.append(",".join(gen.generate_level(layout, "repeat").faces()))
	check(fps[0] == fps[1] and fps[1] == fps[2] and fps[2] == fps[3], "identical output on repeated calls")
	check(Array(MahjongRules.FLOWERS) == before[0] and Array(MahjongRules.SEASONS) == before[1], "constants untouched")


func test_procedural_layout_deterministic() -> void:
	var a := LayoutGenerator.generate(SeededRng.new(42), 64)
	var b := LayoutGenerator.generate(SeededRng.new(42), 64)
	check(a == b, "same seed -> same layout")
	check(a.size() % 2 == 0, "even tile count")
	var geo := BoardGeometry.from_positions(a)
	check(geo.errors.is_empty(), "no overlaps: %s" % [geo.errors])
	for i in geo.count:
		check(geo.is_supported(i), "tile %d supported" % i)


func test_rng_stable_values() -> void:
	# Pin the PRNG so content seeds never drift across engine versions.
	var r := SeededRng.new(12345)
	var seq := [r.next_u63(), r.next_u63(), r.next_u63()]
	var r2 := SeededRng.new(12345)
	check(seq == [r2.next_u63(), r2.next_u63(), r2.next_u63()], "reproducible")
	for v in seq:
		check(v >= 0, "non-negative")
	check_eq(SeededRng.hash_string(""), -3750763034362895579, "FNV offset basis")
	check_eq(SeededRng.hash_string("a"), -5808556873153909620, "FNV-1a('a') = 0xaf63dc4c8601ec8c")


func test_shuffle_preserves_faces_and_is_solvable() -> void:
	var L := LevelDefinition.from_dict(_pack_level(45))
	var g := GameSession.start(L)
	# play a few witness moves first
	for k in 4:
		var p: Vector2i = L.solution[k]
		check(g.match_pair(p.x, p.y), "witness move %d" % k)
	var before := Array(g.state.faces)
	var removed_before := g.state.removed.duplicate()
	var res := g.shuffle()
	check(res.ok, "shuffle succeeded")
	check(g.state.removed == removed_before, "shuffle never changes removed tiles")
	var after := Array(g.state.faces)
	var x := before.duplicate(); x.sort()
	var y := after.duplicate(); y.sort()
	check(x == y, "face multiset preserved")
	check(BoardSolver.replay_is_legal(g.state, res.solution), "shuffle witness legal")
	check_eq(g.checkpoint, g.history.size(), "checkpoint advanced")
	g.undo()
	check(Array(g.state.faces) == before, "undo reverts the shuffle")


func test_shuffle_reports_impossible_geometry() -> void:
	var L := level_from_rows(["X"], [["X"]], ["wind_east", "wind_east"])
	var g := GameSession.start(L)
	var res := g.shuffle()
	check(not res.ok, "stacked pair can never be cleared")
	check_eq(res.reason, "geometry")
	check(g.history.is_empty(), "failed shuffle records nothing")


func test_session_roundtrip() -> void:
	var L := LevelDefinition.from_dict(_pack_level(77))
	var g := GameSession.start(L)
	for k in 5:
		g.match_pair(L.solution[k].x, L.solution[k].y)
	g.shuffle()
	g.stats.hints = 2
	var d := g.to_dict()
	var json := JSON.stringify(d)
	var g2 := GameSession.restore(L, JSON.parse_string(json))
	check(g2 != null, "restored")
	if g2 == null:
		return
	check(g2.state.faces == g.state.faces, "faces")
	check(g2.state.removed == g.state.removed, "removed")
	check(g2.state.cover_cnt == g.state.cover_cnt and g2.state.left_cnt == g.state.left_cnt, "counters")
	check_eq(g2.history.size(), g.history.size(), "history")
	check_eq(g2.stats.hints, 2, "stats")
	g2.undo()
	g.undo()
	check(g2.state.faces == g.state.faces, "undo after restore behaves identically")


func test_session_restore_rejects_foreign_snapshot() -> void:
	var L1 := LevelDefinition.from_dict(_pack_level(3))
	var L2 := LevelDefinition.from_dict(_pack_level(4))
	var d := GameSession.start(L1).to_dict()
	check(GameSession.restore(L2, d) == null, "snapshot for another level rejected")
	d.faces[0] = "dragon_red" if d.faces[0] != "dragon_red" else "dragon_green"
	check(GameSession.restore(L1, d) == null, "tampered faces rejected")
	var d2 := GameSession.start(L1).to_dict()
	d2.removed = [0]
	check(GameSession.restore(L1, d2) == null, "odd removed set rejected")


func test_undo_to_checkpoint() -> void:
	var L := LevelDefinition.from_dict(_pack_level(12))
	var g := GameSession.start(L)
	g.match_pair(L.solution[0].x, L.solution[0].y)
	g.mark_solvable_now()
	g.match_pair(L.solution[1].x, L.solution[1].y)
	g.match_pair(L.solution[2].x, L.solution[2].y)
	check_eq(g.undo_to_checkpoint(), 2, "rewinds to checkpoint")
	check_eq(g.history.size(), 1)


# --- helpers -------------------------------------------------------------------------

static var _levels_cache: Array = []

func _pack_level(id: int) -> Dictionary:
	## Pack boards as the game would use them (identical-tiles-only rule).
	if _levels_cache.is_empty():
		_levels_cache = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/levels_001_150_verified.json"))
	return LevelCatalog.identical_pairs(_levels_cache[id - 1])


func _pack_layout_positions(idx: int) -> Array:
	var layouts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/layouts_50.json"))
	var pos: Array = []
	for p in layouts[idx].positions:
		pos.append(Vector3i(int(p[0]) * 2, int(p[1]) * 2, int(p[2])))
	return pos
