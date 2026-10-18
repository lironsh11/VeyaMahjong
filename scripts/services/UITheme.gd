extends Node
## Builds the global Theme at runtime from the pack's label-free UI sprites.
##
## Fonts: Rubik (SIL OFL, bundled) covers Latin, Cyrillic and Hebrew. Japanese, Korean and
## Traditional Chinese use the operating system's CJK fonts through a SystemFont fallback
## ordered for the active language (so Han characters get the right regional glyph forms)
## plus Godot's automatic system fallback. No CJK font files are redistributed.
##
## Pack UI textures are authored for a 1080px-wide canvas; this game's logical canvas is
## 540px wide, so nine-patch textures are downscaled 0.5x once at load. On a 1080px-wide
## phone that renders them 1:1 with the source pixels.

signal theme_rebuilt

const NAVY := Color("153D56")
const NAVY_SOFT := Color("3E6B80")
const IVORY := Color("FFF8EC")
const CREAM := Color("FFF0D4")
const GOLD := Color("F4C568")
const VIOLET := Color("765AC7")
const TEAL := Color("49BDB7")
const ROSE := Color("F4A3C7")
const GREEN := Color("20A878")
const BLUE := Color("379DD8")
const DANGER := Color("C2453F")

const FONT_SMALL := 17
const FONT_BODY := 20
const FONT_H2 := 25
const FONT_TITLE := 32
const FONT_BUTTON := 22
const TOUCH_MIN := 64      ## minimum touch target height (logical px, ~48dp on phones)
const UI_SCALE := 0.5      ## pack texture -> logical canvas

const BUTTON_COLORS := ["green", "blue", "cream", "gold", "violet", "rose"]

var theme: Theme
var font_regular: Font
var font_bold: Font
var high_contrast: bool = false
var _scaled: Dictionary = {}
var _system_fallback: SystemFont


func _ready() -> void:
	high_contrast = bool(GameState.setting("high_contrast"))
	_build_fonts()
	build()
	LocalizationService.locale_changed.connect(_on_locale_changed)
	GameState.settings_changed.connect(_on_setting)


func _on_setting(key: String) -> void:
	if key == "high_contrast":
		high_contrast = bool(GameState.setting("high_contrast"))
		build()


func _on_locale_changed(_code: String) -> void:
	_order_cjk_fallback()


func text_color() -> Color:
	return Color("0A1E2B") if high_contrast else NAVY


func text_soft() -> Color:
	return Color("16384A") if high_contrast else NAVY_SOFT


func _build_fonts() -> void:
	var base: FontFile = load("res://assets/fonts/Rubik-Variable.ttf")
	base.allow_system_fallback = true
	_system_fallback = SystemFont.new()
	_system_fallback.allow_system_fallback = true
	_order_cjk_fallback()
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	var reg := FontVariation.new()
	reg.base_font = base
	reg.variation_opentype = {wght: 420}
	reg.fallbacks = [_system_fallback]
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_opentype = {wght: 620}
	bold.fallbacks = [_system_fallback]
	font_regular = reg
	font_bold = bold


func _order_cjk_fallback() -> void:
	if _system_fallback == null:
		return
	var jp := ["Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic UI", "Meiryo"]
	var tc := ["Noto Sans CJK TC", "Noto Sans TC", "PingFang TC", "Heiti TC", "Microsoft JhengHei UI", "Microsoft JhengHei"]
	var kr := ["Noto Sans CJK KR", "Noto Sans KR", "Apple SD Gothic Neo", "Malgun Gothic"]
	var names: Array = []
	match LocalizationService.current:
		"ja":
			names = jp + tc + kr
		"ko":
			names = kr + jp + tc
		_:
			names = tc + jp + kr
	names.append_array(["Droid Sans Fallback", "Arial Unicode MS", "sans-serif"])
	_system_fallback.font_names = PackedStringArray(names)


func scaled_tex(rel_path: String, factor: float = UI_SCALE) -> Texture2D:
	var key := "%s@%s" % [rel_path, factor]
	if _scaled.has(key):
		return _scaled[key]
	var src := ContentService.tex(rel_path)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.resize(maxi(1, int(img.get_width() * factor)), maxi(1, int(img.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(img)
	_scaled[key] = t
	return t


func nine(rel_path: String, l: int, t: int, r: int, b: int, content_h: int = 18, content_v: int = 10) -> StyleBoxTexture:
	## Nine-patch from a pack texture; margins are given in SOURCE pixels.
	var sb := StyleBoxTexture.new()
	sb.texture = scaled_tex(rel_path)
	sb.texture_margin_left = l * UI_SCALE
	sb.texture_margin_top = t * UI_SCALE
	sb.texture_margin_right = r * UI_SCALE
	sb.texture_margin_bottom = b * UI_SCALE
	sb.content_margin_left = content_h
	sb.content_margin_right = content_h
	sb.content_margin_top = content_v
	sb.content_margin_bottom = content_v + 4
	return sb


func flat(bg: Color, radius: int = 18, border: Color = Color.TRANSPARENT, border_w: int = 0, pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	sb.anti_aliasing = true
	return sb


func build() -> void:
	var th := Theme.new()
	th.default_font = font_regular
	th.default_font_size = FONT_BODY
	var tc := text_color()

	th.set_color("font_color", "Label", tc)
	th.set_constant("line_spacing", "Label", 2)

	# Buttons: pack pills (460x150 large / 220x100 small); margins avoid the rounded caps.
	for col in BUTTON_COLORS:
		for size in ["large", "small"]:
			var type := "Btn_%s_%s" % [col, size]
			th.add_type(type)
			th.set_type_variation(type, "Button")
			var m := [72, 40, 72, 52] if size == "large" else [46, 30, 46, 40]
			var base := "ui/buttons/%s_%s_" % [col, size]
			th.set_stylebox("normal", type, nine(base + "normal.png", m[0], m[1], m[2], m[3], 22, 8))
			th.set_stylebox("hover", type, nine(base + "normal.png", m[0], m[1], m[2], m[3], 22, 8))
			th.set_stylebox("pressed", type, nine(base + "pressed.png", m[0], m[1], m[2], m[3], 22, 8))
			th.set_stylebox("disabled", type, nine(base + "disabled.png", m[0], m[1], m[2], m[3], 22, 8))
			th.set_stylebox("focus", type, _focus_box())
			for st in ["normal", "hover", "pressed", "disabled"]:
				th.set_stylebox(st + "_mirrored", type, th.get_stylebox(st, type))
			var fc := tc if col in ["cream", "gold"] else Color.WHITE
			th.set_color("font_color", type, fc)
			th.set_color("font_hover_color", type, fc)
			th.set_color("font_pressed_color", type, fc)
			th.set_color("font_focus_color", type, fc)
			th.set_color("font_disabled_color", type, Color(fc, 0.55))
			th.set_color("icon_normal_color", type, fc)
			th.set_font("font", type, font_bold)
			th.set_font_size("font_size", type, FONT_BUTTON if size == "large" else FONT_BODY)
			if high_contrast and fc == Color.WHITE:
				th.set_color("font_outline_color", type, Color(0, 0, 0, 0.8))
				th.set_constant("outline_size", type, 4)
	# Plain Button default = cream small (secondary)
	th.set_stylebox("normal", "Button", th.get_stylebox("normal", "Btn_cream_small"))
	th.set_stylebox("hover", "Button", th.get_stylebox("hover", "Btn_cream_small"))
	th.set_stylebox("pressed", "Button", th.get_stylebox("pressed", "Btn_cream_small"))
	th.set_stylebox("disabled", "Button", th.get_stylebox("disabled", "Btn_cream_small"))
	th.set_stylebox("focus", "Button", _focus_box())
	th.set_color("font_color", "Button", tc)
	th.set_color("font_hover_color", "Button", tc)
	th.set_color("font_pressed_color", "Button", tc)
	th.set_color("font_disabled_color", "Button", Color(tc, 0.5))
	th.set_font("font", "Button", font_bold)

	# Flat transparent button for tool/nav buttons (icon + text drawn by children).
	th.add_type("FlatTool")
	th.set_type_variation("FlatTool", "Button")
	var clear := StyleBoxEmpty.new()
	var pressed_tint := flat(Color(1, 1, 1, 0.18), 20)
	th.set_stylebox("normal", "FlatTool", clear)
	th.set_stylebox("hover", "FlatTool", clear)
	th.set_stylebox("pressed", "FlatTool", pressed_tint)
	th.set_stylebox("disabled", "FlatTool", clear)
	th.set_stylebox("focus", "FlatTool", _focus_box())

	# Panels
	var panel_bg := "ui/components/panel_white.png" if high_contrast else "ui/components/panel_cream.png"
	th.set_stylebox("panel", "PanelContainer", nine(panel_bg, 64, 64, 64, 64, 26, 22))
	th.add_type("Card")
	th.set_type_variation("Card", "PanelContainer")
	if high_contrast:
		th.set_stylebox("panel", "Card", flat(Color.WHITE, 22, NAVY, 3, 18))
		th.set_stylebox("panel", "PanelContainer", flat(Color.WHITE, 26, NAVY, 3, 24))
	else:
		th.set_stylebox("panel", "Card", nine("ui/components/card_cream.png", 52, 52, 52, 56, 20, 14))
	th.add_type("CardFlat")
	th.set_type_variation("CardFlat", "PanelContainer")
	th.set_stylebox("panel", "CardFlat", flat(Color(1, 1, 1, 0.97 if high_contrast else 0.9), 22, Color("E8CFA0") if not high_contrast else NAVY, 2, 16))
	th.add_type("HudPill")
	th.set_type_variation("HudPill", "PanelContainer")
	th.set_stylebox("panel", "HudPill", flat(Color(NAVY, 0.92 if high_contrast else 0.78), 28, Color(1, 1, 1, 0.25), 2, 14))
	th.add_type("NavBar")
	th.set_type_variation("NavBar", "PanelContainer")
	th.set_stylebox("panel", "NavBar", flat(Color(IVORY, 0.98), 26, Color("E8CFA0"), 2, 6))
	th.add_type("Toolbar")
	th.set_type_variation("Toolbar", "PanelContainer")
	th.set_stylebox("panel", "Toolbar", flat(Color("0E5A5E", 0.95 if high_contrast else 0.86), 30, Color(TEAL, 0.8), 2, 8))

	# Toggles
	th.set_icon("checked", "CheckButton", scaled_tex("ui/components/toggle_on.png", 0.45))
	th.set_icon("unchecked", "CheckButton", scaled_tex("ui/components/toggle_off.png", 0.45))
	th.set_icon("checked_disabled", "CheckButton", scaled_tex("ui/components/toggle_on.png", 0.45))
	th.set_icon("unchecked_disabled", "CheckButton", scaled_tex("ui/components/toggle_off.png", 0.45))
	# RTL layouts use separate *_mirrored theme items.
	th.set_icon("checked_mirrored", "CheckButton", scaled_tex("ui/components/toggle_on.png", 0.45))
	th.set_icon("unchecked_mirrored", "CheckButton", scaled_tex("ui/components/toggle_off.png", 0.45))
	th.set_icon("checked_disabled_mirrored", "CheckButton", scaled_tex("ui/components/toggle_on.png", 0.45))
	th.set_icon("unchecked_disabled_mirrored", "CheckButton", scaled_tex("ui/components/toggle_off.png", 0.45))
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "normal_mirrored", "hover_mirrored", "pressed_mirrored", "hover_pressed_mirrored", "disabled_mirrored"]:
		th.set_stylebox(st, "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("focus", "CheckButton", _focus_box())
	th.set_color("font_color", "CheckButton", tc)
	th.set_color("font_hover_color", "CheckButton", tc)
	th.set_color("font_pressed_color", "CheckButton", tc)
	th.set_color("font_hover_pressed_color", "CheckButton", tc)

	# Progress bars (pack bar sprites)
	# Progress bars: flat rounded (the pack bar sprites are too tall to nine-patch slimly).
	var track := flat(Color(NAVY, 0.55 if high_contrast else 0.35), 10, Color(1, 1, 1, 0.5), 1, 0)
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	var fill := flat(GOLD, 10, Color.TRANSPARENT, 0, 0)
	th.set_stylebox("background", "ProgressBar", track)
	th.set_stylebox("fill", "ProgressBar", fill)
	th.set_color("font_color", "ProgressBar", tc)

	# Slider
	th.set_stylebox("slider", "HSlider", flat(Color(NAVY, 0.25), 8, Color.TRANSPARENT, 0, 4))
	th.set_stylebox("grabber_area", "HSlider", flat(GREEN, 8, Color.TRANSPARENT, 0, 4))
	th.set_stylebox("grabber_area_highlight", "HSlider", flat(GREEN, 8, Color.TRANSPARENT, 0, 4))
	var grab := _circle_icon(30, GREEN)
	th.set_icon("grabber", "HSlider", grab)
	th.set_icon("grabber_highlight", "HSlider", grab)
	th.set_stylebox("focus", "HSlider", _focus_box())

	# Scrollbars: slim, unobtrusive
	th.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0.05), 4, Color.TRANSPARENT, 0, 2))
	th.set_stylebox("grabber", "VScrollBar", flat(Color(NAVY, 0.35), 4, Color.TRANSPARENT, 0, 2))
	th.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(NAVY, 0.5), 4, Color.TRANSPARENT, 0, 2))
	th.set_stylebox("grabber_pressed", "VScrollBar", flat(Color(NAVY, 0.6), 4, Color.TRANSPARENT, 0, 2))

	# OptionButton / popup (language picker etc.)
	th.set_stylebox("normal", "OptionButton", flat(Color.WHITE, 16, Color("E8CFA0"), 2, 14))
	th.set_stylebox("hover", "OptionButton", flat(Color.WHITE, 16, GOLD, 2, 14))
	th.set_stylebox("pressed", "OptionButton", flat(CREAM, 16, GOLD, 2, 14))
	th.set_stylebox("normal_mirrored", "OptionButton", flat(Color.WHITE, 16, Color("E8CFA0"), 2, 14))
	th.set_stylebox("hover_mirrored", "OptionButton", flat(Color.WHITE, 16, GOLD, 2, 14))
	th.set_stylebox("pressed_mirrored", "OptionButton", flat(CREAM, 16, GOLD, 2, 14))
	th.set_stylebox("disabled_mirrored", "OptionButton", flat(Color(1, 1, 1, 0.6), 16, Color("E8CFA0"), 2, 14))
	th.set_stylebox("disabled", "OptionButton", flat(Color(1, 1, 1, 0.6), 16, Color("E8CFA0"), 2, 14))
	th.set_stylebox("focus", "OptionButton", _focus_box())
	th.set_color("font_color", "OptionButton", tc)
	th.set_color("font_hover_color", "OptionButton", tc)
	th.set_color("font_pressed_color", "OptionButton", tc)
	th.set_color("font_focus_color", "OptionButton", tc)
	th.set_stylebox("panel", "PopupMenu", flat(IVORY, 16, Color("E8CFA0"), 2, 10))
	th.set_color("font_color", "PopupMenu", tc)
	th.set_color("font_hover_color", "PopupMenu", tc)
	th.set_stylebox("hover", "PopupMenu", flat(CREAM, 10, GOLD, 1, 6))
	th.set_font_size("font_size", "PopupMenu", FONT_BODY)
	th.set_constant("v_separation", "PopupMenu", 14)

	theme = th
	get_tree().root.theme = th
	theme_rebuilt.emit()


func _focus_box() -> StyleBoxFlat:
	## Visible keyboard/gamepad focus ring (accessibility); invisible to touch users.
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(3)
	sb.border_color = Color(GOLD.darkened(0.25) if not high_contrast else Color.BLACK)
	sb.set_corner_radius_all(22)
	sb.set_expand_margin_all(3)
	return sb


func _circle_icon(d: int, c: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)
			var col := Color.WHITE if dist < r - 3.5 else c
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)
