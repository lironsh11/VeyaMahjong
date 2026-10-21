class_name TileView
extends Control
## Visual for one tile slot. Purely presentational: it never receives input itself
## (BoardView hit-tests logically) and never changes rules state.

## Cast shadow of a raised tile (layer > 0) on the tiles below it, in tile widths. It makes the
## layers read at a glance; same-layer neighbours are drawn later and simply cover it.
const DEPTH_SHADOW_OFFSET := Vector2(0.075, 0.065)
const DEPTH_SHADOW_COLOR := Color(0.04, 0.12, 0.08, 0.5)
## Brightness of a tile per layer below the board's top layer.
const LAYER_SHADE_STEP := 0.07
const LAYER_SHADE_MIN := 0.82
## One tile's flip from its back to its face when a board is dealt.
const DEAL_FLIP_S := 0.22

var index: int = -1
var shadow: TextureRect      ## first child, so it sits under this tile's face
var face_rect: TextureRect
var ring: TextureRect        ## "selected" overlay
var hint_ring: TextureRect   ## "hint" overlay
var blocked_ov: TextureRect  ## covered tiles when "highlight free tiles" is on
var match_ov: TextureRect    ## flashes as a matched pair leaves
var pressed_ov: TextureRect  ## tap feedback on a blocked tile
var base_pos: Vector2 = Vector2.ZERO
var gone: bool = false
var _high_contrast: bool = false
var _layer_shade := Color.WHITE
var _tw: Tween
var _hint_tw: Tween
var _back_rect: TextureRect  ## the tile back while a deal flip is pending (BoardView.play_deal)


func setup(p_index: int, tex: Texture2D, sprite_size: Vector2, hi_res: bool) -> void:
	index = p_index
	# Board visuals never mirror. Note: in an RTL locale Godot mirrors a control's position if it
	# is set before the control is attached, so children are always attached first.
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = sprite_size
	pivot_offset = sprite_size * 0.5
	shadow = _layer()
	shadow.texture = tex
	shadow.self_modulate = DEPTH_SHADOW_COLOR
	shadow.visible = false
	face_rect = _layer()
	face_rect.texture = tex
	# Overlays share the face's slot geometry, so they simply cover the whole tile.
	blocked_ov = _layer()
	pressed_ov = _layer()
	match_ov = _layer()
	ring = _layer()
	hint_ring = _layer()
	set_overlay_res(hi_res)


func _layer() -> TextureRect:
	var r := TextureRect.new()
	add_child(r)  # attach BEFORE positioning (RTL locales would otherwise mirror the offset)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if face_rect != null:
		r.visible = false
	return r


func set_overlay_res(hi_res: bool) -> void:
	blocked_ov.texture = ContentService.tile_overlay("blocked", hi_res)
	pressed_ov.texture = ContentService.tile_overlay("pressed", hi_res)
	match_ov.texture = ContentService.tile_overlay("match", hi_res)
	ring.texture = ContentService.tile_overlay("selected", hi_res)
	hint_ring.texture = ContentService.tile_overlay("hint", hi_res)


func set_texture(tex: Texture2D) -> void:
	face_rect.texture = tex
	shadow.texture = tex


func set_depth_shadow(on: bool) -> void:
	shadow.visible = on
	var d := DEPTH_SHADOW_OFFSET * size.x
	shadow.offset_left = d.x
	shadow.offset_top = d.y
	shadow.offset_right = d.x
	shadow.offset_bottom = d.y


func set_dimmed(on: bool, high_contrast: bool) -> void:
	blocked_ov.visible = on
	_high_contrast = high_contrast
	_apply_tint()


func _apply_tint() -> void:
	## The pack's selected/hint rings are thin at phone tile sizes, so the face also takes a
	## light tint (gold = selected, jade = hint). High contrast darkens blocked faces too.
	if ring.visible:
		face_rect.self_modulate = Color(1.0, 0.94, 0.78)
	elif hint_ring.visible:
		face_rect.self_modulate = Color(0.82, 1.0, 0.94)
	elif blocked_ov.visible and _high_contrast:
		face_rect.self_modulate = Color(0.72, 0.74, 0.78) * _layer_shade
	else:
		face_rect.self_modulate = _layer_shade


func set_layer_depth(below_top: int) -> void:
	## Tiles on lower layers are drawn slightly darker, so the top of every stack stands out
	## (it says how high a tile sits, not whether it is free).
	var v := maxf(LAYER_SHADE_MIN, 1.0 - LAYER_SHADE_STEP * below_top)
	_layer_shade = Color(v, v, v * 0.97)
	_apply_tint()


func _kill() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	if _back_rect != null:
		# A deal flip cut short (the tile was tapped, hinted, matched...) ends face-up.
		_back_rect.queue_free()
		_back_rect = null
		scale = Vector2.ONE


func show_back(back_tex: Texture2D) -> void:
	## Covers the tile body with a tile back (a board about to be dealt, BoardView.play_deal).
	_kill()
	_back_rect = TextureRect.new()
	add_child(_back_rect)  # attach BEFORE positioning (RTL locales would otherwise mirror the offset)
	_back_rect.texture = back_tex
	_back_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_back_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_back_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit_back()


func fit_back() -> void:
	if _back_rect != null:
		_back_rect.position = BoardView.BODY.position * size
		_back_rect.size = BoardView.BODY.size * size
		_back_rect.self_modulate = _layer_shade


func flip_to_face(delay: float) -> void:
	## Turns a tile shown by show_back() face-up after `delay` seconds.
	if _back_rect == null:
		return
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_interval(delay)
	_tw.tween_property(self, "scale:x", 0.0, DEAL_FLIP_S * 0.5).set_ease(Tween.EASE_IN)
	_tw.tween_callback(func() -> void:
		if _back_rect != null:
			_back_rect.queue_free()
			_back_rect = null)
	_tw.tween_property(self, "scale:x", 1.0, DEAL_FLIP_S * 0.5).set_ease(Tween.EASE_OUT)


func set_selected(on: bool, animate: bool) -> void:
	ring.visible = on
	_apply_tint()
	# Free tiles are never covered, so drawing them above neighbours is visually safe.
	z_index = 1 if (on or hint_ring.visible) else 0
	_kill()
	var target_pos := base_pos + (Vector2(0, -4) if on else Vector2.ZERO)
	var target_scale := Vector2(1.04, 1.04) if on else Vector2.ONE
	if animate:
		_tw = create_tween().set_parallel(true)
		_tw.tween_property(self, "position", target_pos, 0.09)
		_tw.tween_property(self, "scale", target_scale, 0.09)
	else:
		position = base_pos
		scale = Vector2.ONE


func set_hint(on: bool, animate: bool) -> void:
	hint_ring.visible = on
	_apply_tint()
	z_index = 1 if (on or ring.visible) else 0
	if _hint_tw and _hint_tw.is_valid():
		_hint_tw.kill()
	hint_ring.modulate.a = 1.0
	if on and animate:
		_hint_tw = create_tween().set_loops(4)
		_hint_tw.tween_property(hint_ring, "modulate:a", 0.35, 0.45)
		_hint_tw.tween_property(hint_ring, "modulate:a", 1.0, 0.45)


func play_remove(animate: bool) -> void:
	gone = true
	ring.visible = false
	hint_ring.visible = false
	blocked_ov.visible = false
	_apply_tint()
	match_ov.visible = true
	z_index = 0
	_kill()
	if not animate:
		_tw = create_tween()
		_tw.tween_property(self, "modulate:a", 0.0, 0.09)
		_tw.tween_callback(_hide_removed)
		return
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.06)
	_tw.tween_property(self, "scale", Vector2(0.55, 0.55), 0.16).set_ease(Tween.EASE_IN)
	_tw.parallel().tween_property(self, "modulate:a", 0.0, 0.16)
	_tw.tween_callback(_hide_removed)


func _hide_removed() -> void:
	match_ov.visible = false
	hide()


func lift_off() -> void:
	## Picked into the tray: the tray draws the flight, so this copy vanishes at once.
	gone = true
	_kill()
	ring.visible = false
	hint_ring.visible = false
	blocked_ov.visible = false
	match_ov.visible = false
	_apply_tint()
	z_index = 0
	position = base_pos
	scale = Vector2.ONE
	hide()


func play_restore(animate: bool) -> void:
	gone = false
	_kill()
	match_ov.visible = false
	show()
	position = base_pos
	scale = Vector2.ONE
	if animate:
		modulate.a = 0.0
		_tw = create_tween()
		_tw.tween_property(self, "modulate:a", 1.0, 0.14)
	else:
		modulate.a = 1.0


func play_blocked(animate: bool) -> void:
	_kill()
	position = base_pos
	pressed_ov.visible = true
	_tw = create_tween()
	if animate:
		for dx in [-6.0, 6.0, -4.0, 3.0, 0.0]:
			_tw.tween_property(self, "position:x", base_pos.x + dx, 0.035)
	else:
		# Reduced motion: brief static tint instead of a shake.
		face_rect.modulate = Color(1.0, 0.75, 0.75)
		_tw.tween_interval(0.25)
	_tw.tween_callback(func() -> void:
		face_rect.modulate = Color.WHITE
		pressed_ov.visible = false)
