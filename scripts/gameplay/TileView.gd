class_name TileView
extends Control
## Visual for one tile slot. Purely presentational: it never receives input itself
## (BoardView hit-tests logically) and never changes rules state.

var index: int = -1
var face_rect: TextureRect
var ring: Panel
var hint_ring: Panel
var base_pos: Vector2 = Vector2.ZERO
var gone: bool = false
var _tw: Tween
var _hint_tw: Tween


func setup(p_index: int, tex: Texture2D, sprite_size: Vector2, body: Rect2) -> void:
	index = p_index
	# Board visuals never mirror. Note: in an RTL locale Godot mirrors a control's position if it
	# is set before the control is attached, so children are always attached first.
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = sprite_size
	pivot_offset = sprite_size * 0.5
	face_rect = TextureRect.new()
	add_child(face_rect)
	face_rect.texture = tex
	face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_rect.stretch_mode = TextureRect.STRETCH_SCALE
	face_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var radius := int(body.size.x * 0.13)
	ring = _make_ring(body, UITheme.GOLD.darkened(0.05), Color(1.0, 0.86, 0.35, 0.22), radius, 5)
	hint_ring = _make_ring(body, UITheme.TEAL, Color(0.29, 0.74, 0.72, 0.18), radius, 5)


func _make_ring(body: Rect2, border: Color, fill: Color, radius: int, width: int) -> Panel:
	var p := Panel.new()
	add_child(p)  # attach BEFORE positioning (RTL locales would otherwise mirror the offset)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = body.position - Vector2(3, 3)
	p.size = body.size + Vector2(6, 6)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	return p


func set_texture(tex: Texture2D) -> void:
	face_rect.texture = tex


func set_dimmed(on: bool, high_contrast: bool) -> void:
	if on:
		face_rect.self_modulate = Color(0.62, 0.64, 0.68) if high_contrast else Color(0.80, 0.81, 0.84)
	else:
		face_rect.self_modulate = Color.WHITE


func _kill() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()


func set_selected(on: bool, animate: bool) -> void:
	ring.visible = on
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
	z_index = 0
	_kill()
	if not animate:
		_tw = create_tween()
		_tw.tween_property(self, "modulate:a", 0.0, 0.09)
		_tw.tween_callback(hide)
		return
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.06)
	_tw.tween_property(self, "scale", Vector2(0.55, 0.55), 0.16).set_ease(Tween.EASE_IN)
	_tw.parallel().tween_property(self, "modulate:a", 0.0, 0.16)
	_tw.tween_callback(hide)


func play_restore(animate: bool) -> void:
	gone = false
	_kill()
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
	if animate:
		_tw = create_tween()
		for dx in [-6.0, 6.0, -4.0, 3.0, 0.0]:
			_tw.tween_property(self, "position:x", base_pos.x + dx, 0.035)
	else:
		# Reduced motion: brief static tint instead of a shake.
		face_rect.modulate = Color(1.0, 0.75, 0.75)
		_tw = create_tween()
		_tw.tween_interval(0.25)
		_tw.tween_callback(func() -> void: face_rect.modulate = Color.WHITE)
