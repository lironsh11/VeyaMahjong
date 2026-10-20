class_name TrayView
extends Control
## The tray above the board: picked tiles fly here along an arc, twins burst, and a full
## tray shakes. Purely presentational: it never receives input and never changes rules state.
##
## The rules (GameSession) update first; this view mirrors the model's tray order and only
## catches up, so rapid taps never desync. A tile that is still flying simply retargets when
## its slot moves. It draws above the board (z_index) so flights can cross it, and below
## dialogs (ModalDialog uses z_index 100). Like the board it never mirrors in RTL.
##
## Reduced Motion: tiles fade into their slots and pairs fade out; no arcs, particles or shake.
##
## Frame art: art/lishi_v2/ui/tray/tray_{4,5,6}.png (owner art, 216 px high, drawn at half
## size), with each painted slot measured into data/config/tray_slots.json by tools/measure_tray_art.gd.
## Tiles fill those slots' width (see tile_size). A capacity without art falls back to a drawn frame.

signal popped(center: Vector2, combo: int)

const ART_DIR := "res://art/lishi_v2/ui/tray/"
const SLOTS_JSON := "res://data/config/tray_slots.json"
const SLOT_INSET := 3.0    ## px between a slot's painted side and the tile body
const SLOT_RISE := 1.2     ## the tile body may be this much taller than its slot
const TRAY_H := 128.0   ## frame art height on screen (the ornate frame needs room around its slots)
const PAD := 10.0
const GAP := 8.0
const COMBO_BAR_H := 6.0
const FLY_S := 0.26
const RETURN_S := 0.22
const PULL_S := 0.1
const HIT_STOP_S := 0.05
const POP_S := 0.16
const WELL := Color(0.02, 0.2, 0.12, 0.62)
const WELL_DANGER := Color(0.88, 0.2, 0.17, 0.92)
const FRAME := Color(0.05, 0.33, 0.2, 0.92)
const FRAME_EDGE := Color(0.45, 0.78, 0.5, 0.9)
const SPARK_COLORS: Array[Color] = [Color("F4C568"), Color("FFF8EC"), Color("49BDB7"), Color("20A878"), Color("F4A3C7")]
const PRAISE := ["", "", "combo_good", "combo_great", "combo_amazing", "combo_incredible"]

var theme_id: String = "classic"
var capacity: int = TrayRules.CAPACITY
var _root: Control
var _frame: Panel
var _frame_art: TextureRect
var _wells: Array[Panel] = []    ## one per slot: the drawn well, or (with art) the danger overlay
var _bar_bg: ColorRect
var _bar: ColorRect
var _bar_tw: Tween
var _danger_tw: Tween
var _shake_tw: Tween
var _order := PackedInt32Array()
var _faces := PackedStringArray()
var _nodes := {}        ## tile -> TextureRect resting in (or flying to) its slot
var _hi_res: bool = false
static var _dot: Texture2D
static var _art_meta: Dictionary = {}


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	z_index = 10
	custom_minimum_size = Vector2(0, TRAY_H + COMBO_BAR_H + 2.0)
	_root = Control.new()
	add_child(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_frame = Panel.new()
	_root.add_child(_frame)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_theme_stylebox_override("panel", _box(FRAME, 22, FRAME_EDGE, 3))
	_frame_art = TextureRect.new()
	_root.add_child(_frame_art)
	_frame_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_art.stretch_mode = TextureRect.STRETCH_SCALE
	_bar_bg = ColorRect.new()
	_root.add_child(_bar_bg)
	_bar_bg.color = Color(0, 0, 0, 0.25)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = ColorRect.new()
	_bar_bg.add_child(_bar)
	_bar.color = UITheme.GOLD
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.visible = false
	resized.connect(_relayout)
	AccessibilityService.set_access_name(self, LocalizationService.t("a11y_tray"))


static func _box(c: Color, radius: int, edge: Color = Color.TRANSPARENT, edge_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.border_color = edge
	sb.set_border_width_all(edge_w)
	return sb


func _anim() -> bool:
	return not AccessibilityService.reduced_motion()


# --- geometry ------------------------------------------------------------------------

static func art_for(cap: int) -> Dictionary:
	## {"tex", "size": Vector2, "slots": Array[Rect2]} in art pixels, or {} if there is none.
	if _art_meta.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SLOTS_JSON))
		_art_meta = {"_loaded": true}
		if typeof(parsed) == TYPE_DICTIONARY:
			for k in parsed:
				var d: Dictionary = parsed[k]
				var rects: Array[Rect2] = []
				for r in d.get("slots", []):
					rects.append(Rect2(r[0], r[1], r[2], r[3]))
				_art_meta[k] = {"size": Vector2(d.size[0], d.size[1]), "slots": rects}
	var m: Dictionary = _art_meta.get(str(cap), {})
	if m.is_empty() or (m.slots as Array).size() != cap:
		return {}
	if not m.has("tex"):
		m["tex"] = ContentService.tex(ART_DIR + "tray_%d.png" % cap)
	return m if m.tex != null else {}


func _art_scale(art: Dictionary) -> float:
	var s: Vector2 = art.size
	return minf(TRAY_H / s.y, maxf(1.0, size.x) / s.x)


func slot_rect(s: int) -> Rect2:
	## The painted (or drawn) slot, in this control's coordinates.
	var art := art_for(capacity)
	if art.is_empty():
		var h := TRAY_H - PAD * 2.0
		var ts := Vector2(h / BoardFit.ASPECT, h)
		return Rect2(_frame_rect().position + Vector2(PAD + s * (ts.x + GAP), PAD), ts)
	var k := _art_scale(art)
	var r: Rect2 = art.slots[clampi(s, 0, capacity - 1)]
	return Rect2(_frame_rect().position + r.position * k, r.size * k)


func tile_size() -> Vector2:
	## Tile sprite size: its body (BoardView.BODY, the sprite minus shadow padding) fits the
	## slot with SLOT_INSET to spare.
	var art := art_for(capacity)
	if art.is_empty():
		var h := TRAY_H - PAD * 2.0
		return Vector2(h / BoardFit.ASPECT, h)
	# The smallest painted slot decides, so every tile fits every slot.
	var smallest := slot_rect(0).size
	for s in range(1, capacity):
		smallest = smallest.min(slot_rect(s).size)
	# Tiles are taller than the near-square slots, so fitting the height too left them small:
	# they fill the slot's width and stand a little proud of its top and bottom edges (the
	# ornate frame has room around every slot), up to SLOT_RISE of the slot's height.
	var body := BoardView.BODY.size
	var w := (smallest.x - SLOT_INSET * 2.0) / body.x
	var h_fit := smallest.y * SLOT_RISE / (body.y * BoardFit.ASPECT)
	w = minf(w, h_fit)
	return Vector2(w, w * BoardFit.ASPECT)


func _frame_rect() -> Rect2:
	var art := art_for(capacity)
	if art.is_empty():
		var h := TRAY_H - PAD * 2.0
		var w := capacity * (h / BoardFit.ASPECT) + (capacity - 1) * GAP + PAD * 2.0
		return Rect2(Vector2((size.x - w) * 0.5, 0), Vector2(w, TRAY_H))
	var sz: Vector2 = art.size * _art_scale(art)
	return Rect2(Vector2((size.x - sz.x) * 0.5, (TRAY_H - sz.y) * 0.5), sz)


func slot_pos(s: int) -> Vector2:
	## Top-left of a tile sprite whose body is centred in slot s.
	var r := slot_rect(s)
	var ts := tile_size()
	var body_center := (BoardView.BODY.position + BoardView.BODY.size * 0.5) * ts
	return r.get_center() - body_center


func slot_center_global(s: int) -> Vector2:
	return get_global_transform() * slot_rect(s).get_center()


func _to_local_pos(global_p: Vector2) -> Vector2:
	return _root.get_global_transform().affine_inverse() * global_p


func _well_box(danger: bool) -> StyleBoxFlat:
	## With frame art the painted slot shows through; the overlay only tints it red.
	if danger:
		return _box(Color(WELL_DANGER, 0.55) if _has_art() else WELL_DANGER, 10)
	return _box(Color(0, 0, 0, 0) if _has_art() else WELL, 10)


func _has_art() -> bool:
	return not art_for(capacity).is_empty()


func _relayout() -> void:
	var fr := _frame_rect()
	var art := art_for(capacity)
	_frame.visible = art.is_empty()
	_frame_art.visible = not art.is_empty()
	_frame.position = fr.position
	_frame.size = fr.size
	if not art.is_empty():
		_frame_art.texture = art.tex
		_frame_art.position = fr.position
		_frame_art.size = fr.size
	while _wells.size() < capacity:
		var w := Panel.new()
		_root.add_child(w)
		_root.move_child(w, _frame_art.get_index() + 1)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wells.append(w)
	while _wells.size() > capacity:
		_wells.pop_back().queue_free()
	var ts := tile_size()
	for s in _wells.size():
		_wells[s].add_theme_stylebox_override("panel", _well_box(false))
		if art.is_empty():
			_wells[s].position = slot_pos(s) + BoardView.BODY.position * ts
			_wells[s].size = BoardView.BODY.size * ts
		else:
			var r := slot_rect(s)
			_wells[s].position = r.position
			_wells[s].size = r.size
	# The combo bar: on the drawn frame's bottom edge, or just under the ornate art (whose bottom
	# edge carries an ornament), spanning the slots.
	if art.is_empty():
		_bar_bg.position = Vector2(fr.position.x + 22.0, fr.end.y - COMBO_BAR_H * 0.5)
		_bar_bg.size = Vector2(fr.size.x - 44.0, COMBO_BAR_H)
	else:
		var x0 := slot_rect(0).position.x
		var x1 := slot_rect(capacity - 1).end.x
		_bar_bg.position = Vector2(x0, fr.end.y + 1.0)
		_bar_bg.size = Vector2(x1 - x0, COMBO_BAR_H)
	_bar.size.y = COMBO_BAR_H
	var vp := get_viewport()
	var phys := 1.0
	if vp:
		phys = float(DisplayServer.window_get_size().x) / maxf(1.0, vp.get_visible_rect().size.x)
	var want_hi := ts.x * phys > 48.0  # the 192 px atlas, as on the board (see BoardView)
	if want_hi != _hi_res:
		_hi_res = want_hi
		for t in _nodes:
			(_nodes[t] as TextureRect).texture = _tex(_face(t))
	_layout(false)


func _face(tile: int) -> String:
	return _faces[tile] if tile >= 0 and tile < _faces.size() else ""


func _tex(face: String) -> Texture2D:
	return ContentService.tile_texture(theme_id, face, _hi_res)


# --- model mirroring -----------------------------------------------------------------

func show_tray(tray: PackedInt32Array, faces: PackedStringArray, p_capacity: int, animate: bool = false) -> void:
	## Matches the model exactly (screen build, resume, undo). New tiles pop in, stale ones
	## fade out.
	theme_id = ProgressionService.equipped_theme()
	_faces = faces.duplicate()
	if p_capacity != capacity:
		capacity = p_capacity
		_relayout()
	_order = tray.duplicate()
	for t in _nodes.keys():
		if not _order.has(t):
			var old: TextureRect = _nodes[t]
			_nodes.erase(t)
			_fade_free(old, animate)
	for t in _order:
		if not _nodes.has(t):
			var n := _make_node(_face(t))
			n.position = slot_pos(_order.find(t))
			_nodes[t] = n
			if animate and _anim():
				n.scale = Vector2(0.3, 0.3)
				n.create_tween().tween_property(n, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_layout(animate)


func _make_node(face: String) -> TextureRect:
	var n := TextureRect.new()
	_root.add_child(n)  # attach before positioning (RTL would mirror the offset otherwise)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.stretch_mode = TextureRect.STRETCH_SCALE
	n.size = tile_size()
	n.pivot_offset = tile_size() * 0.5
	n.texture = _tex(face)
	return n


func _fade_free(n: Control, animate: bool) -> void:
	if not animate or not _anim():
		n.queue_free()
		return
	var tw := n.create_tween()
	tw.tween_property(n, "modulate:a", 0.0, 0.12)
	tw.tween_callback(n.queue_free)


func _layout(animate: bool) -> void:
	var ts := tile_size()
	for s in _order.size():
		var t := _order[s]
		if not _nodes.has(t):
			continue
		var n: TextureRect = _nodes[t]
		if n.has_meta("flying"):
			continue  # the flight reads its slot every frame
		# Tiles restored on screen build (resume) are made before the tray has its width, at a
		# near-zero size: they take the real size once it is known, or they stay invisible.
		n.size = ts
		n.pivot_offset = ts * 0.5
		var target := slot_pos(s)
		if animate and _anim() and n.position.distance_to(target) > 0.5:
			var tw := n.create_tween()
			tw.tween_property(n, "position", target, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			n.position = target


func _target_of(tile: int, n: Control) -> Vector2:
	var s := _order.find(tile)
	if s >= 0:
		return slot_pos(s)
	return n.get_meta("target", n.position)


# --- flights ---------------------------------------------------------------------------

func fly_in(tile: int, face: String, from_global: Rect2, tray: PackedInt32Array) -> void:
	## A picked tile flies from its board place into its slot.
	_order = tray.duplicate()
	if tile >= _faces.size():
		_faces.resize(tile + 1)
	_faces[tile] = face
	var n := _make_node(face)
	_nodes[tile] = n
	_layout(true)
	_fly(n, tile, from_global, _land.bind(n))


func fly_match(tile: int, face: String, from_global: Rect2, partner: int, partner_slot: int, tray: PackedInt32Array, combo: int, points: int) -> void:
	## A picked tile flies next to its twin's slot; on arrival both pull together and burst.
	## The twin may itself still be flying (two quick taps): it retargets to the same slot.
	_order = tray.duplicate()
	if tile >= _faces.size():
		_faces.resize(tile + 1)
	_faces[tile] = face
	var p_node: TextureRect = _nodes.get(partner)
	_nodes.erase(partner)
	var meet := slot_pos(partner_slot)
	if p_node == null:
		p_node = _make_node(face)
		p_node.position = meet
	p_node.set_meta("target", meet)
	var n := _make_node(face)
	n.set_meta("target", meet + Vector2(tile_size().x * 0.6, 0))
	_fly(n, tile, from_global, _pop_pair.bind(n, p_node, combo, points))
	# The rest of the tray closes the gap a moment later, after the pair has met.
	get_tree().create_timer(FLY_S + PULL_S if _anim() else 0.0).timeout.connect(func() -> void:
		if is_inside_tree():
			_layout(true))


func _fly(n: TextureRect, tile: int, from_global: Rect2, on_land: Callable) -> void:
	if not _anim() or from_global.size.x <= 0.0:
		n.position = _target_of(tile, n)
		n.modulate.a = 0.0
		var tw0 := n.create_tween()
		tw0.tween_property(n, "modulate:a", 1.0, 0.12)
		tw0.tween_callback(on_land)
		return
	var start := _to_local_pos(from_global.position)
	var start_scale := clampf(from_global.size.x / tile_size().x, 0.4, 2.5)
	var end0 := _target_of(tile, n)
	var ctrl := Vector2(lerpf(start.x, end0.x, 0.5) + (start.x - end0.x) * 0.25, minf(start.y, end0.y) - 60.0)
	var spin := 0.18 if start.x > end0.x else -0.18
	n.set_meta("flying", true)
	n.z_index = 2
	n.position = start
	n.scale = Vector2(start_scale, start_scale)
	n.pivot_offset = Vector2.ZERO
	var tw := n.create_tween()
	# Tap squash first, then the arc.
	tw.tween_property(n, "scale", Vector2(start_scale * 1.08, start_scale * 1.08), 0.05)
	tw.tween_method(func(t: float) -> void:
		var end := _target_of(tile, n)
		var a := start.lerp(ctrl, t)
		var b := ctrl.lerp(end, t)
		n.position = a.lerp(b, t)
		var sc := lerpf(start_scale * 1.08, 1.0, t)
		n.scale = Vector2(sc, sc)
		n.rotation = sin(t * PI) * spin, 0.0, 1.0, FLY_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		n.remove_meta("flying")
		n.z_index = 0
		n.rotation = 0.0
		n.scale = Vector2.ONE
		n.pivot_offset = tile_size() * 0.5
		n.position = _target_of(tile, n)
		on_land.call())


func _land(n: TextureRect) -> void:
	if not _anim():
		return
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(1.12, 0.9), 0.06)
	tw.tween_property(n, "scale", Vector2(0.96, 1.04), 0.07)
	tw.tween_property(n, "scale", Vector2.ONE, 0.08)


func send_home(targets: Dictionary, tray: PackedInt32Array, faces: PackedStringArray, on_arrive: Callable) -> void:
	## Tiles leave the tray back to their board places (undo / second chance).
	_faces = faces.duplicate()
	_order = tray.duplicate()
	for tile in targets:
		var n: TextureRect = _nodes.get(tile)
		_nodes.erase(tile)
		var r: Rect2 = targets[tile]
		if n == null or not _anim() or r.size.x <= 0.0:
			if n:
				n.queue_free()
			on_arrive.call(tile)
			continue
		n.pivot_offset = Vector2.ZERO
		n.z_index = 2
		var tw := n.create_tween().set_parallel(true)
		var sc := clampf(r.size.x / tile_size().x, 0.4, 2.5)
		tw.tween_property(n, "position", _to_local_pos(r.position), RETURN_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(n, "scale", Vector2(sc, sc), RETURN_S)
		tw.chain().tween_callback(func() -> void:
			n.queue_free()
			on_arrive.call(tile))
	_layout(true)


# --- match burst ---------------------------------------------------------------------

func _pop_pair(a: TextureRect, b: TextureRect, combo: int, points: int) -> void:
	var center := (a.position + b.position) * 0.5 + tile_size() * 0.5
	if not _anim():
		_fade_free(a, false)
		_fade_free(b, false)
		_float_text("+%d" % points, center + Vector2(0, -10), UITheme.GOLD, 26)
		popped.emit(get_global_transform() * center, combo)
		return
	for n in [a, b]:
		var tw: Tween = n.create_tween()
		tw.tween_property(n, "position", center - tile_size() * 0.5 + (n.position - center + tile_size() * 0.5) * 0.25, PULL_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(n, "modulate", Color(1.7, 1.7, 1.5), PULL_S)
		tw.tween_interval(HIT_STOP_S)
		tw.tween_property(n, "scale", Vector2(1.3, 1.3), POP_S).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(n, "modulate:a", 0.0, POP_S)
		tw.tween_callback(n.queue_free)
	get_tree().create_timer(PULL_S + HIT_STOP_S).timeout.connect(func() -> void:
		if is_inside_tree():
			_burst(center, combo, points))


func _burst(center: Vector2, combo: int, points: int) -> void:
	if AccessibilityService.effects_on():
		_particles(center, 18 + mini(combo, 6) * 4)
		_spawn_flipbook("match_sparkle", center, tile_size().x * 2.2)
		if combo >= 3:
			_spawn_flipbook("petal_pop", center, tile_size().x * 2.6)
		_ring(center, tile_size().x * (1.1 + 0.15 * mini(combo, 5)))
	_float_text("+%d" % points, center + Vector2(0, -tile_size().y * 0.55), UITheme.GOLD, 26 + mini(combo, 5) * 2)
	if combo >= 2:
		_praise(combo)
	popped.emit(get_global_transform() * center, combo)


func _particles(center: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	_root.add_child(p)
	p.z_index = 3
	p.position = center
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount if not AccessibilityService.low_profile else amount / 2
	p.lifetime = 0.6
	p.texture = _dot_tex()
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 520)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.8
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	p.color_ramp = ramp
	var hues := Gradient.new()
	hues.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	hues.colors = PackedColorArray(SPARK_COLORS)
	p.color_initial_ramp = hues
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)


static func _dot_tex() -> Texture2D:
	if _dot == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d * d, 0.0, 1.0)))
		_dot = ImageTexture.create_from_image(img)
	return _dot


func _ring(center: Vector2, radius: float) -> void:
	var r := Ring.new()
	_root.add_child(r)
	r.z_index = 3
	r.position = center
	var tw := r.create_tween().set_parallel(true)
	tw.tween_property(r, "radius", radius, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(r.queue_free)


func _float_text(text: String, at: Vector2, color: Color, font_size: int) -> void:
	var l := UIKit.label(text, font_size, true, color, HORIZONTAL_ALIGNMENT_CENTER, false)
	_root.add_child(l)
	l.z_index = 4
	l.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.size = Vector2(160, font_size + 12)
	l.position = at - l.size * 0.5
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - (36.0 if _anim() else 0.0), 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func _praise(combo: int) -> void:
	var key: String = PRAISE[clampi(combo, 0, PRAISE.size() - 1)]
	var text := LocalizationService.t(key) + "  ×%d" % combo
	var l := UIKit.label(text, UITheme.FONT_TITLE + mini(combo, 6) * 2, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	_root.add_child(l)
	l.z_index = 5
	l.add_theme_color_override("font_outline_color", Color(UITheme.VIOLET if combo >= 4 else UITheme.NAVY, 0.9))
	l.add_theme_constant_override("outline_size", 10)
	l.size = Vector2(size.x, 60)
	l.position = Vector2(0, TRAY_H + 24)
	l.pivot_offset = l.size * 0.5
	var tw := l.create_tween()
	if _anim():
		l.scale = Vector2(0.4, 0.4)
		tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(l, "scale", Vector2.ONE, 0.08)
	tw.tween_interval(0.45)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


func _spawn_flipbook(effect: String, center: Vector2, px: float) -> void:
	var frames := ContentService.effect_frames(effect)
	if frames.is_empty():
		return
	var tr := TextureRect.new()
	_root.add_child(tr)
	tr.z_index = 3
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


# --- combo, danger, fail -------------------------------------------------------------

func show_combo(combo: int, window_s: float) -> void:
	## The gold bar under the tray drains while another match would extend the combo.
	if _bar_tw and _bar_tw.is_valid():
		_bar_tw.kill()
	_bar_bg.visible = combo >= 1
	if combo < 1:
		return
	_bar.size.x = _bar_bg.size.x
	_bar.color = UITheme.GOLD if combo < 4 else UITheme.ROSE
	_bar_tw = _bar.create_tween()
	_bar_tw.tween_property(_bar, "size:x", 0.0, window_s)
	_bar_tw.tween_callback(func() -> void: _bar_bg.visible = false)


func set_danger(on: bool) -> void:
	## One slot left: the last empty well pulses red.
	if _danger_tw and _danger_tw.is_valid():
		_danger_tw.kill()
	for w in _wells:
		w.self_modulate = Color.WHITE
		w.add_theme_stylebox_override("panel", _well_box(false))
	if not on or _wells.is_empty():
		return
	var last := _wells[mini(_order.size(), _wells.size() - 1)]
	last.add_theme_stylebox_override("panel", _well_box(true))
	if _anim():
		_danger_tw = last.create_tween().set_loops()
		_danger_tw.tween_property(last, "self_modulate:a", 0.45, 0.4)
		_danger_tw.tween_property(last, "self_modulate:a", 1.0, 0.4)


func celebrate() -> void:
	## Level clear: confetti bursts falling from the tray over the board.
	set_danger(false)
	show_combo(0, 0.0)
	if not AccessibilityService.effects_on():
		return
	var rng := RandomNumberGenerator.new()
	for k in 5:
		var at := Vector2(rng.randf_range(0.12, 0.88) * size.x, TRAY_H * rng.randf_range(0.3, 1.0))
		get_tree().create_timer(k * 0.12).timeout.connect(func() -> void:
			if is_inside_tree():
				_particles(at, 34))


func play_fail() -> void:
	set_danger(false)
	for w in _wells:
		w.add_theme_stylebox_override("panel", _well_box(true))
	if not _anim():
		return
	if _shake_tw and _shake_tw.is_valid():
		_shake_tw.kill()
	_shake_tw = _root.create_tween()
	_shake_tw.tween_interval(FLY_S)
	for dx in [-12.0, 12.0, -9.0, 8.0, -5.0, 3.0, 0.0]:
		_shake_tw.tween_property(_root, "position:x", dx, 0.04)


class Ring:
	extends Control
	var radius: float = 4.0:
		set(v):
			radius = v
			queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.95, 0.75), 4.0, true)
