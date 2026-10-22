extends TestCase
## Regression: in an RTL locale (Hebrew) the selection/hint frames must sit exactly on their
## tile. A control positioned before being attached gets mirrored by Godot in RTL, which once
## drew the selection frame one tile to the left of the tapped tile.

func _board_in_rtl_parent() -> Array:
	LocalizationService.set_locale("he")
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var parent := Control.new()
	parent.layout_direction = Control.LAYOUT_DIRECTION_RTL
	parent.size = Vector2(540, 900)
	root.add_child(parent)
	var board := BoardView.new()
	parent.add_child(board)
	board.size = Vector2(540, 900)
	var L := level_from_rows(["XXXXXX", ".XXXX.", "XXXXXX"], [[".XX..."]], [])
	board.setup(L.build_state(), "classic")
	return [parent, board, L]


func test_frames_align_with_tiles_in_rtl() -> void:
	var made := _board_in_rtl_parent()
	var parent: Control = made[0]
	var board: BoardView = made[1]
	check(board.tiles.size() > 0, "board built")
	for i in board.tiles.size():
		var tv := board.tiles[i]
		var tile_rect := tv.get_global_rect()
		var ring_center := tv.ring.get_global_rect().get_center()
		var hint_center := tv.hint_ring.get_global_rect().get_center()
		check(tile_rect.has_point(ring_center), "tile %d selection frame inside its tile" % i)
		check(tile_rect.has_point(hint_center), "tile %d hint frame inside its tile" % i)
		check(Rect2(Vector2.ZERO, board.size).encloses(board.body_rect(i)), "tile %d drawn inside the board" % i)
		var sprite_center := board.get_global_transform() * board.proj.sprite_rect(i).get_center()
		check(ring_center.distance_to(sprite_center) < 1.0, "tile %d frame centred on its tile (off by %.1f px)" % [i, ring_center.distance_to(sprite_center)])
		check(board.body_rect(i).has_point(board.get_global_transform().affine_inverse() * ring_center), "tile %d frame centre on its body" % i)
	parent.queue_free()
	LocalizationService.set_locale("en")


func test_board_is_not_mirrored_in_rtl() -> void:
	# Mahjong layouts never mirror: the leftmost logical tile stays leftmost on screen.
	var made := _board_in_rtl_parent()
	var parent: Control = made[0]
	var board: BoardView = made[1]
	var geo := board.state.geo
	var leftmost := 0
	var rightmost := 0
	for i in geo.count:
		if geo.gz[i] == 0 and geo.gy[i] == 0:
			if geo.gx[i] < geo.gx[leftmost] or geo.gy[leftmost] != 0:
				leftmost = i
			if geo.gx[i] > geo.gx[rightmost] or geo.gy[rightmost] != 0:
				rightmost = i
	check(board.tiles[leftmost].get_global_rect().position.x < board.tiles[rightmost].get_global_rect().position.x, "board keeps LTR order in Hebrew")
	parent.queue_free()
	LocalizationService.set_locale("en")


func _badge_x_offset(rtl: bool) -> float:
	## Badge centre minus button centre, measured in a parent with the given direction.
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var parent := HBoxContainer.new()
	parent.layout_direction = Control.LAYOUT_DIRECTION_RTL if rtl else Control.LAYOUT_DIRECTION_LTR
	parent.size = Vector2(300, 120)
	root.add_child(parent)
	var b := UIKit.tool_button("hint", "Hint", true, 38)
	b.custom_minimum_size = Vector2(90, 80)
	parent.add_child(b)
	UIKit.set_tool_badge(b, "3", "BadgeGold")
	var badge: Control = b.get_node("Badge")
	var off := badge.get_global_rect().get_center().x - b.get_global_rect().get_center().x
	parent.queue_free()
	return off


func test_booster_badge_mirrors_in_rtl() -> void:
	check(_badge_x_offset(false) > 0.0, "badge on the right corner in LTR")
	check(_badge_x_offset(true) < 0.0, "badge on the left corner in RTL (Hebrew)")


func test_row_overlap_tap_picks_the_front_tile() -> void:
	# The next row's face covers this row's bottom side (the thickness band): a tap in that band
	# must pick the lower (front, drawn later) tile.
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var board := BoardView.new()
	root.add_child(board)
	board.size = Vector2(540, 900)
	var L := level_from_rows(["X", "X"], [], ["circle_1", "circle_1"])
	board.setup(L.build_state(), "classic")
	var upper := board.body_rect(0)
	var lower := board.body_rect(1)
	check(lower.position.y < upper.end.y, "rows overlap")
	var p := Vector2(upper.get_center().x, (lower.position.y + upper.end.y) * 0.5)
	check_eq(board.pick(p), 1, "the front (lower) tile is picked in the overlap band")
	check_eq(board.pick(upper.get_center()), 0, "the upper tile is still pickable above the band")
	board.queue_free()


func _board_for(positions: Array) -> BoardView:
	var geo := BoardGeometry.from_positions(positions)
	var faces := PackedStringArray()
	for k in geo.count:
		faces.append("circle_1")
	var board := BoardView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(board)
	board.size = Vector2(540, 900)
	board.setup(BoardState.create(geo, faces), "classic")
	return board


func test_deal_flip_shows_the_back_and_never_sticks() -> void:
	var prev_rm: Variant = GameState.setting("reduced_motion")
	GameState.data.settings["reduced_motion"] = false
	var board := _board_for([Vector3i(0, 0, 0), Vector3i(2, 0, 0), Vector3i(4, 0, 0), Vector3i(6, 0, 0)])
	board.play_deal(ContentService.tile_back_texture("jade_bamboo_valley"))
	for tv in board.tiles:
		check(tv._back_rect != null, "tile %d starts on its back" % tv.index)
	# A tile touched mid-deal (selected, matched, hinted...) shows its face at once.
	board.tiles[0].set_selected(true, false)
	check(board.tiles[0]._back_rect == null, "a selected tile drops its back")
	check_eq(board.tiles[0].scale, Vector2.ONE)
	board.queue_free()
	# Held under the level-start dialog: backs show, nothing flips until released.
	board = _board_for([Vector3i(0, 0, 0), Vector3i(2, 0, 0)])
	board.play_deal(ContentService.tile_back_texture("jade_bamboo_valley"), true)
	check(board.tiles[1]._back_rect != null and board.tiles[1]._tw == null, "held deal waits face-down")
	board.release_deal()
	check(board.tiles[1]._tw != null and board.tiles[1]._tw.is_valid(), "released deal flips")
	board.queue_free()
	GameState.data.settings["reduced_motion"] = true
	board = _board_for([Vector3i(0, 0, 0), Vector3i(2, 0, 0)])
	board.play_deal(ContentService.tile_back_texture("jade_bamboo_valley"))
	check(board.tiles[0]._back_rect == null, "reduced motion: no deal flip")
	board.queue_free()
	GameState.data.settings["reduced_motion"] = prev_rm


func test_draw_order_keeps_covered_tiles_behind() -> void:
	# Every tile is drawn after every tile it covers, on real shipped boards.
	for id in [1, 13, 40, 150, 151, 300]:
		var geo := ContentService.get_level(id).build_state().geo
		var order := geo.draw_order()
		var at := PackedInt32Array()
		at.resize(geo.count)
		for k in order.size():
			at[order[k]] = k
		var ok := true
		for i in geo.count:
			for j in geo.below[i]:
				if at[i] < at[j]:
					ok = false
		check(ok, "level %d: covering tiles drawn on top" % id)
