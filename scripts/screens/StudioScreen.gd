extends Screen
## Board Studio: build a board, prove it winnable, play it and share it as a code.
## - Create: pick a shape, width, layers, tile count and how it is carved; the preview shows the
##   exact shape. Check & Play builds the faces and proves the board can be cleared (on a worker
##   thread); the board is saved to My boards with its code.
## - My boards: the player's boards and friends' boards (codes only), play solo or together.
## - Enter code: type or paste a friend's code (forgiving input, clear error messages).
## Studio boards never pay out coins, Lights or streak progress.
##
## Params: {"tab": "create"|"mine"|"code"}

const FreePlay := preload("res://scripts/screens/FreePlayScreen.gd")
const TILE_STEP := 4

static var _params := {}   ## the Create tab's settings survive leaving and coming back

var _tab: String = "create"
var _busy: bool = false
var _status: Label
var _code_field: LineEdit
var _code_error: Label
var _code_text: String = ""


func _ready() -> void:
	_tab = str(Router.params.get("tab", "create"))
	if not _tab in ["create", "mine", "code"]:
		_tab = "create"
	if _params.is_empty():
		_params = {"family": "pyramid", "cols": 6, "layers": 3, "mode": "top", "tiles": 72, "seed": Time.get_ticks_usec() % (StudioCode.SEED_MAX + 1)}
	_clamp_tiles()
	FreePlayService.mark_seen("studio")
	super._ready()


func build_background() -> void:
	var w := str(ContentService.world_for_level(GameState.next_level(ContentService.level_count())).get("id", "aurora_garden"))
	UIKit.fullscreen_bg(self, ContentService.world_bg(w, "bloom", AccessibilityService.low_profile), 0.0)


func build() -> void:
	var root := UIKit.vbox(10)
	safe.add_child(root)
	root.add_child(UIKit.header(t("board_studio"), func() -> void: Router.back(), true))
	var tabs := UIKit.hbox(6)
	for pair in [["create", "studio_tab_create"], ["mine", "studio_tab_mine"], ["code", "studio_tab_code"]]:
		var id: String = pair[0]
		tabs.add_child(UIKit.tab_button(t(pair[1]), _tab == id, func() -> void:
			_tab = id
			_rebuild()))
	root.add_child(tabs)
	match _tab:
		"mine":
			_build_mine(root)
		"code":
			_build_code(root)
		_:
			_build_create(root)


# --- Create ---------------------------------------------------------------------------

func _clamp_tiles() -> void:
	## Keep a tile count this exact shape can be carved to, so the preview always shows the board.
	var n := StudioBoard.fit_tiles(_params)
	if n > 0:
		_params.tiles = n


func _change(key: String, value: Variant) -> void:
	_params[key] = value
	_clamp_tiles()
	_rebuild()


func _build_create(root: VBoxContainer) -> void:
	var list := UIKit.vbox(10)
	# Preview: the exact shape these settings build.
	var pc := UIKit.panel("Card")
	pc.custom_minimum_size.y = 300
	var pv := UIKit.vbox(4)
	var preview := BoardView.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size.y = 250
	AccessibilityService.set_access_name(preview, t("a11y_board_preview"))
	pv.add_child(preview)
	var preview_state: BoardState = null
	var positions := StudioBoard.positions_for(_params)
	if not positions.is_empty():
		var geo := BoardGeometry.from_positions(positions)
		var faces := PackedStringArray()
		faces.resize(geo.count)
		faces.fill("dragon_white")
		preview_state = BoardState.create(geo, faces)
	preview.input_enabled = false
	var info := "%s · %s" % [t("tiles_n", {"count": int(_params.tiles)}), t("layers_n", {"count": LayoutTemplates.layer_count(positions) if not positions.is_empty() else int(_params.layers)})]
	pv.add_child(UIKit.label(info, UITheme.FONT_SMALL, true, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER, false))
	pc.add_child(pv)
	list.add_child(pc)
	# Shape
	var sc := UIKit.panel("Card")
	var sv := UIKit.vbox(8)
	sv.add_child(UIKit.label(t("studio_shape"), UITheme.FONT_BODY, true))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for fam in LayoutTemplates.FAMILIES:
		grid.add_child(UIKit.tab_button(t("shape_" + fam), str(_params.family) == fam, _change.bind("family", fam)))
	sv.add_child(grid)
	sc.add_child(sv)
	list.add_child(sc)
	# Size
	var zc := UIKit.panel("Card")
	var zv := UIKit.vbox(8)
	var r := StudioBoard.tile_range(_params)
	zv.add_child(UIKit.stepper(t("studio_tiles"), LocalizationService.format_number(int(_params.tiles)),
		func() -> void: _change("tiles", maxi(r.x, int(_params.tiles) - TILE_STEP)),
		func() -> void: _change("tiles", mini(r.y, int(_params.tiles) + TILE_STEP)),
		t("a11y_fewer_tiles"), t("a11y_more_tiles")))
	zv.add_child(UIKit.stepper(t("studio_layers"), LocalizationService.format_number(int(_params.layers)),
		func() -> void: _change("layers", maxi(StudioCode.MIN_LAYERS, int(_params.layers) - 1)),
		func() -> void: _change("layers", mini(StudioCode.MAX_LAYERS, int(_params.layers) + 1)),
		t("a11y_fewer_layers"), t("a11y_more_layers")))
	zv.add_child(UIKit.stepper(t("studio_width"), LocalizationService.format_number(int(_params.cols)),
		func() -> void: _change("cols", maxi(StudioCode.MIN_COLS, int(_params.cols) - 1)),
		func() -> void: _change("cols", mini(StudioCode.MAX_COLS, int(_params.cols) + 1)),
		t("a11y_narrower"), t("a11y_wider")))
	var carve := UIKit.hbox(6)
	var cl := UIKit.label(t("studio_carve"), UITheme.FONT_BODY, true)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carve.add_child(cl)
	for m in LayoutTemplates.MODES:
		var b := UIKit.tab_button(t("carve_" + m), str(_params.mode) == m, _change.bind("mode", m))
		b.size_flags_horizontal = Control.SIZE_FILL
		b.custom_minimum_size.x = 120
		carve.add_child(b)
	zv.add_child(carve)
	zv.add_child(UIKit.button(t("studio_variation"), "cream", "small", func() -> void:
		_change("seed", (int(_params.seed) + 1 + Time.get_ticks_usec() % 977) % (StudioCode.SEED_MAX + 1))))
	zc.add_child(zv)
	list.add_child(zc)
	root.add_child(UIKit.scroll(list))
	if preview_state != null:
		preview.setup(preview_state, ProgressionService.equipped_theme())  # in the tree now
	preview.input_enabled = false
	_status = _outlined_label("")
	_status.visible = false
	root.add_child(_status)
	var go := UIKit.button(t("studio_check_play"), "green", "large", _check_and_play)
	go.disabled = r.y <= 0
	root.add_child(go)


func _check_and_play() -> void:
	if _busy:
		return
	_busy = true
	_status.text = t("studio_checking")
	_status.visible = true
	var p := _params.duplicate()
	Jobs.run(func() -> Dictionary: return StudioBoard.make(p), _on_made)


func _on_made(res: Variant) -> void:
	_busy = false
	if not is_inside_tree():
		return
	if is_instance_valid(_status):
		_status.visible = false
	if typeof(res) != TYPE_DICTIONARY or not bool(res.get("ok", false)):
		var m := ModalDialog.open(self, t("studio_impossible_title"), t("studio_impossible"))
		m.add_action(t("ok"), "ok", "green")
		return
	StudioBoard.remember(res.level)
	_params = (res.params as Dictionary).duplicate()
	var saved := FreePlayService.save_board(str(res.code), false)
	AnalyticsService.track("studio_board_made", {"tiles": int(_params.tiles), "layers": int(_params.layers), "shape": str(_params.family)})
	var m := ModalDialog.open(self, t("studio_ready_title"), t("studio_ready_body"))
	var box := UIKit.vbox(8)
	box.add_child(FreePlay.code_row(str(res.code)))
	box.add_child(UIKit.label("%s %s" % [t("studio_difficulty"), t("band_" + str(res.band))], UITheme.FONT_SMALL, true, UITheme.VIOLET, HORIZONTAL_ALIGNMENT_CENTER))
	if str(res.adjusted) == "seed":
		box.add_child(_soft(t("studio_adjusted_seed")))
	elif str(res.adjusted) == "tiles":
		box.add_child(_soft(t("studio_adjusted_tiles", {"count": int(_params.tiles)})))
	if bool(res.small):
		box.add_child(_soft(t("studio_small_tiles")))
	if saved == "full":
		box.add_child(_soft(t("studio_full", {"count": FreePlayService.MAX_BOARDS})))
	elif saved == "saved":
		box.add_child(_soft(t("studio_saved")))
	m.add_content(box)
	m.add_action(t("play"), "play", "green")
	m.add_action(t("play_together"), "together", "gold", "small")
	m.add_action(t("cancel"), "close", "cream", "small")
	m.closed.connect(_on_board_choice.bind(str(res.code)))


# --- My boards ------------------------------------------------------------------------

func _build_mine(root: VBoxContainer) -> void:
	var list := UIKit.vbox(10)
	var boards := FreePlayService.boards()
	if boards.is_empty():
		var c := UIKit.panel("Card")
		c.add_child(UIKit.label(t("studio_mine_empty"), UITheme.FONT_BODY, false, null, HORIZONTAL_ALIGNMENT_CENTER))
		list.add_child(c)
	for b in boards:
		if typeof(b) == TYPE_DICTIONARY:
			list.add_child(_board_card(b))
	root.add_child(UIKit.scroll(list))
	root.add_child(_outlined_label(t("studio_made_n", {"count": FreePlayService.boards_made()})))


func _board_card(b: Dictionary) -> Control:
	var code := str(b.get("code", ""))
	var d := StudioCode.decode(code)
	var card := UIKit.panel("Card")
	var v := UIKit.vbox(6)
	var top := UIKit.hbox(8)
	var cl := UIKit.label(code, UITheme.FONT_H2, true, UITheme.NAVY, HORIZONTAL_ALIGNMENT_LEFT, false)
	cl.text_direction = Control.TEXT_DIRECTION_LTR
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(cl)
	if bool(b.get("friend", false)):
		top.add_child(UIKit.chip(t("studio_from_code"), "ChipEmerald"))
	if bool(b.get("solved", false)):
		top.add_child(UIKit.chip(t("studio_solved"), "BadgeGreen"))
	v.add_child(top)
	if d.err == StudioCode.Err.OK:
		var p: Dictionary = d.params
		var line := "%s · %s · %s" % [t("shape_" + str(p.family)), t("tiles_n", {"count": int(p.tiles)}), t("layers_n", {"count": int(p.layers)})]
		if int(b.get("best", 0)) > 0:
			line += " · " + t("score_n", {"score": LocalizationService.format_number(int(b.best))})
		v.add_child(UIKit.label(line, UITheme.FONT_SMALL, false, UITheme.text_soft()))
	var row := UIKit.hbox(6)
	for spec in [["play", "play", "green"], ["play_together", "together", "gold"], ["copy_code", "copy", "cream"]]:
		var act: String = spec[1]
		var btn := UIKit.button(t(spec[0]), spec[2], "small", func() -> void: _on_board_choice(act, code))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(btn)
	var del := UIKit.icon_button("close", t("a11y_delete_board"), func() -> void: _confirm_delete(code), 48)
	row.add_child(del)
	v.add_child(row)
	card.add_child(v)
	return card


func _confirm_delete(code: String) -> void:
	var m := ModalDialog.open(self, t("studio_delete_title"), t("studio_delete_body"))
	m.add_content(FreePlay.code_row(code))
	m.add_action(t("delete"), "yes", "rose")
	m.add_action(t("cancel"), "no", "cream", "small")
	m.closed.connect(func(r: String) -> void:
		if r == "yes":
			FreePlayService.delete_board(code)
			_rebuild())


# --- Enter code -----------------------------------------------------------------------

func _build_code(root: VBoxContainer) -> void:
	var c := UIKit.panel("Card")
	var v := UIKit.vbox(10)
	v.add_child(UIKit.label(t("studio_code_intro"), UITheme.FONT_BODY, false, null, HORIZONTAL_ALIGNMENT_CENTER))
	_code_field = UIKit.text_field("LS-XXXX-XXXX", 16, true)
	_code_field.text = _code_text
	_code_field.text_changed.connect(func(s: String) -> void:
		_code_text = s
		if is_instance_valid(_code_error):
			_code_error.visible = false)
	_code_field.text_submitted.connect(func(_s: String) -> void: _play_code())
	AccessibilityService.set_access_name(_code_field, t("a11y_code_field"))
	v.add_child(_code_field)
	_code_error = UIKit.label("", UITheme.FONT_SMALL, true, UITheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_code_error.visible = false
	v.add_child(_code_error)
	var row := UIKit.hbox(8)
	var paste := UIKit.button(t("code_paste"), "cream", "small", func() -> void:
		_code_text = DisplayServer.clipboard_get().strip_edges().left(40)
		_code_field.text = _code_text)
	paste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(paste)
	var play := UIKit.button(t("code_play"), "green", "small", _play_code)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(play)
	v.add_child(row)
	c.add_child(v)
	root.add_child(c)
	root.add_child(UIKit.spacer(0, true))


func _play_code() -> void:
	var res := StudioBoard.from_code(_code_text)
	if res.err != StudioCode.Err.OK:
		_code_error.text = t(StudioCode.error_key(res.err))
		_code_error.visible = true
		AudioService.play("invalid")
		return
	var code := str(res.code)
	var saved := FreePlayService.save_board(code, true)
	AnalyticsService.track("studio_code_entered", {"ok": true})
	var m := ModalDialog.open(self, t("studio_code_ready_title"))
	var box := UIKit.vbox(8)
	box.add_child(FreePlay.code_row(code))
	var p: Dictionary = res.params
	box.add_child(UIKit.label("%s · %s · %s" % [t("shape_" + str(p.family)), t("tiles_n", {"count": int(p.tiles)}), t("layers_n", {"count": int(p.layers)})], UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	if saved == "full":
		box.add_child(_soft(t("studio_full", {"count": FreePlayService.MAX_BOARDS})))
	m.add_content(box)
	m.add_action(t("play"), "play", "green")
	m.add_action(t("play_together"), "together", "gold", "small")
	m.add_action(t("cancel"), "close", "cream", "small")
	m.closed.connect(_on_board_choice.bind(code))


# --- shared ---------------------------------------------------------------------------

func _on_board_choice(r: String, code: String) -> void:
	match r:
		"play":
			GameState.clear_session(FreePlayService.SLOT_STUDIO)
			Router.go("freeplay", {"kind": "studio", "code": code, "restart": true})
		"together":
			Router.go("duet", {"code": code})
		"copy":
			DisplayServer.clipboard_set(t("studio_share_text", {"code": code}))
			Router.toast(t("code_copied"))
		_:
			if _tab == "create":
				_rebuild()


func _soft(text: String) -> Label:
	return UIKit.label(text, UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER)


func _outlined_label(text: String) -> Label:
	var l := UIKit.label(text, UITheme.FONT_SMALL, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.7))
	l.add_theme_constant_override("outline_size", 5)
	return l


func on_back() -> bool:
	Router.back()
	return true
