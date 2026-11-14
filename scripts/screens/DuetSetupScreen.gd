extends Screen
## Play Together setup: who is playing (names and colours, kept on this device), how big a
## board, then Start. A game in progress can be continued. Boards are Studio presets made and
## proven winnable on a worker thread (StudioBoard.make), so every board also has a share code.
##
## Params: {"auto": bool} start a new board of the saved difficulty at once (after a win);
##         {"code": "LS-…"} play that Studio board together instead of a new one.

var _busy: bool = false
var _start_btn: Button
var _status: Label
var _code: String = ""


func _ready() -> void:
	_code = str(Router.params.get("code", ""))
	if StudioCode.decode(_code).err != StudioCode.Err.OK:
		_code = ""
	FreePlayService.mark_seen("duet")
	super._ready()
	if Router.params.get("auto", false):
		_start.call_deferred()


func build_background() -> void:
	var w := str(ContentService.world_for_level(GameState.next_level(ContentService.level_count())).get("id", "aurora_garden"))
	UIKit.fullscreen_bg(self, ContentService.world_bg(w, "bloom", AccessibilityService.low_profile), 0.0)


func build() -> void:
	var root := UIKit.vbox(10)
	safe.add_child(root)
	root.add_child(UIKit.header(t("play_together"), func() -> void: Router.back(), true))
	var list := UIKit.vbox(12)
	# What it is
	var intro := UIKit.panel("Card")
	var iv := UIKit.vbox(6)
	iv.add_child(UIKit.label(t("duet_intro"), UITheme.FONT_BODY + 1, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	for k in ["duet_rule_turns", "duet_rule_pairs", "duet_rule_tray"]:
		var r := UIKit.hbox(8)
		r.add_child(UIKit.texrect(ContentService.icon("check"), Vector2(22, 22)))
		var l := UIKit.label(t(k), UITheme.FONT_SMALL, false, UITheme.text_soft())
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		iv.add_child(r)
	intro.add_child(iv)
	list.add_child(intro)
	# Players
	var pc := UIKit.panel("Card")
	var pv := UIKit.vbox(10)
	for i in 2:
		pv.add_child(_player_row(i))
	pc.add_child(pv)
	list.add_child(pc)
	# Board
	var bc := UIKit.panel("Card")
	var bv := UIKit.vbox(8)
	if _code != "":
		bv.add_child(UIKit.label(t("duet_use_code_board"), UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER))
		var cl := UIKit.label(_code, UITheme.FONT_H2, true, UITheme.NAVY, HORIZONTAL_ALIGNMENT_CENTER, false)
		cl.text_direction = Control.TEXT_DIRECTION_LTR
		bv.add_child(cl)
	else:
		bv.add_child(UIKit.label(t("duet_board"), UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER))
		var seg := UIKit.hbox(6)
		for d in StudioBoard.DIFFICULTIES:
			seg.add_child(UIKit.tab_button(t("diff_" + d), FreePlayService.difficulty() == d, func() -> void:
				FreePlayService.set_difficulty(d)
				_rebuild()))
		bv.add_child(seg)
	bc.add_child(bv)
	list.add_child(bc)
	list.add_child(UIKit.label(t("free_play_note"), UITheme.FONT_SMALL, false, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	if FreePlayService.team_wins() > 0:
		list.add_child(UIKit.label(t("duet_team_wins", {"count": FreePlayService.team_wins()}), UITheme.FONT_SMALL, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	for c in list.get_children():
		if c is Label:
			c.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.7))
			c.add_theme_constant_override("outline_size", 5)
	root.add_child(UIKit.scroll(list))
	# Actions
	_status = UIKit.label("", UITheme.FONT_SMALL, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_status.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.7))
	_status.add_theme_constant_override("outline_size", 5)
	_status.visible = false
	root.add_child(_status)
	var resumable := not GameState.session(FreePlayService.SLOT_DUET).is_empty() and _code == ""
	if resumable:
		root.add_child(UIKit.button(t("continue"), "green", "large", func() -> void:
			Router.go("freeplay", {"kind": "duet", "resume": true})))
		_start_btn = UIKit.button(t("duet_new_game"), "cream", "small", _start)
		root.add_child(_start_btn)
	else:
		_start_btn = UIKit.button(t("duet_start"), "green", "large", _start)
		root.add_child(_start_btn)
		UIKit.focus_initial.call_deferred(_start_btn)
	if _code == "":
		root.add_child(UIKit.button(t("duet_play_studio_board"), "cream", "small", func() -> void:
			Router.go("studio", {"tab": "mine"})))


func _player_row(i: int) -> HBoxContainer:
	var row := UIKit.hbox(10)
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.custom_minimum_size = Vector2(UITheme.TOUCH_MIN, UITheme.TOUCH_MIN)
	var tok := TurnBar.token(i + 1, FreePlayService.player_color(i), 44)
	tok.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tok.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tok)
	AccessibilityService.set_access_name(b, t("a11y_player_color", {"n": i + 1}))
	b.pressed.connect(func() -> void:
		AudioService.play("button")
		FreePlayService.set_player_color(i, (FreePlayService.color_index(i) + 1) % DuetTurns.COLORS.size())
		_rebuild())
	row.add_child(b)
	var e := UIKit.text_field(t("player_n", {"n": i + 1}), DuetTurns.NAME_MAX)
	e.text = DuetTurns.clean_name(str(FreePlayService.player(i).get("name", "")))
	AccessibilityService.set_access_name(e, t("a11y_player_name", {"n": i + 1}))
	e.text_changed.connect(func(text: String) -> void: FreePlayService.set_player_name(i, text))
	row.add_child(e)
	return row


func _start() -> void:
	if _busy:
		return
	if _code != "":
		GameState.clear_session(FreePlayService.SLOT_DUET)
		Router.replace("freeplay", {"kind": "duet", "code": _code, "restart": true})
		return
	_busy = true
	if is_instance_valid(_start_btn):
		_start_btn.disabled = true
	if is_instance_valid(_status):
		_status.text = t("board_preparing")
		_status.visible = true
	var d := FreePlayService.difficulty()
	var seed_value := absi(int(Time.get_unix_time_from_system()) * 7919 + Time.get_ticks_usec()) % 1000000
	var params := StudioBoard.preset(d, seed_value)
	Jobs.run(func() -> Dictionary: return StudioBoard.make(params), _on_made.bind(d, 0))


func _on_made(res: Variant, d: String, tries: int) -> void:
	if not is_inside_tree():
		return
	if typeof(res) != TYPE_DICTIONARY or not bool(res.get("ok", false)):
		if tries < 3:
			var params := StudioBoard.preset(d, Time.get_ticks_usec() % 1000000)
			Jobs.run(func() -> Dictionary: return StudioBoard.make(params), _on_made.bind(d, tries + 1))
			return
		_busy = false
		_rebuild()
		Router.toast(t("studio_impossible"), 3.0)
		return
	StudioBoard.remember(res.level)
	GameState.clear_session(FreePlayService.SLOT_DUET)
	Router.replace("freeplay", {"kind": "duet", "code": str(res.code), "difficulty": d, "restart": true})


func on_back() -> bool:
	Router.back()
	return true
