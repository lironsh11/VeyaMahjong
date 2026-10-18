class_name BoardView
extends Control
## Renders a BoardState and turns touches into tile indices.
##
## Hit-testing is logical, not per-sprite: tiles are tested from the topmost drawn tile
## downwards against each tile's BODY rectangle (sprite minus transparent padding and drop
## shadow), so the selected tile is always the visually topmost one under the finger. If a
## touch lands in a gap, the nearest tile whose slightly enlarged body contains the point is
## used (forgiving hit areas for large fingers).
##
## The board never mirrors in RTL: Mahjong layouts, symbols and coordinates are
## direction-neutral, so this control forces LTR.

signal tile_tapped(index: int)

## Fractions of the tile slot (LiShi v2 atlas cells are 96x123 / 192x246: tile body plus soft
## shadow; tools/import_lishi_v2.gd fits every face onto this body).
const BODY := Rect2(0.04, 0.025, 0.915, 0.905)
const STEP_X := BoardFit.STEP_X
const STEP_Y := BoardFit.STEP_Y
const LAYER_DX := BoardFit.LAYER_DX
const LAYER_DY := BoardFit.LAYER_DY
const ASPECT := BoardFit.ASPECT
const MAX_TILE_W := BoardFit.MAX_TILE_W
const LARGE_TILE_MIN_W := 66.0
const TAP_SLOP := 14.0
const HIT_GROW := 0.10

var state: BoardState
var theme_id: String = "classic"
var large_tiles: bool = false
var highlight_free: bool = true
var high_contrast: bool = false
var tiles: Array[TileView] = []
var tile_w: float = 64.0
var _order: PackedInt32Array
var _layer: Control
var _fx: Control
var _pan: Vector2 = Vector2.ZERO
var _content_size: Vector2 = Vector2.ZERO
var _can_pan: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragged: bool = false
var _hi_res: bool = false
var input_enabled: bool = true


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_relayout)


func setup(p_state: BoardState, p_theme: String) -> void:
	state = p_state
	theme_id = p_theme
	large_tiles = bool(GameState.setting("large_tiles"))
	highlight_free = bool(GameState.setting("highlight_free"))
	high_contrast = bool(GameState.setting("high_contrast"))
	for c in get_children():
		c.queue_free()
	tiles.clear()
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(_layer)
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(_fx)
	_order = state.geo.draw_order()
	tiles.resize(state.size())
	for i in _order:
		var tv := TileView.new()
		_layer.add_child(tv)
		tiles[i] = tv
	_pan = Vector2.ZERO
	_relayout()


func _anim() -> bool:
	return not AccessibilityService.reduced_motion()


func _physical_scale() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.0
	var win := DisplayServer.window_get_size()
	var vis := vp.get_visible_rect().size
	return float(win.x) / maxf(1.0, vis.x)


func _relayout() -> void:
	if state == null or tiles.is_empty() or size.x <= 0.0:
		return
	var geo := state.geo
	var units := BoardFit.board_units(geo)
	var w_units := units.x
	var h_units := units.y
	tile_w = BoardFit.fit_tile_width(geo, size)
	_can_pan = false
	if large_tiles and tile_w < LARGE_TILE_MIN_W:
		tile_w = LARGE_TILE_MIN_W
		_can_pan = true
	var tile_h := tile_w * ASPECT
	_content_size = Vector2(w_units * tile_w, h_units * tile_w)
	_clamp_pan()
	var origin := (size - _content_size) * 0.5 + _pan
	# Texture resolution: 192px atlas only when tiles are drawn large on the physical screen
	# (the 96px one would be upscaled more than ~1.15x).
	var phys_w := tile_w * _physical_scale()
	var want_hi := phys_w > 112.0 and not AccessibilityService.low_profile
	var retexture := want_hi != _hi_res or tiles[0] == null or tiles[0].face_rect == null
	_hi_res = want_hi
	var sprite := Vector2(tile_w, tile_h)
	for i in tiles.size():
		var tv := tiles[i]
		var pos := tile_pos(i, origin, sprite)
		if tv.face_rect == null:
			tv.setup(i, _tex(i), sprite, _hi_res)
		else:
			tv.size = sprite
			tv.pivot_offset = sprite * 0.5
			if retexture:
				tv.set_texture(_tex(i))
				tv.set_overlay_res(_hi_res)
		tv.base_pos = pos
		tv.position = pos
		tv.visible = not state.is_removed(i)
		tv.gone = state.is_removed(i)
		tv.modulate.a = 1.0
		tv.scale = Vector2.ONE
	refresh_free()


func tile_pos(i: int, origin: Vector2, sprite: Vector2) -> Vector2:
	var geo := state.geo
	var x := (geo.gx[i] - geo.min_gx) / 2.0 * STEP_X + (geo.max_z - geo.gz[i]) * absf(LAYER_DX)
	var y := ((geo.gy[i] - geo.min_gy) / 2.0 * STEP_Y + (geo.max_z - geo.gz[i]) * absf(LAYER_DY)) * ASPECT
	return origin + Vector2(x * sprite.x, y * sprite.x)


func _tex(i: int) -> Texture2D:
	return ContentService.tile_texture(theme_id, state.faces[i], _hi_res)


func body_rect(i: int, grow: float = 0.0) -> Rect2:
	var tv := tiles[i]
	var sprite := tv.size
	var r := Rect2(tv.base_pos + BODY.position * sprite, BODY.size * sprite)
	return r.grow(r.size.x * grow)


func pick(point: Vector2) -> int:
	## Topmost tile whose body contains the point; else nearest within a forgiving margin.
	for k in range(_order.size() - 1, -1, -1):
		var i := _order[k]
		if state.is_removed(i):
			continue
		if body_rect(i).has_point(point):
			return i
	var best := -1
	var best_d := INF
	for k in range(_order.size() - 1, -1, -1):
		var i := _order[k]
		if state.is_removed(i):
			continue
		var r := body_rect(i, HIT_GROW)
		if r.has_point(point):
			var d := r.get_center().distance_squared_to(point)
			if d < best_d - 0.01:
				best_d = d
				best = i
	return best


func _clamp_pan() -> void:
	if not _can_pan:
		_pan = Vector2.ZERO
		return
	var slack := ((_content_size - size) * 0.5).max(Vector2.ZERO) + Vector2(12, 12)
	_pan = _pan.clamp(-slack, slack)


func _gui_input(event: InputEvent) -> void:
	if not input_enabled or state == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragged = false
			_press_pos = event.position
			if not _can_pan:
				_emit_tap(event.position)
		else:
			if _pressing and _can_pan and not _dragged:
				_emit_tap(event.position)
			_pressing = false
		accept_event()
	elif event is InputEventMouseMotion and _pressing and _can_pan:
		if _dragged or event.position.distance_to(_press_pos) > TAP_SLOP:
			_dragged = true
			_pan += event.relative
			_relayout()
		accept_event()


func _emit_tap(p: Vector2) -> void:
	var i := pick(p)
	if i >= 0:
		tile_tapped.emit(i)


# --- visual state API used by the gameplay controller --------------------------------

func refresh_free() -> void:
	for i in tiles.size():
		var tv := tiles[i]
		if tv == null or tv.face_rect == null:
			continue
		tv.set_dimmed(highlight_free and not state.is_removed(i) and not state.is_free(i), high_contrast)


func set_selected(i: int, on: bool) -> void:
	if i >= 0 and i < tiles.size():
		tiles[i].set_selected(on, _anim())


func show_hint(a: int, b: int) -> void:
	clear_hint()
	tiles[a].set_hint(true, _anim())
	tiles[b].set_hint(true, _anim())


func clear_hint() -> void:
	for tv in tiles:
		if tv.hint_ring and tv.hint_ring.visible:
			tv.set_hint(false, false)


func play_match(a: int, b: int) -> void:
	clear_hint()
	tiles[a].play_remove(_anim())
	tiles[b].play_remove(_anim())
	if AccessibilityService.effects_on():
		_spawn_fx("match_sparkle", body_rect(a).get_center(), tile_w * 1.3)
		_spawn_fx("match_sparkle", body_rect(b).get_center(), tile_w * 1.3)
	refresh_free()


func play_restore(a: int, b: int) -> void:
	tiles[a].play_restore(_anim())
	tiles[b].play_restore(_anim())
	refresh_free()


func play_blocked(i: int) -> void:
	tiles[i].play_blocked(_anim())


func play_reshuffle() -> void:
	clear_hint()
	for i in tiles.size():
		if state.is_removed(i):
			continue
		var tv := tiles[i]
		tv.set_selected(false, false)
		if _anim():
			var tw := tv.create_tween()
			tw.tween_property(tv, "modulate:a", 0.15, 0.12)
			tw.tween_callback(func() -> void: tv.set_texture(_tex(i)))
			tw.tween_property(tv, "modulate:a", 1.0, 0.16)
		else:
			tv.set_texture(_tex(i))
	refresh_free()


func retheme(p_theme: String) -> void:
	theme_id = p_theme
	for i in tiles.size():
		tiles[i].set_texture(_tex(i))


func play_win_fx() -> void:
	if not AccessibilityService.effects_on():
		return
	var rng := RandomNumberGenerator.new()
	for k in 6:
		var p := Vector2(rng.randf_range(0.2, 0.8) * size.x, rng.randf_range(0.2, 0.7) * size.y)
		get_tree().create_timer(k * 0.1).timeout.connect(func() -> void:
			if is_inside_tree():
				_spawn_fx("gold_twinkle", p, 120.0))


func _spawn_fx(effect: String, center: Vector2, px: float) -> void:
	var frames := ContentService.effect_frames(effect)
	if frames.is_empty():
		return
	var tr := TextureRect.new()
	_fx.add_child(tr)  # attach before positioning (see TileView note on RTL)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = Vector2(px, px)
	tr.position = center - tr.size * 0.5
	tr.texture = frames[0]
	var tw := tr.create_tween()
	tw.tween_method(func(f: float) -> void:
		tr.texture = frames[clampi(int(f), 0, frames.size() - 1)], 0.0, float(frames.size()), frames.size() / 20.0)
	tw.tween_callback(tr.queue_free)
