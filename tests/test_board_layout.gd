extends TestCase
## Layered board geometry (2026-10-22): half-tile offsets, partial overlap and blocking, the
## stacked projection (what is drawn on top is what the rules call on top), touch priority,
## layer draw order, the LayoutTemplates families, and undo/shuffle/hint on layered boards.


static func _geo(positions: Array) -> BoardGeometry:
	return BoardGeometry.from_positions(positions)


static func _state(positions: Array) -> BoardState:
	var geo := _geo(positions)
	var faces := PackedStringArray()
	for k in geo.count:
		faces.append("circle_1")
	return BoardState.create(geo, faces)


static func _removed(st: BoardState) -> PackedByteArray:
	return st.removed


func test_half_offset_tile_covers_two_or_four() -> void:
	# Ground 2x2 block; a tile half a tile off both ways sits on the corner of all four, one off
	# sideways only straddles two, and one a whole tile up covers exactly the tile beneath.
	var ground := [Vector3i(0, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 2, 0), Vector3i(2, 2, 0)]
	var g4 := _geo(ground + [Vector3i(1, 1, 1)])
	check_eq(g4.below[4].size(), 4, "corner tile rests on four")
	for i in 4:
		check(g4.above[i].has(4), "ground tile %d is covered by the corner tile" % i)
	var g2 := _geo(ground + [Vector3i(1, 0, 1)])
	check_eq(g2.below[4].size(), 2, "sideways half offset rests on two")
	check(g2.above[0].has(4) and g2.above[1].has(4), "the two top-row tiles are covered")
	check(g2.above[2].is_empty() and g2.above[3].is_empty(), "the bottom row is not covered (no shared area)")
	var g1 := _geo(ground + [Vector3i(0, 0, 1)])
	check_eq(g1.below[4].size(), 1, "aligned tile rests on one")
	check(g1.is_supported(4), "supported")


func test_partial_overlap_counts_touching_does_not() -> void:
	# Footprints sharing any area (|dx| < 2 and |dy| < 2) cover; touching edges never do.
	var g := _geo([Vector3i(0, 0, 0), Vector3i(1, 1, 1), Vector3i(2, 2, 2), Vector3i(4, 0, 1)])
	check(g.above[0].has(1), "quarter overlap covers")
	check(g.above[1].has(2), "a quarter overlap on the next layer covers")
	check(not g.above[0].has(2), "corner-touching tile two layers up does not cover")
	check(g.above[0].size() == 1, "a tile two units away does not cover")


func test_side_blocking_and_freedom() -> void:
	# Row of three: the middle tile has both sides blocked, the ends are free.
	var st := _state([Vector3i(0, 0, 0), Vector3i(2, 0, 0), Vector3i(4, 0, 0)])
	check(st.is_free(0) and st.is_free(2), "ends free")
	check(not st.is_free(1) and not st.is_covered(1), "middle side-blocked, not covered")
	# A covered tile is never free even with both sides open.
	st = _state([Vector3i(0, 0, 0), Vector3i(0, 0, 1)])
	check(not st.is_free(0) and st.is_covered(0), "covered tile with open sides is not free")
	# Half-row offset neighbours (|dy| = 1) block a side; whole rows above/below (|dy| = 2) do not.
	st = _state([Vector3i(2, 0, 0), Vector3i(0, 1, 0), Vector3i(4, 1, 0)])
	check(not st.is_free(0), "half-row neighbours on both sides block")
	st = _state([Vector3i(2, 0, 0), Vector3i(2, 2, 0), Vector3i(2, -2, 0)])
	check(st.is_free(0) and st.is_free(1) and st.is_free(2), "tiles above/below in a column are not side blockers")


func test_removing_upper_tile_frees_and_exposes_lower() -> void:
	# A half-offset cap over two ground tiles: they are blocked until it leaves, and the screen
	# point that picked the cap then picks the ground tile underneath.
	var st := _state([Vector3i(0, 0, 0), Vector3i(2, 0, 0), Vector3i(1, 0, 1)])
	check(not st.is_free(0) and not st.is_free(1), "both ground tiles covered")
	check(st.is_free(2), "cap free")
	var proj := BoardProjection.centered(st.geo, Vector2(400, 400))
	var p := proj.face_rect(2).get_center()
	check_eq(proj.pick(p, _removed(st)), 2, "the cap is picked, not a tile under it")
	check(st.take(2), "cap taken")
	check(st.is_free(0) and st.is_free(1), "ground tiles freed at once")
	var under := proj.pick(p, _removed(st))
	check(under == 0 or under == 1, "the same point now picks a ground tile (%d)" % under)
	st.put_back(2)
	check(not st.is_free(0) and not st.is_free(1), "put back: covered again")
	check_eq(proj.pick(p, _removed(st)), 2, "and the cap is on top again")


func test_upper_layers_are_lifted_by_the_side_thickness() -> void:
	# Layer z is drawn LIFT up-left per layer, LIFT == SIDE: a tile resting exactly on another
	# shows the lower tile's sides below and right of its own sides.
	var proj := BoardProjection.make(_geo([Vector3i(0, 0, 0), Vector3i(0, 0, 1)]), 100.0, Vector2(50, 50))
	var lo := proj.solid_rect(0)
	var hi := proj.solid_rect(1)
	check(hi.position.is_equal_approx(lo.position - BoardFit.LIFT * 100.0), "lifted one side thickness")
	check(BoardFit.LIFT == BoardFit.SIDE, "lift equals side thickness")
	check(hi.end.is_equal_approx(lo.end - BoardFit.SIDE * 100.0), "the lower tile's sides stay visible")
	check(proj.face_rect(1).encloses(Rect2(proj.face_rect(0).position, proj.face_rect(0).size - BoardFit.SIDE * 100.0)), "the covered face is hidden")


func _pyramid_board() -> Array:
	return LayoutTemplates.structure("pyramid", 6, 9, 4, SeededRng.new(3)).positions()


func test_draw_order_is_layer_by_layer_and_sides_are_covered() -> void:
	for positions in [_pyramid_board(), LayoutTemplates.structure("turtle", 6, 9, 5, SeededRng.new(1)).positions(), LayoutTemplates.structure("brick", 5, 7, 4, SeededRng.new(2)).positions()]:
		var geo := _geo(positions)
		var proj := BoardProjection.make(geo, 90.0, Vector2.ZERO)
		var ok_layers := true
		var ok_sides := true
		for i in geo.count:
			for j in geo.count:
				if geo.gz[i] < geo.gz[j] and proj.rank[i] > proj.rank[j]:
					ok_layers = false
				# A same-layer right/lower neighbour must be drawn over this tile's side.
				if i != j and geo.gz[i] == geo.gz[j]:
					var dx := geo.gx[j] - geo.gx[i]
					var dy := geo.gy[j] - geo.gy[i]
					if (dx == 2 and absi(dy) < 2) or (dy == 2 and absi(dx) < 2):
						if proj.rank[j] < proj.rank[i]:
							ok_sides = false
		check(ok_layers, "every lower layer is drawn before every higher layer")
		check(ok_sides, "right/lower neighbours are drawn over a tile's sides")


func test_no_tile_drawn_over_a_tile_physically_in_front() -> void:
	# Wherever two drawn tiles overlap on screen, the one drawn later is physically in front:
	# it covers the other, or it is higher and the other lies behind it (up/left), or, on one
	# layer, it is the right/lower neighbour hiding the other's side. Checked on shipped boards.
	for id in [4, 30, 75, 150, 200, 300]:
		var geo := ContentService.get_level(id).build_state().geo
		var proj := BoardProjection.make(geo, 90.0, Vector2.ZERO)
		var bad := 0
		for i in geo.count:
			var ri := proj.solid_rect(i)
			for j in geo.count:
				if proj.rank[j] <= proj.rank[i] or not ri.intersects(proj.solid_rect(j)):
					continue
				# j is drawn over part of i.
				var covers := geo.above[i].has(j)
				var behind := geo.gx[i] < geo.gx[j] or geo.gy[i] < geo.gy[j]
				var front_ok := covers or (geo.gz[j] > geo.gz[i] and behind) or (geo.gz[j] == geo.gz[i] and geo.gx[j] + geo.gy[j] >= geo.gx[i] + geo.gy[i])
				if not front_ok:
					bad += 1
		check_eq(bad, 0, "level %d: no tile drawn over one in front of it" % id)


func test_higher_tile_never_reaches_onto_a_tile_in_front() -> void:
	# A raised tile behind a free lower tile (one row up) never paints over it; a raised tile in
	# front of a free lower tile hides at most a lift's strip of its face, never the symbol, and
	# the free tile is still picked on its visible face.
	var st := _state([Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 2, 0)])
	var proj := BoardProjection.centered(st.geo, Vector2(500, 600))
	check(st.is_free(3), "the lower tile in front is free")
	check(not proj.solid_rect(2).intersects(proj.face_rect(3)), "the raised tile behind it does not reach its face")
	check_eq(proj.pick(proj.face_rect(3).position + Vector2(4, 4), _removed(st)), 3, "its top-left corner picks it")
	st = _state([Vector3i(0, 0, 0), Vector3i(-1, 2, 0), Vector3i(1, 2, 0), Vector3i(0, 2, 1)])
	proj = BoardProjection.centered(st.geo, Vector2(500, 600))
	check(st.is_free(0), "the tile behind is free")
	var face := proj.face_rect(0)
	var hidden := face.end.y - proj.solid_rect(3).position.y
	check(hidden <= (BoardFit.LIFT.y - BoardFit.GAP.y) * proj.tile_w + 0.5, "hidden strip %.1f px is at most one lift" % hidden)
	check(hidden < face.size.y * 0.15, "the face stays at least 85% visible")
	check_eq(proj.pick(face.get_center(), _removed(st)), 0, "its face centre picks it")


func test_touch_picks_the_topmost_tile_everywhere() -> void:
	# On a real layered board: every touch point inside any tile's solid picks the last-drawn tile
	# containing it; the centre of a covered tile's face never picks the covered tile when a higher
	# tile is drawn there; shadows/padding (outside every solid) pick nothing without the margin.
	var L := ContentService.get_level(120)
	var state := L.build_state()
	var proj := BoardProjection.centered(state.geo, BoardFit.PLAY_AREA)
	var removed := state.removed
	var mismatches := 0
	var through := 0
	for i in state.geo.count:
		var r := proj.solid_rect(i)
		for f in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.9), Vector2(0.1, 0.9), Vector2(0.9, 0.1)]:
			var p: Vector2 = r.position + r.size * f
			var expect := -1
			for k in range(proj.order.size() - 1, -1, -1):
				if proj.solid_rect(proj.order[k]).has_point(p):
					expect = proj.order[k]
					break
			if proj.pick(p, removed) != expect:
				mismatches += 1
		if state.is_covered(i):
			var c := proj.face_rect(i).get_center()
			var got := proj.pick(c, removed)
			if got == i and not state.geo.above[i].is_empty():
				for j in state.geo.above[i]:
					if proj.solid_rect(j).has_point(c):
						through += 1
	check_eq(mismatches, 0, "pick == topmost drawn solid")
	check_eq(through, 0, "never picks a covered tile through a tile drawn over it")
	var outside := proj.content_rect().position - Vector2(5, 5)
	check_eq(proj.pick(outside, removed), -1, "a touch off the board picks nothing")


func test_board_view_taps_select_the_topmost_tile() -> void:
	# End to end through the node: a mouse press on the board emits the tile drawn on top.
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var board := BoardView.new()
	root.add_child(board)
	board.size = Vector2(540, 900)
	var st := _state([Vector3i(0, 0, 0), Vector3i(2, 0, 0), Vector3i(1, 0, 1)])
	board.setup(st, "classic")
	var got: Array[int] = []
	board.tile_tapped.connect(func(i: int) -> void: got.append(i))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = board.face_rect(2).get_center()
	board._gui_input(ev)
	check(got.size() == 1 and got[0] == 2, "tap on the cap selects the cap (got %s)" % [got])
	# The covered ground tile's visible strip (left of the cap) selects the ground tile, which the
	# rules then refuse (blocked) - the view never redirects a tap to another tile.
	ev.position = board.face_rect(0).position + Vector2(3, board.face_rect(0).size.y * 0.5)
	board._gui_input(ev)
	check(got.size() == 2 and got[1] == 0, "tap on the visible part of the covered tile picks it (got %s)" % [got])
	check(not st.is_free(0), "and it is not selectable")
	board.queue_free()


func test_board_stays_centred_and_still_when_tiles_leave() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var board := BoardView.new()
	root.add_child(board)
	board.size = BoardFit.PLAY_AREA
	var L := ContentService.get_level(60)
	var st := L.build_state()
	board.setup(st, "classic")
	var c := board.proj.content_rect()
	check(c.get_center().distance_to(board.size * 0.5) < 1.0, "board centred in its area")
	check(c.size.x <= board.size.x + 0.5 and c.size.y <= board.size.y + 0.5, "nothing clipped: sides and shadows inside")
	var before := board.tiles[0].base_pos
	for i in st.free_tiles():
		st.take(i)
		board.lift(i)
	board._relayout()
	check(board.tiles[0].base_pos.is_equal_approx(before), "tiles do not move when others leave")
	check(board.proj.content_rect().is_equal_approx(c), "bounds come from the layout, not the remaining tiles")
	board.queue_free()


func test_debug_overlay_is_off_unless_asked() -> void:
	var board := BoardView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(board)
	board.size = Vector2(400, 400)
	board.setup(_state([Vector3i(0, 0, 0), Vector3i(2, 0, 0)]), "classic")
	check(board._debug == null, "no overlay by default")
	BoardView.debug_overlay = true
	board.setup(_state([Vector3i(0, 0, 0), Vector3i(2, 0, 0)]), "classic")
	check(board._debug != null, "overlay in a debug build when asked")
	BoardView.debug_overlay = false
	board.queue_free()


# --- templates ------------------------------------------------------------------------------

func _check_structure(positions: Array, cols: int, label: String) -> void:
	var geo := _geo(positions)
	check(geo.errors.is_empty(), "%s: no same-layer overlap %s" % [label, geo.errors])
	var at := {}
	for p in positions:
		at[p] = true
	var asym := 0
	for i in geo.count:
		if geo.gz[i] > 0:
			# Meaningful support: at least half the tile rests on the layer right below.
			var area := 0
			for b in geo.below[i]:
				if geo.gz[b] == geo.gz[i] - 1:
					area += (2 - absi(geo.gx[b] - geo.gx[i])) * (2 - absi(geo.gy[b] - geo.gy[i]))
			check(area >= 2, "%s: tile %d at layer %d rests on the layer below (%d/4)" % [label, i, geo.gz[i], area])
		if not at.has(Vector3i(2 * cols - 2 - geo.gx[i], geo.gy[i], geo.gz[i])):
			asym += 1
	check(asym <= 1, "%s: mirror-symmetric (%d unmatched)" % [label, asym])


func test_every_family_builds_layered_symmetric_supported_boards() -> void:
	for fam in LayoutTemplates.FAMILIES:
		for cols in [5, 6]:
			var rows := BoardFit.rows_to_fill(cols)
			var b := LayoutTemplates.structure(fam, cols, rows, 4, SeededRng.new(5))
			var pos := b.positions()
			check(LayoutTemplates.layer_count(pos) >= 3, "%s/%d: at least 3 layers (%d)" % [fam, cols, LayoutTemplates.layer_count(pos)])
			_check_structure(pos, cols, "%s/%d" % [fam, cols])
			var fr := LayoutGenerator.fill_ratio(pos, BoardFit.PLAY_AREA)
			check(fr.x >= 0.88 and fr.y >= 0.88, "%s/%d fills the screen (%.2f x %.2f)" % [fam, cols, fr.x, fr.y])
			check(BoardFit.fit_tile_width(_geo(pos), BoardFit.PLAY_AREA) >= 84.0, "%s/%d big tiles" % [fam, cols])


func test_staggered_families_use_real_half_tile_offsets() -> void:
	# pyramid: every layer-1 tile on the corner of four; brick/ridge: layer 1 straddles two side by
	# side; turtle: flippers half a row off the body; bridge: decks rest half on a pier.
	var py := _geo(LayoutTemplates.structure("pyramid", 6, 9, 3, SeededRng.new(1)).positions())
	for i in py.count:
		if py.gz[i] == 1:
			check(py.gx[i] % 2 == 1 and py.gy[i] % 2 == 1 and py.below[i].size() == 4, "pyramid layer-1 tile %d sits on four" % i)
	for fam in ["brick", "ridge"]:
		var g := _geo(LayoutTemplates.structure(fam, 6, 9, 2, SeededRng.new(1)).positions())
		for i in g.count:
			if g.gz[i] == 1:
				check(g.gx[i] % 2 == 1 and g.gy[i] % 2 == 0 and g.below[i].size() == 2, "%s layer-1 tile %d straddles two" % [fam, i])
	var tu := LayoutTemplates.structure("turtle", 6, 9, 4, SeededRng.new(1))
	var flippers := 0
	for p in tu.positions():
		if p.z == 0 and (p.x == 0 or p.x == 10):
			flippers += 1
			check(p.y % 2 == 1, "flipper at %s is half a row off" % str(p))
	check(flippers >= 4, "turtle has flippers")
	var br := _geo(LayoutTemplates.structure("bridge", 6, 9, 2, SeededRng.new(1)).positions())
	var half := 0
	for i in br.count:
		if br.gz[i] == 1 and br.below[i].size() >= 1:
			var area := 0
			for b in br.below[i]:
				area += (2 - absi(br.gx[b] - br.gx[i])) * (2 - absi(br.gy[b] - br.gy[i]))
			if area == 2:
				half += 1
	check(half >= 4, "bridge decks rest half on piers (%d)" % half)


func test_the_32_tile_three_layer_example() -> void:
	# 6x4 ground, a 3x2 layer centred half a tile across, two tiles centred over that: 32 tiles,
	# solvable, with every middle-layer tile under the top two.
	var b := LayoutTemplates.Build.new(6, 4)
	b.rect(0, 0, 0, 6, 4)
	for x in [3, 5]:
		for y in [2, 4]:
			check(b.put_pair(Vector2i(x, y), 1), "layer 1 tile at %d,%d" % [x, y])
	check(b.put_pair(Vector2i(4, 3), 2), "layer 2 tile")
	var pos := b.positions()
	check_eq(pos.size(), 32, "24 + 6 + 2 tiles")
	check_eq(LayoutTemplates.layer_count(pos), 3, "three layers")
	_check_structure(pos, 6, "example")
	var L := BoardGenerator.new().generate_level(pos, "test|example32")
	check(L.is_valid(), "faces assigned")
	var rep := BoardValidator.validate(L, 200000)
	check(rep.ok and rep.witness_legal, "solvable: %s" % [rep.errors])
	var st := L.build_state()
	for i in st.size():
		if st.geo.gz[i] == 2:
			check(st.is_free(i), "top tile free")
		elif st.geo.gz[i] == 1:
			check(st.is_covered(i), "middle-layer tile %d covered by the top" % i)


func test_templates_are_deterministic_and_hit_the_count() -> void:
	var caps := {}
	var made := 0
	for s in 40:
		var cols := 5 + s % 2
		var target := 2 * (14 + s * 3 % 50)
		var a := LayoutTemplates.pick(SeededRng.new(700 + s), target, cols, 2, 5, caps)
		var b := LayoutTemplates.pick(SeededRng.new(700 + s), target, cols, 2, 5, caps)
		check(a == b, "seed %d deterministic" % s)
		if a.is_empty():
			continue
		made += 1
		check_eq(a.positions.size(), target, "seed %d hits %d tiles" % [s, target])
		check(LayoutTemplates.layer_count(a.positions) >= 2, "seed %d layered" % s)
		_check_structure(a.positions, cols, "seed %d %s" % [s, a.family])
	check(made >= 30, "most sizes have a template (%d/40)" % made)


func test_carving_never_removes_a_supporting_tile_or_an_edge() -> void:
	var full := LayoutTemplates.structure("pyramid", 6, 9, 5, SeededRng.new(9)).positions()
	var g0 := _geo(full)
	for mode in LayoutTemplates.MODES:
		var pos := LayoutTemplates.carve(full, 90, 6, mode, SeededRng.new(4))
		check_eq(pos.size(), 90, "%s carve hits the count" % mode)
		var g := _geo(pos)
		check(g.min_gx == g0.min_gx and g.max_gx == g0.max_gx and g.min_gy == g0.min_gy and g.max_gy == g0.max_gy, "%s keeps the board's extent" % mode)
		for i in g.count:
			check(g.is_supported(i), "%s: tile %d still supported" % [mode, i])


# --- play on layered boards -------------------------------------------------------------------

func test_undo_restores_positions_and_blocking() -> void:
	var L := ContentService.get_level(150)
	var s := GameSession.start(L)
	var cover0 := s.state.cover_cnt.duplicate()
	var left0 := s.state.left_cnt.duplicate()
	var right0 := s.state.right_cnt.duplicate()
	var free0 := s.state.free_tiles()
	var picks := 0
	for k in 3:
		var free := s.state.free_tiles()
		if s.tap(free[0]).r != GameSession.Tap.IGNORED:
			picks += 1
	for k in picks:
		s.undo()
	check(s.state.cover_cnt == cover0 and s.state.left_cnt == left0 and s.state.right_cnt == right0, "blocking counters restored")
	check(s.state.free_tiles() == free0, "same free tiles")
	check(s.state.remaining == L.tiles.size(), "every tile back")
	check(GameSession.layout_hash(s.level) == GameSession.layout_hash(L), "positions untouched")


func test_shuffle_never_moves_tiles_or_layers() -> void:
	var L := ContentService.get_level(200)
	var s := GameSession.start(L)
	for k in 6:
		var free := s.state.free_tiles()
		s.tap(free[k % free.size()])
		if s.failed:
			s.undo()
			break
	var removed := s.state.removed_indices()
	var geo := s.state.geo
	var res := s.shuffle()
	check(res.ok, "shuffle found an arrangement")
	check(s.state.geo == geo, "same geometry object")
	check(s.state.removed_indices() == removed, "same tiles on the board")
	for i in geo.count:
		check(L.tiles[i].gx == geo.gx[i] and L.tiles[i].gy == geo.gy[i] and L.tiles[i].z == geo.gz[i], "tile %d keeps its place and layer" % i)


func test_hint_only_suggests_free_tiles() -> void:
	for id in [10, 90, 260]:
		var st := ContentService.get_level(id).build_state()
		var tray := PackedInt32Array()
		for step in 12:
			var g := BoardController.best_guess(st, tray)
			check(not g.is_empty(), "level %d: a hint exists" % id)
			for i in g:
				check(st.is_free(i), "level %d: hinted tile %d is free" % [id, i])
			var i0 := g[0]
			st.take(i0)
			var slot := TrayRules.partner_slot(tray, st.keys, i0)
			if slot >= 0:
				tray.remove_at(slot)
			else:
				tray.append(i0)
			if tray.size() >= TrayRules.CAPACITY - 1 or st.remaining == 0:
				break
		var sol := TraySolver.new(60000).solve(ContentService.get_level(id).build_state())
		if sol.result == BoardSolver.Result.SOLVED:
			check(ContentService.get_level(id).build_state().is_free(sol.solution[0]), "level %d: the proven first pick is free" % id)
