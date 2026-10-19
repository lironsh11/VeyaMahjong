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
		var body_center := board.get_global_transform() * board.body_rect(i).get_center()
		check(ring_center.distance_to(body_center) < 3.0, "tile %d frame centred on body (off by %.1f px)" % [i, ring_center.distance_to(body_center)])
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
