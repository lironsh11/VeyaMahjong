extends Screen
## Main gameplay: minimal HUD, the board as the hero, and an icon+text toolbar
## (Shuffle / Hint / Undo) that is always free. No timers gate anything; the optional clock
## is a personal statistic hidden by default.
##
## Params: {"mode": "level", "level": int, "restart": bool}  |  {"mode": "daily", "date": "YYYY-MM-DD"}
## If the saved active session matches the requested board it is resumed exactly.

var mode: String = "level"
var date: String = ""
var level: LevelDefinition
var session: GameSession
var controller: BoardController
var board: BoardView
var _hud_tiles: Label
var _hud_timer: Label
var _progress: ProgressBar
var _btn_undo: Button
var _btn_hint: Button
var _btn_shuffle: Button
var _banner: PanelContainer
var _banner_label: Label
var _won: bool = false
var _resumed: bool = false
var _timer_accum: float = 0.0


func _ready() -> void:
	if not _init_session():
		Router.toast(LocalizationService.t("error_level_unavailable"))
		Router.replace.call_deferred("home")
		return
	super._ready()
	controller.start_clock()
	AudioService.play_world_music(level.world if level.world != "" else "aurora_garden")
	ContentService.active_world = level.world
	ContentService.active_theme = ProgressionService.equipped_theme()
	set_process(true)


func _init_session() -> bool:
	var p := Router.params
	mode = str(p.get("mode", "level"))
	var saved := GameState.active_session()
	if p.get("resume", false) and not saved.is_empty():
		mode = str(saved.get("mode", "level"))
		p = {"mode": mode, "level": int(saved.get("level_id", 0)), "date": str(saved.get("key", "")).trim_prefix("daily:")}
	if mode == "daily":
		date = str(p.get("date", DailyService.today()))
		level = DailyService.board_cached(date)
		if level == null:
			level = DailyService.level_for_key("daily:" + date)
	else:
		level = ContentService.get_level(int(p.get("level", GameState.next_level(ContentService.level_count()))))
	if level == null:
		return false
	session = null
	if not p.get("restart", false) and str(saved.get("key", "")) == level.key:
		session = GameSession.restore(level, saved.get("session", {}))
		_resumed = session != null
	if session == null:
		if not saved.is_empty() and str(saved.get("key", "")) != level.key:
			AnalyticsService.track("level_abandoned", {"level": int(saved.get("level_id", 0)), "progress_pct": 0})
		session = GameSession.start(level)
	controller = BoardController.new(session, mode)
	controller.won.connect(_on_won)
	controller.moves_exhausted.connect(_on_no_moves)
	controller.solvability.connect(_on_solvability)
	controller.hint_result.connect(_on_hint)
	controller.changed.connect(_refresh_hud)
	controller.blocked_tapped.connect(_on_blocked)
	if mode == "daily":
		AnalyticsService.track("daily_started", {"date": date})
	else:
		AnalyticsService.track("level_started", {"level": level.id, "world": level.world, "resumed": _resumed})
	controller.save()
	return true


func build_background() -> void:
	var low := AccessibilityService.low_profile
	var bg := ContentService.world_bg(level.world if level.world != "" else "aurora_garden", "gameplay", low)
	var soften := bool(GameState.setting("soften_background")) or UITheme.high_contrast
	UIKit.fullscreen_bg(self, bg, 0.35 if soften else 0.06, Color(UITheme.NAVY) if soften else Color.WHITE)


func build() -> void:
	var root := UIKit.vbox(8)
	safe.add_child(root)
	# --- HUD ---
	var hud := UIKit.hbox(10)
	hud.add_child(UIKit.icon_button("pause", t("a11y_pause"), _open_pause, 60))
	var titles := UIKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_text := t("daily_puzzle") if mode == "daily" else t("level_n", {"level": level.id})
	var tl := UIKit.label(title_text, UITheme.FONT_H2 + 2, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	tl.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.75))
	tl.add_theme_constant_override("outline_size", 6)
	titles.add_child(tl)
	var sub := LocalizationService.format_date(date) if mode == "daily" else t(ContentService.world_name_key(level.world))
	var sl := UIKit.label(sub, UITheme.FONT_SMALL, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	sl.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.7))
	sl.add_theme_constant_override("outline_size", 5)
	titles.add_child(sl)
	hud.add_child(titles)
	var pill := UIKit.panel("HudPill")
	pill.custom_minimum_size = Vector2(60, 56)
	var pv := UIKit.vbox(0)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_tiles = UIKit.label("", UITheme.FONT_BODY, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	pv.add_child(_hud_tiles)
	_hud_timer = UIKit.label("", UITheme.FONT_SMALL, false, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, false)
	_hud_timer.visible = bool(GameState.setting("show_timer"))
	pv.add_child(_hud_timer)
	pill.add_child(pv)
	hud.add_child(pill)
	root.add_child(hud)
	_progress = UIKit.progress_bar(0, 100, 12)
	root.add_child(_progress)
	# --- stuck banner (only when the solver PROVES the board is no longer clearable) ---
	_banner = UIKit.panel("CardFlat")
	_banner.visible = false
	var bh := UIKit.hbox(8)
	_banner_label = UIKit.label(t("stuck_banner"), UITheme.FONT_SMALL, true)
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(_banner_label)
	bh.add_child(UIKit.button(t("options"), "gold", "small", func() -> void: _open_rescue(false)))
	_banner.add_child(bh)
	root.add_child(_banner)
	# --- board ---
	board = BoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AccessibilityService.set_access_name(board, t("a11y_board"))
	root.add_child(board)
	board.setup(session.state, ProgressionService.equipped_theme())
	controller.attach_view(board)
	board.input_enabled = not _won
	# --- toolbar ---
	var bar := UIKit.panel("Toolbar")
	var bh2 := UIKit.hbox(4)
	bh2.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_shuffle = UIKit.tool_button("shuffle", t("shuffle"), true, 38, _on_shuffle_pressed)
	_btn_hint = UIKit.tool_button("hint", t("hint"), true, 38, _on_hint_pressed)
	_btn_undo = UIKit.tool_button("undo", t("undo"), true, 38, _on_undo_pressed)
	(_btn_undo.get_node("Box/Icon") as TextureRect).flip_h = LocalizationService.is_rtl()
	for b in [_btn_shuffle, _btn_hint, _btn_undo]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(90, 80)
		bh2.add_child(b)
	bar.add_child(bh2)
	root.add_child(bar)
	_refresh_hud()
	_banner.visible = controller.dead_known
	if _resumed and session.history.size() > 0 and not session.has_moves() and not session.completed:
		_on_no_moves.call_deferred()


func _process(delta: float) -> void:
	if _hud_timer == null or not _hud_timer.visible:
		return
	_timer_accum += delta
	if _timer_accum >= 0.5:
		_timer_accum = 0.0
		_hud_timer.text = _fmt_time(controller.elapsed_ms())


static func _fmt_time(ms: int) -> String:
	var s := ms / 1000
	return "%d:%02d" % [s / 60, s % 60]


func _refresh_hud() -> void:
	if _hud_tiles == null or not is_instance_valid(_hud_tiles):
		return
	_hud_tiles.text = LocalizationService.format_number(session.state.remaining)
	AccessibilityService.set_access_name(_hud_tiles, t("tiles_left", {"count": session.state.remaining}))
	_progress.value = session.progress() * 100.0
	_btn_undo.disabled = not session.can_undo()
	_btn_undo.tooltip_text = t("undo") if session.can_undo() else t("undo_nothing")
	_btn_undo.modulate.a = 1.0 if session.can_undo() else 0.45
	_hud_timer.text = _fmt_time(controller.elapsed_ms())
	if not controller.dead_known and _banner:
		_banner.visible = false


# --- toolbar -------------------------------------------------------------------------

func _on_undo_pressed() -> void:
	if not controller.undo():
		Router.toast(t("undo_nothing"))


func _on_hint_pressed() -> void:
	if session.completed:
		return
	if not session.has_moves():
		_on_no_moves()
		return
	controller.request_hint()


func _on_hint(res: Dictionary) -> void:
	AnalyticsService.track("hint_used", {"level": level.id, "safe": bool(res.get("safe", false))})
	if res.get("pair") == null:
		_on_no_moves()
	elif res.get("dead", false):
		Router.toast(t("hint_dead"), 3.5)
	elif not res.get("safe", false):
		Router.toast(t("hint_unverified"), 3.0)


func _on_shuffle_pressed() -> void:
	_do_shuffle(false)


func _do_shuffle(from_rescue: bool) -> void:
	var res := controller.shuffle()
	if res.ok:
		_banner.visible = false
		if from_rescue:
			AnalyticsService.track("level_rescued", {"level": level.id, "method": "shuffle"})
		_refresh_hud()
		return
	_open_shuffle_failed()


func _on_blocked(_i: int) -> void:
	# Explain the rule once per session in a gentle way (restrained feedback otherwise).
	if not has_meta("explained_block"):
		set_meta("explained_block", true)
		Router.toast(t("tile_blocked_help"), 3.0)


func _on_solvability(status: String) -> void:
	if _banner == null:
		return
	_banner.visible = status == "dead" and not session.completed


# --- dialogs -------------------------------------------------------------------------

func _open_pause() -> void:
	controller.stop_clock()
	var m := ModalDialog.open(self, t("pause"))
	m.add_action(t("resume"), "resume", "green")
	m.add_action(t("restart"), "restart", "cream", "small")
	m.add_action(t("settings"), "settings", "cream", "small")
	m.add_action(t("home"), "home", "cream", "small")
	m.closed.connect(_on_pause_closed)


func _on_pause_closed(r: String) -> void:
	match r:
		"restart":
			_confirm_restart()
		"settings":
			controller.save()
			Router.go("settings")
		"home":
			controller.save()
			Router.reset_to("home")
		_:
			controller.start_clock()


func _confirm_restart() -> void:
	var m := ModalDialog.open(self, t("restart_confirm_title"), t("restart_confirm_body"))
	m.add_action(t("restart"), "yes", "rose")
	m.add_action(t("cancel"), "no", "cream", "small")
	m.closed.connect(func(r: String) -> void:
		if r == "yes":
			GameState.clear_active_session()
			var p := {"mode": mode, "level": level.id, "date": date, "restart": true}
			Router.replace("gameplay", p)
		else:
			controller.start_clock())


func _on_no_moves() -> void:
	if session.completed:
		return
	AnalyticsService.track("no_moves_encountered", {"level": level.id, "remaining": session.state.remaining})
	_open_rescue(true)


func _open_rescue(no_moves: bool) -> void:
	var title := t("no_moves") if no_moves else t("stuck_title")
	var m := ModalDialog.open(self, title, t("rescue_body"))
	m.add_action(t("shuffle_free"), "shuffle", "green")
	if session.can_undo():
		m.add_action(t("undo"), "undo", "cream", "small")
	m.add_action(t("restart"), "restart", "cream", "small")
	m.closed.connect(_on_rescue_closed)


func _on_rescue_closed(r: String) -> void:
	match r:
		"shuffle":
			_do_shuffle(true)
		"undo":
			controller.undo()
		"restart":
			_confirm_restart()


func _open_shuffle_failed() -> void:
	var m := ModalDialog.open(self, t("shuffle_failed_title"), t("shuffle_failed_body"))
	if session.checkpoint < session.history.size():
		m.add_action(t("rewind_checkpoint"), "rewind", "green")
	m.add_action(t("restart"), "restart", "cream", "small")
	m.closed.connect(_on_shuffle_failed_closed)


func _on_shuffle_failed_closed(r: String) -> void:
	match r:
		"rewind":
			var n := controller.undo_to_checkpoint()
			AnalyticsService.track("level_rescued", {"level": level.id, "method": "rewind"})
			Router.toast(t("rewound_n", {"count": n}))
		"restart":
			_confirm_restart()


# --- winning -------------------------------------------------------------------------

func _on_won() -> void:
	if _won:
		return
	_won = true
	board.input_enabled = false
	var stats: Dictionary = session.stats.duplicate()
	stats.elapsed_ms = controller.elapsed_ms()
	var result: Dictionary
	# Progress is committed BEFORE any celebration so nothing can be lost.
	if mode == "daily":
		result = ProgressionService.complete_daily(date, stats)
		AnalyticsService.track("daily_completed", {"date": date, "first_time": bool(result.first_time)})
	else:
		result = ProgressionService.complete_level(level.id, stats)
		AdsService.on_level_finished()
		AnalyticsService.track("level_completed", {"level": level.id, "moves": int(stats.moves), "hints": int(stats.hints), "undos": int(stats.undos), "shuffles": int(stats.shuffles), "first_time": bool(result.first_time)})
	DailyService.record_board_complete(int(stats.hints), mode == "daily")
	GameState.clear_active_session()
	GameState.save_now()
	AudioService.play("victory")
	AccessibilityService.haptic("win")
	board.play_win_fx()
	var delay := 0.05 if AccessibilityService.reduced_motion() else 0.75
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_inside_tree():
			_open_win(result, stats))


func _open_win(result: Dictionary, stats: Dictionary) -> void:
	var title := t("daily_solved") if mode == "daily" else t("level_complete")
	var m := ModalDialog.open(self, title, t("beautiful"), false)
	var box := UIKit.vbox(10)
	if result.light_awarded:
		var row := UIKit.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UIKit.texrect(ContentService.tex("ui/rewards/light.png"), Vector2(44, 44)))
		row.add_child(UIKit.label(t("light_earned"), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER, false))
		box.add_child(row)
		AudioService.play("reward")
	elif not result.first_time:
		box.add_child(UIKit.label(t("replay_no_light"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	if bool(GameState.setting("show_timer")):
		box.add_child(UIKit.label(t("time_taken", {"time": _fmt_time(int(stats.elapsed_ms))}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	for d in result.discoveries:
		box.add_child(UIKit.label(t("discovery_unlocked", {"name": t("disc_" + str(d.sprite))}), UITheme.FONT_BODY, true, UITheme.VIOLET, HORIZONTAL_ALIGNMENT_CENTER))
	var np: Vector2i = result.next_progress
	if np.x >= 0 and result.discoveries.is_empty():
		box.add_child(UIKit.label(t("lights_to_next", {"count": np.y - np.x, "have": np.x, "need": np.y}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
		box.add_child(UIKit.progress_bar(np.x, np.y, 14))
	for th in result.themes:
		box.add_child(UIKit.label(t("collection_unlocked") + " " + t("theme_" + str(th)), UITheme.FONT_BODY, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER))
	if str(result.get("world_unlocked", "")) != "":
		box.add_child(UIKit.label(t("world_unlock") + " " + t(ContentService.world_name_key(result.world_unlocked)), UITheme.FONT_BODY, true, UITheme.BLUE, HORIZONTAL_ALIGNMENT_CENTER))
		AudioService.play("world_unlock")
	m.add_content(box)
	if mode == "daily":
		m.add_action(t("back_to_daily"), "daily", "green")
	elif level.id < ContentService.level_count():
		m.add_action(t("next_level"), "next", "green")
	if not result.discoveries.is_empty():
		m.add_action(t("see_bloom"), "bloom", "gold", "small")
	# Optional rewarded bonus: shown ONLY when a real ad is loaded (never in this build).
	if result.first_time and mode == "level" and AdsService.is_rewarded_ready("bonus_light"):
		m.add_action(t("ad_bonus_light"), "ad", "violet", "small")
	m.add_action(t("home"), "home", "cream", "small")
	m.closed.connect(_on_win_closed.bind(result, stats))


func _on_win_closed(r: String, result: Dictionary, stats: Dictionary) -> void:
	match r:
		"next":
			AdsService.show_interstitial("level_complete_continue", _go_next_level)
		"daily":
			Router.replace("daily")
		"bloom":
			Router.replace("bloom", {"world": str(result.discoveries[0].world)})
		"ad":
			AdsService.show_rewarded("bonus_light", "ad:level:%d" % level.id, _grant_ad_light)
			_open_win(_refreshed_result(), stats)
		_:
			Router.reset_to("home")


func _go_next_level() -> void:
	Router.replace("gameplay", {"mode": "level", "level": level.id + 1})


func _grant_ad_light() -> void:
	ProgressionService.award_light("ad:level:%d" % level.id)


func _refreshed_result() -> Dictionary:
	return {"first_time": false, "light_awarded": false, "discoveries": [], "themes": [], "world_unlocked": "", "next_progress": ProgressionService.lights_progress()}


func on_back() -> bool:
	if _won:
		Router.reset_to("home")
	else:
		_open_pause()
	return true


func save_state() -> void:
	if controller and not _won:
		controller.stop_clock()
		controller.save()
		controller.start_clock()
