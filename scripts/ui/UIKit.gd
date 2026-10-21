class_name UIKit
extends RefCounted
## Reusable UI builders. Text is always a live Godot Label (never baked into PNGs) so every
## locale renders, wraps and mirrors correctly.

static func label(text: String, size: int = UITheme.FONT_BODY, bold: bool = false, color: Variant = null, align: int = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if bold:
		l.add_theme_font_override("font", UITheme.font_bold)
	if color != null:
		l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, color: Variant = null) -> Label:
	return label(text, UITheme.FONT_TITLE, true, color, HORIZONTAL_ALIGNMENT_CENTER)


static func button(text: String, color: String = "green", size: String = "large", on_press: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "Btn_%s_%s" % [color, size]
	b.custom_minimum_size = Vector2(0, 72 if size == "large" else UITheme.TOUCH_MIN)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: AudioService.play("button"))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func tab_button(text: String, active: bool, on_press: Callable) -> Button:
	## Segmented-control button that wraps long names (e.g. German/Russian world names).
	var b := button(text, "cream", "small", on_press)
	b.theme_type_variation = "TabOn" if active else "TabOff"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, UITheme.TOUCH_MIN)
	b.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	return b


static func world_tabs(selected: String, on_pick: Callable, mark_locked: bool = false) -> GridContainer:
	## One tab per world, three per row (six worlds don't fit one row on a 540 px screen).
	## on_pick(world_id) runs when a tab is pressed.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for w in ContentService.worlds:
		var wid := str(w.id)
		var b := tab_button(LocalizationService.t(ContentService.world_name_key(wid)), wid == selected, func() -> void: on_pick.call(wid))
		if mark_locked and not GameState.is_level_unlocked(ContentService.world_range(wid).x):
			b.icon = UITheme.scaled_tex("ui/icons/emerald/lock.png", 0.27)
		grid.add_child(b)
	return grid


static func tool_button(icon_name: String, text: String, white: bool = true, icon_size: int = 40, on_press: Callable = Callable()) -> Button:
	## Icon + text vertical button with a generous hit area (icon and label are drawn as
	## children; the Button itself is the touch target).
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.custom_minimum_size = Vector2(76, 76)
	b.focus_mode = Control.FOCUS_ALL
	var v := VBoxContainer.new()
	v.name = "Box"
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	var ic := TextureRect.new()
	ic.texture = ContentService.icon(icon_name, white)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(icon_size, icon_size)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.name = "Icon"
	v.add_child(ic)
	var l := label(text, UITheme.FONT_SMALL, true, Color.WHITE if white else UITheme.text_color(), HORIZONTAL_ALIGNMENT_CENTER, false)
	l.name = "Text"
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	v.add_child(l)
	b.add_child(v)
	AccessibilityService.set_access_name(b, text)
	b.pressed.connect(func() -> void: AudioService.play("button"))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func icon_button(icon_name: String, access_name: String, on_press: Callable = Callable(), diameter: int = 64, mirror_rtl: bool = false) -> Button:
	## Round icon-only button (cream disc). Accessibility name is required.
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = access_name
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", UITheme.flat(Color(UITheme.IVORY, 0.96), diameter / 2, Color("E8CFA0"), 2, 0))
	b.add_child(bg)
	var ic := TextureRect.new()
	ic.texture = ContentService.icon(icon_name, false)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := diameter * 0.22
	ic.offset_left = inset
	ic.offset_top = inset
	ic.offset_right = -inset
	ic.offset_bottom = -inset
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.flip_h = mirror_rtl and LocalizationService.is_rtl()
	b.add_child(ic)
	AccessibilityService.set_access_name(b, access_name)
	b.pressed.connect(func() -> void: AudioService.play("button"))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func focus_initial(c: Control) -> void:
	## Keyboard/gamepad users get an initial focus target; touch users never see a stray
	## focus ring (Godot draws focus whenever a control holds it).
	if DisplayServer.is_touchscreen_available():
		return
	if is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()


static func vbox(sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(h: int = 0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	return p


static func texrect(tex: Texture2D, size: Vector2 = Vector2.ZERO) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func fullscreen_bg(parent: Control, tex: Texture2D, dim: float = 0.0, dim_color: Color = Color.BLACK) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	if dim > 0.0:
		var c := ColorRect.new()
		c.color = Color(dim_color, dim)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(c)
	return r


static func header(title_text: String, on_back: Callable = Callable(), light: bool = false) -> HBoxContainer:
	## Title row with a back button that mirrors in RTL.
	var h := hbox(10)
	h.custom_minimum_size.y = 64
	if on_back.is_valid():
		h.add_child(icon_button("back", LocalizationService.t("a11y_back"), on_back, 56, true))
	var l := label(title_text, UITheme.FONT_H2 + 3, true, Color.WHITE if light else null, HORIZONTAL_ALIGNMENT_CENTER, false)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if light:
		l.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.6))
		l.add_theme_constant_override("outline_size", 6)
	h.add_child(l)
	if on_back.is_valid():
		h.add_child(spacer())  # keeps the title optically centred
		h.get_child(h.get_child_count() - 1).custom_minimum_size.x = 56
	return h


static func bottom_nav(active: String) -> PanelContainer:
	## Home / Worlds / Daily / Collection / (Shop). Every item navigates somewhere real.
	var p := panel("NavBar")
	var h := hbox(0)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(h)
	var items := [["home", "home", "home"], ["worlds", "worlds", "worlds"], ["daily", "daily", "daily"], ["collection", "collection", "collection"]]
	if FeatureFlags.enabled("shop_enabled"):
		items.append(["shop", "shop", "shop"])
	for it in items:
		var b := tool_button(it[1], LocalizationService.t(it[0]), false, 34, func() -> void:
			if Router.current_name == it[2]:
				return
			if it[2] == "home":
				Router.reset_to("home")
			else:
				Router.go(it[2]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(64, 72)
		var nav_label := b.get_node("Box/Text") as Label
		fit_label(nav_label, 96.0, UITheme.FONT_SMALL, 12)
		if it[2] == active:
			var sb := UITheme.flat(Color(UITheme.TEAL, 0.22), 18)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			(b.get_node("Box/Text") as Label).add_theme_color_override("font_color", UITheme.NAVY)
		else:
			(b.get_node("Box/Text") as Label).add_theme_color_override("font_color", UITheme.text_soft())
		h.add_child(b)
	return p


static func fit_label(l: Label, max_w: float, size: int, min_size: int) -> void:
	## Shrinks a single-line label's font until it fits (long German/Russian/Japanese words).
	var font: Font = l.get_theme_font("font")
	var fs := size
	while fs > min_size and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)


static func progress_bar(value: float, max_value: float, height: int = 18) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = max_value
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, height)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


static func chip(text: String, style: String = "ChipEmerald") -> PanelContainer:
	## Status chip / badge: pack sprite (ChipEmerald, ChipCream, BadgeGreen, BadgeRed,
	## BadgeGold) with live text on top.
	var p := PanelContainer.new()
	p.theme_type_variation = style
	var fg: Color = UITheme.text_color() if style in ["ChipCream", "BadgeGold"] else Color.WHITE
	p.add_child(label(text, UITheme.FONT_SMALL, true, fg, HORIZONTAL_ALIGNMENT_CENTER, false))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func scroll(content: Control) -> ScrollContainer:
	## A vertical list that touch-drags from anywhere, its cards and buttons included.
	var s := TouchScroll.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s


static func set_tool_badge(b: Button, text: String, style: String) -> void:
	## Count badge on a tool_button's top-end corner (mirrors to top-left in RTL). An empty
	## text removes it.
	var old := b.get_node_or_null("Badge")
	if old:
		b.remove_child(old)
		old.queue_free()
	if text == "":
		return
	var c := chip(text, style)
	c.name = "Badge"
	b.add_child(c)  # attach before positioning (RTL mirrors the corner automatically)
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 4)
	c.position.y = -6
	c.z_index = 1


static func coin_pill(on_press: Callable = Callable(), light: bool = true) -> Button:
	## Coin balance; live-updates from EconomyService and opens the shop when tapped.
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 52)
	var p := panel("HudPill")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(p)
	var h := hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(h)
	h.add_child(texrect(ContentService.icon("coin", light), Vector2(26, 26)))
	var l := label("", UITheme.FONT_BODY, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	l.name = "Amount"
	h.add_child(l)
	var refresh := func() -> void:
		if is_instance_valid(l):
			l.text = LocalizationService.format_number(EconomyService.coins())
			AccessibilityService.set_access_name(b, LocalizationService.t("a11y_coins", {"count": EconomyService.coins()}))
			b.custom_minimum_size.x = maxf(96.0, l.get_minimum_size().x + 64.0)
	refresh.call()
	EconomyService.wallet_changed.connect(refresh)
	b.tree_exiting.connect(func() -> void:
		if EconomyService.wallet_changed.is_connected(refresh):
			EconomyService.wallet_changed.disconnect(refresh))
	b.pressed.connect(func() -> void: AudioService.play("button"))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func stars_row(filled: int, px: float = 22.0, total: int = 3) -> HBoxContainer:
	## 1-3 earned stars (gold) out of `total` (dim). Direction-neutral, so never mirrored.
	var h := hbox(2)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.layout_direction = Control.LAYOUT_DIRECTION_LTR
	for k in total:
		var s := texrect(ContentService.icon("star", true), Vector2(px, px))
		s.name = "Star%d" % k
		s.pivot_offset = Vector2(px, px) * 0.5
		s.self_modulate = UITheme.GOLD if k < filled else Color(0.6, 0.62, 0.66, 0.55)
		h.add_child(s)
	AccessibilityService.set_access_name(h, LocalizationService.t("a11y_stars", {"count": filled}))
	return h


static func streak_pill(count: int, height: int = 52) -> PanelContainer:
	## Win-streak flame with the current count (HUD and Home).
	var p := panel("HudPill")
	p.custom_minimum_size = Vector2(0, height)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := hbox(4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(StreakFlame.make(26.0, count > 0))
	h.add_child(label(LocalizationService.format_number(count), UITheme.FONT_BODY, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false))
	AccessibilityService.set_access_name(p, LocalizationService.t("streak_n", {"count": count}))
	return p
