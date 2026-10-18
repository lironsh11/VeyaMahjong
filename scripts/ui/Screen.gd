class_name Screen
extends Control
## Base for every full screen: full-rect anchoring, safe-area insets (notches, punch holes,
## gesture bars), locale-driven layout direction (RTL for Hebrew) and automatic rebuild when
## the language or theme changes, so switching language needs no restart.

const BASE_PAD := 16

var safe: MarginContainer  ## children go here; it already respects safe insets
var _built: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	LocalizationService.locale_changed.connect(_on_relayout)
	UITheme.theme_rebuilt.connect(_on_relayout)
	get_viewport().size_changed.connect(_update_safe_area)
	_rebuild()


func _on_relayout(_a: Variant = null) -> void:
	_rebuild.call_deferred()


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	layout_direction = Control.LAYOUT_DIRECTION_RTL if LocalizationService.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	build_background()
	safe = MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)
	_update_safe_area()
	build()
	_built = true


func build_background() -> void:
	## Override to add full-bleed backgrounds behind the safe area.
	pass


func build() -> void:
	## Override: build the screen UI into `safe`.
	pass


func on_back() -> bool:
	## Override to intercept Android back / Escape. Return true when handled.
	return false


func save_state() -> void:
	pass


static func safe_insets(vp: Viewport) -> Vector4:
	## (left, top, right, bottom) in logical canvas pixels.
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return Vector4.ZERO
	var safe_rect := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var s := vp.get_visible_rect().size.x / float(win.x)
	return Vector4(
		maxf(0.0, safe_rect.position.x) * s,
		maxf(0.0, safe_rect.position.y) * s,
		maxf(0.0, screen.x - safe_rect.end.x) * s,
		maxf(0.0, screen.y - safe_rect.end.y) * s)


func _update_safe_area() -> void:
	if safe == null or not is_inside_tree():
		return
	var ins := safe_insets(get_viewport())
	safe.add_theme_constant_override("margin_left", BASE_PAD + int(ins.x))
	safe.add_theme_constant_override("margin_top", BASE_PAD + int(ins.y))
	safe.add_theme_constant_override("margin_right", BASE_PAD + int(ins.z))
	safe.add_theme_constant_override("margin_bottom", 10 + int(ins.w))


func t(key: String, vars: Dictionary = {}) -> String:
	return LocalizationService.t(key, vars)
