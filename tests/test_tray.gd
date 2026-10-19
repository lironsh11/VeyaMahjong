extends TestCase
## Tray play: undo, second chance, saves (incl. v1 conversion), tray-aware shuffle, the tray
## solver (against brute force) and the claim that every shipped witness is a tray witness.


func _row8() -> LevelDefinition:
	# c1 c2 c3 c4 c4 c3 c2 c1 on one row: all free under the tray rule.
	return level_from_rows(["XXXXXXXX"], [], ["circle_1", "circle_2", "circle_3", "circle_4", "circle_4", "circle_3", "circle_2", "circle_1"])


func test_undo_plain_and_matching_picks() -> void:
	var g := GameSession.start(_row8())
	var start := g.state.clone()
	g.tap(0)
	g.tap(1)
	g.tap(6)  # matches tile 1 in slot 1
	check_eq(g.tray, PackedInt32Array([0]))
	var u := g.undo()
	check_eq(u.t, "p")
	check_eq(int(u.partner), 1, "undoing a match brings the partner back")
	check_eq(g.tray, PackedInt32Array([0, 1]), "partner back in its old slot")
	check(not g.state.is_removed(6), "picked tile back on the board")
	g.undo()
	g.undo()
	check(g.tray.is_empty())
	check(g.state.removed == start.removed and g.state.cover_cnt == start.cover_cnt, "board restored exactly")
	check_eq(g.state.zhash, start.zhash)
	check(g.state.key_remaining == start.key_remaining, "key counts restored")


func test_undo_after_fail_reopens_play() -> void:
	var g := GameSession.start(_row8())
	for i in 4:
		g.tap(i)
	check(g.failed)
	g.undo()
	check(not g.failed, "undo clears the loss")
	check_eq(g.tray.size(), 3)
	check_eq(g.tap(5).r, GameSession.Tap.MATCHED, "play continues (c3 meets its twin)")


func test_send_back_second_chance() -> void:
	var g := GameSession.start(_row8())
	for i in 4:
		g.tap(i)
	var r := g.send_back(3)
	check_eq(r.tiles, PackedInt32Array([1, 2, 3]), "newest three return")
	check(not g.failed)
	check_eq(g.tray, PackedInt32Array([0]))
	for i in [1, 2, 3]:
		check(g.state.is_free(i), "tile %d free again on the board" % i)
	check(g.state.face_counts_valid(g.tray), "board + tray still pair up")
	g.undo()
	check(g.failed, "undoing the send-back restores the full tray")
	check_eq(g.tray, PackedInt32Array([0, 1, 2, 3]))
	var g2 := GameSession.start(_row8())
	for i in 4:
		g2.tap(i)
	g2.send_back(3)
	var picks := PackedInt32Array([7, 1, 6, 2, 5, 3, 4])
	for p in picks:
		g2.tap(p)
	check(g2.completed, "board clears after a second chance")


func test_score_follows_undo() -> void:
	var g := GameSession.start(_row8())
	g.tap(3)
	g.tap(4)
	g.award(30, 3)
	check_eq(g.score, 30)
	check_eq(int(g.stats.best_combo), 3)
	g.undo()
	check_eq(g.score, 0, "undoing a match takes its points back")


func test_v2_roundtrip_with_tray() -> void:
	var L := level_from_rows(["XXXXXXXXXX"], [], ["circle_1", "circle_2", "circle_3", "circle_4", "circle_5", "circle_5", "circle_4", "circle_3", "circle_2", "circle_1"])
	var g := GameSession.start(L)
	g.tap(4)
	g.tap(5)
	g.award(10, 1)
	for i in 4:
		g.tap(i)
	check(g.failed)
	var g2 := GameSession.restore(L, JSON.parse_string(JSON.stringify(g.to_dict())))
	check(g2 != null, "restored")
	if g2 == null:
		return
	check_eq(g2.tray, g.tray, "tray order")
	check(g2.failed, "a full tray is restored as a loss")
	check_eq(g2.score, 10)
	check(g2.state.removed == g.state.removed and g2.state.cover_cnt == g.state.cover_cnt)
	g2.undo()
	g.undo()
	check_eq(g2.tray, g.tray, "undo after restore behaves identically")
	var bad := g.to_dict()
	bad.tray = [1, 1]
	check(GameSession.restore(L, bad) == null, "duplicate tray tile rejected")
	var bad2 := g.to_dict()
	bad2.tray = [6]
	check(GameSession.restore(L, bad2) == null, "a tray tile that is still on the board is rejected")


func test_v1_snapshot_converts() -> void:
	var L := LevelDefinition.from_dict(_pack_level(20))
	var removed: Array = []
	var hist: Array = []
	for k in 3:
		var p: Vector2i = L.solution[k]
		removed.append(p.x)
		removed.append(p.y)
		hist.append({"t": "m", "a": p.x, "b": p.y})
	var v1 := {"v": 1, "level_key": L.key, "faces": Array(L.faces()), "removed": removed, "history": hist,
		"stats": {"moves": 3}, "checkpoint": 2, "shuffle_counter": 0}
	var g := GameSession.restore(L, v1)
	check(g != null, "classic save restores")
	if g == null:
		return
	check(g.tray.is_empty())
	check_eq(g.history.size(), 6, "each pair is two picks")
	check_eq(g.checkpoint, 4, "checkpoint keeps pointing after the same pairs")
	g.undo()
	check_eq(g.tray.size(), 1, "undoing the 2nd pick of a pair leaves its twin in the tray")
	g.undo()
	check(g.tray.is_empty())
	check_eq(g.state.remaining, L.tiles.size() - 4)


func test_shuffle_with_tray_is_solvable() -> void:
	for id in [7, 33, 61, 120]:
		var L := LevelDefinition.from_dict(_pack_level(id))
		for seed_k in 3:
			var g := GameSession.start(L)
			var rng := SeededRng.new(1000 * id + seed_k)
			# Random picks that keep a slot free, so the tray holds a few tiles.
			for n in 9:
				var free := g.state.free_tiles()
				var i: int = free[rng.rand_int(0, free.size() - 1)]
				if g.tray.size() >= 2 and TrayRules.partner_slot(g.tray, g.state.keys, i) < 0:
					continue
				g.tap(i)
			var tray_before := g.tray.duplicate()
			var faces_before := Array(g.state.faces)
			var res := g.shuffle()
			check(res.ok, "shuffle ok on level %d" % id)
			if not res.ok:
				continue
			check_eq(g.tray, tray_before, "tray untouched")
			check(TraySolver.replay_is_legal(g.state, g.tray, res.solution), "witness clears board and tray (level %d)" % id)
			var a := faces_before.duplicate(); a.sort()
			var b := Array(g.state.faces); b.sort()
			check(a == b, "face multiset preserved")
			for t in g.tray:
				check_eq(g.state.faces[t], faces_before[t], "tray faces never change")


func test_every_shipped_witness_is_a_tray_witness() -> void:
	check_eq(ContentService.level_count(), 150)
	for id in range(1, ContentService.level_count() + 1):
		var L := ContentService.get_level(id)
		var picks := TraySolver.flatten(L.solution)
		if not check(TraySolver.replay_is_legal(L.build_state(), PackedInt32Array(), picks), "level %d witness" % L.id):
			return


func test_tray_solver_solves_shipped_levels() -> void:
	for id in [1, 50, 100, 150]:
		var L := LevelDefinition.from_dict(_pack_level(id))
		var st := L.build_state()
		var r := TraySolver.new(200000).solve(st)
		check_eq(r.result, BoardSolver.Result.SOLVED, "level %d" % id)
		check(TraySolver.replay_is_legal(st, PackedInt32Array(), r.solution), "solution legal")


func test_tray_solver_matches_brute_force() -> void:
	var rng := SeededRng.new(4242)
	var shapes := [
		[["XXX", "XXX"], [[".X.", ".X."]]],
		[["XXXX"], [[".XX."]]],
		[["XXXXXX"], [["XX...."]]],
		[["XX", "XX", "XX"], [["XX"]]],
	]
	var faces_pool := ["circle_1", "circle_2", "circle_3", "bamboo_5", "dragon_red", "wind_east"]
	for trial in 40:
		var shape: Array = shapes[trial % shapes.size()]
		var probe := level_from_rows(shape[0], shape[1])
		var n := probe.tiles.size()
		if n % 2 != 0:
			continue
		var fs: Array = []
		for k in n / 2:
			var f: String = faces_pool[rng.rand_int(0, faces_pool.size() - 1)]
			fs.append(f)
			fs.append(f)
		rng.shuffle(fs)
		var L := level_from_rows(shape[0], shape[1], fs)
		var st := L.build_state()
		for cap in [2, 3, 4]:
			var r := TraySolver.new(100000, 0, cap).solve(st)
			var brute := _brute(st.clone(), PackedInt32Array(), cap)
			check_eq(r.result == BoardSolver.Result.SOLVED, brute, "trial %d cap %d" % [trial, cap])
			if r.result == BoardSolver.Result.SOLVED:
				check(TraySolver.replay_is_legal(st, PackedInt32Array(), r.solution, cap), "legal")


func test_hint_names_a_free_safe_pick() -> void:
	var L := LevelDefinition.from_dict(_pack_level(30))
	var st := L.build_state()
	var h := BoardController.compute_hint(st, PackedInt32Array())
	var tiles: PackedInt32Array = h.tiles
	check(not tiles.is_empty(), "something to pick")
	check(st.is_free(tiles[0]), "hinted tile is free")
	check(h.safe, "proven by the solver")
	var g := GameSession.start(_row8())
	g.tap(0)
	var h2 := BoardController.compute_hint(g.state, g.tray)
	check_eq(PackedInt32Array(h2.tiles), PackedInt32Array([7]), "the twin of a tray tile comes first")


# --- helpers -------------------------------------------------------------------------

func _brute(s: BoardState, tray: PackedInt32Array, cap: int) -> bool:
	if s.remaining == 0:
		return tray.is_empty()
	for i in s.free_tiles():
		var slot := TrayRules.partner_slot(tray, s.keys, i)
		var t := tray.duplicate()
		if slot >= 0:
			t.remove_at(slot)
		else:
			t.append(i)
			if t.size() >= cap:
				continue
		s.take(i)
		var ok := _brute(s, t, cap)
		s.put_back(i)
		if ok:
			return true
	return false


static var _levels_cache: Array = []

func _all_levels() -> Array:
	if _levels_cache.is_empty():
		var raw: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/levels_001_150_verified.json"))
		for d in raw:
			_levels_cache.append(LevelCatalog.identical_pairs(d))
	return _levels_cache


func _pack_level(id: int) -> Dictionary:
	return _all_levels()[id - 1]


func test_tray_art_slots_fit_tiles() -> void:
	# Frame art for every capacity the game can reach (4 base, up to 6 with extra slots), with
	# the measured slots (tools/measure_tray_art.gd) and a tile body that fits each slot.
	for cap in range(TrayRules.CAPACITY, GameSession.MAX_CAPACITY + 1):
		var art := TrayView.art_for(cap)
		if not check(not art.is_empty(), "art for %d slots" % cap):
			continue
		var slots: Array = art.slots
		check_eq(slots.size(), cap, "slot count %d" % cap)
		for k in range(1, slots.size()):
			var a: Rect2 = slots[k - 1]
			var b: Rect2 = slots[k]
			check(b.position.x >= a.end.x, "slots %d/%d don't overlap" % [k - 1, k])
		var tv := TrayView.new()
		tv.capacity = cap
		tv.size = Vector2(BoardFit.PLAY_AREA.x, TrayView.TRAY_H)
		var ts := tv.tile_size()
		var r := tv.slot_rect(0)
		var body := Rect2(tv.slot_pos(0) + BoardView.BODY.position * ts, BoardView.BODY.size * ts)
		check(r.grow(0.5).encloses(body), "tile body inside slot (cap %d)" % cap)
		check(ts.x >= 48.0, "tray tiles stay readable (%.0f px)" % ts.x)
		check(tv._frame_rect().size.x <= BoardFit.PLAY_AREA.x + 0.5, "frame fits the screen (cap %d)" % cap)
		tv.free()


func test_snapshot_rejected_on_new_geometry() -> void:
	# A rebuilt level keeps its key; a snapshot from the old geometry must not restore onto it.
	var L := _row8()
	var g := GameSession.start(L)
	g.tap(0)
	var d := g.to_dict()
	check(GameSession.restore(L, d) != null, "same layout restores")
	var moved := level_from_rows(["XXXX", "XXXX"], [], ["circle_1", "circle_2", "circle_3", "circle_4", "circle_4", "circle_3", "circle_2", "circle_1"])
	check_eq(moved.key, L.key, "same key (same tile count)")
	check(GameSession.restore(moved, d) == null, "different positions rejected")


func test_dense_layouts_fill_and_stand() -> void:
	# LayoutGenerator.generate_dense: deterministic, symmetric, every upper tile fully supported,
	# and the board fills the play area both ways.
	for s in 12:
		var cols := 5 + s % 2
		var layers := 1 + s % 5
		var a := LayoutGenerator.generate_dense(SeededRng.new(900 + s), 40 + s * 8, cols, layers)
		var b := LayoutGenerator.generate_dense(SeededRng.new(900 + s), 40 + s * 8, cols, layers)
		check(a == b, "deterministic")
		check_eq(a.size() % 2, 0, "even tile count")
		var geo := BoardGeometry.from_positions(a)
		check(geo.errors.is_empty(), "no overlapping tiles")
		var by_layer := {}
		for p in a:
			if not by_layer.has(p.z):
				by_layer[p.z] = {}
			by_layer[p.z][Vector2i(p.x, p.y)] = true
		for p in a:
			if p.z > 0:
				check(LayoutGenerator._fully_supported(Vector2i(p.x, p.y), by_layer[p.z - 1]), "tile at %s rests on the layer below" % str(p))
		var fr := LayoutGenerator.fill_ratio(a, BoardFit.PLAY_AREA)
		check(fr.x >= 0.88 and fr.y >= 0.88, "fills the screen (%.2f x %.2f)" % [fr.x, fr.y])
