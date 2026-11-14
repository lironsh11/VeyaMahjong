class_name TurnBar
extends HBoxContainer
## Play Together: both players' chips under the HUD. The player whose turn it is gets the bright,
## enlarged chip. Each chip carries a numbered token (1 / 2), so turns never depend on colour.

var _chips: Array[PanelContainer] = []
var _names: Array[String] = []
var _active: int = -1


static func token(n: int, color: Color, px: int = 30) -> Label:
	## A filled circle with the player's number.
	var l := Label.new()
	l.text = str(n)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(px, px)
	l.add_theme_font_size_override("font_size", int(px * 0.58))
	l.add_theme_color_override("font_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(px)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	l.add_theme_stylebox_override("normal", sb)
	if UITheme.font_bold:
		l.add_theme_font_override("font", UITheme.font_bold)
	return l


func setup(names: Array, colors: Array) -> void:
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER
	for c in get_children():
		c.queue_free()
	_chips.clear()
	_names.clear()
	for i in 2:
		var chip := UIKit.panel("HudPill")
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size.y = 40
		var h := UIKit.hbox(8)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(token(i + 1, colors[i]))
		var l := UIKit.label(str(names[i]), UITheme.FONT_BODY, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text_direction = Control.TEXT_DIRECTION_AUTO
		h.add_child(l)
		chip.add_child(h)
		chip.pivot_offset = Vector2(120, 20)
		add_child(chip)
		_chips.append(chip)
		_names.append(str(names[i]))
	_active = -1


func set_active(i: int, animate: bool = true) -> void:
	if i == _active or _chips.is_empty():
		return
	_active = i
	for k in _chips.size():
		var on := k == i
		var c := _chips[k]
		var target_a := 1.0 if on else 0.5
		var target_s := Vector2(1.04, 1.04) if on else Vector2(0.94, 0.94)
		if animate and not AccessibilityService.reduced_motion():
			var tw := c.create_tween().set_parallel(true)
			tw.tween_property(c, "modulate:a", target_a, 0.2)
			tw.tween_property(c, "scale", target_s, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			c.modulate.a = target_a
			c.scale = target_s
	AccessibilityService.set_access_name(self, LocalizationService.t("duet_turn", {"name": _names[i]}))
