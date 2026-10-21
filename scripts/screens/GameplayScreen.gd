extends Screen
## Main gameplay: minimal HUD with the score, the 4-slot tray, the board as the hero, and an
## icon+text toolbar (Shuffle / Hint / Undo) backed by the booster economy (EconomyService +
## AssistPolicy): each button shows how many the player owns; the first undos of a board, one
## rescue shuffle when the board is proven stuck, the first "send tiles back" after a full
## tray, rewinding to the last solvable point and restarting are free, so a board can never
## be locked behind a price. No timers gate anything; the optional clock is a personal
## statistic hidden by default.
##
## Params: {"mode": "level", "level": int, "restart": bool}  |  {"mode": "daily", "date": "YYYY-MM-DD"}
## If the saved active session matches the requested board it is resumed exactly.

var mode: String = "level"
var date: String = ""
var level: LevelDefinition
var session: GameSession
var controller: BoardController
var board: BoardView
var tray: TrayView
var _hud_tiles: Label
var _hud_score: Label
var _hud_streak: Control
var _hud_timer: Label
var _progress: ProgressBar
var _btn_undo: Button
var _btn_hint: Button
var _btn_shuffle: Button
var _banner: PanelContainer
var _banner_label: Label
var _won: bool = false
var _resumed: bool = false
var _dealt: bool = false
var _timer_accum: float = 0.0


func _ready() -> void:
	if not _init_session():
		Router.toast(LocalizationService.t("error_level_unavailable"))
		Router.replace.call_deferred("home")
		return
	# No bottom banner while playing: the board gets the whole screen (owner request).
	AdsService.set_banner_suppressed(true)
	set_meta("banner_suppressed", true)
	super._ready()
	EconomyService.inventory_changed.connect(_on_inventory_changed)
	AdsService.on_level_started()
	controller.start_clock()
	if has_meta("pre_level"):
		remove_meta("pre_level")
		_open_level_start.call_deferred()
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
		if mode == "level":
			_start_fresh_attempt()
	controller = BoardController.new(session, mode)
	controller.won.connect(_on_won)
	controller.tray_failed.connect(_on_tray_failed)
	controller.matched.connect(_on_matched)
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


func _start_fresh_attempt() -> void:
	## A new attempt at a level: a second fresh start of the same new level is a retry (it
	## ends the win streak). A running streak of 3+ gives this board a free extra slot.
	if ProgressionService.start_attempt(level.id):
		session.assists.retry = 1
	elif ProgressionService.streak_bonus_active() and not GameState.is_level_completed(level.id):
		session.add_slot()
		session.assists.streak_slot = 1
	if session.assists.streak_slot == 1 or (_economy_on() and EconomyService.count("extra_slot") > 0):
		set_meta("pre_level", true)


func _streak_applies() -> bool:
	## The streak only counts first clears of levels (never the daily or replays).
	return mode == "level" and not GameState.is_level_completed(level.id)


func build_background() -> void:
	var low := AccessibilityService.low_profile
	var bg := ContentService.world_bg(level.world if level.world != "" else "aurora_garden", "gameplay", low)
	var soften := bool(GameState.setting("soften_background")) or UITheme.high_contrast
	UIKit.fullscreen_bg(self, bg, 0.35 if soften else 0.06, Color(UITheme.NAVY) if soften else Color.WHITE)


func build() -> void:
	var root := UIKit.vbox(4)
	safe.add_child(root)
	# --- HUD ---
	# Compact HUD (52 px): every pixel saved goes to the board.
	var hud := UIKit.hbox(8)
	hud.add_child(UIKit.icon_button("pause", t("a11y_pause"), _open_pause, 52))
	var titles := UIKit.vbox(-4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	var title_text := t("daily_puzzle") if mode == "daily" else t("level_n", {"level": level.id})
	var tl := UIKit.label(title_text, UITheme.FONT_BODY + 1, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	tl.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.75))
	tl.add_theme_constant_override("outline_size", 6)
	titles.add_child(tl)
	_hud_score = UIKit.label("", UITheme.FONT_BODY + 2, true, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, false)
	_hud_score.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.8))
	_hud_score.add_theme_constant_override("outline_size", 6)
	_hud_score.pivot_offset = Vector2(60, 14)
	titles.add_child(_hud_score)
	hud.add_child(titles)
	hud.add_child(UIKit.coin_pill(_open_shop))
	var pill := UIKit.panel("HudPill")
	pill.custom_minimum_size = Vector2(56, 48)
	var pv := UIKit.vbox(0)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_tiles = UIKit.label("", UITheme.FONT_BODY, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	pv.add_child(_hud_tiles)
	_hud_timer = UIKit.label("", UITheme.FONT_SMALL, false, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, false)
	_hud_timer.visible = bool(GameState.setting("show_timer"))
	pv.add_child(_hud_timer)
	pill.add_child(pv)
	hud.add_child(pill)
	if mode == "level" and ProgressionService.streak_count() > 0:
		_hud_streak = UIKit.streak_pill(ProgressionService.streak_count(), 48)
		hud.add_child(_hud_streak)
	root.add_child(hud)
	_progress = UIKit.progress_bar(0, 100, 6)
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
	# --- tray (drawn above the board so picked tiles can fly over it) ---
	tray = TrayView.new()
	tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tray)
	# --- board ---
	board = BoardView.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AccessibilityService.set_access_name(board, t("a11y_board"))
	root.add_child(board)
	board.setup(session.state, ProgressionService.equipped_theme())
	# A newly dealt board flips face-up from the equipped tile back, once per screen (a rebuild
	# for a language or setting change, a resumed board and a won board appear face-up). When the
	# level-start dialog covers the board, the tiles stay face-down until it closes.
	var back := ProgressionService.equipped_back()
	if back != "" and not _dealt and not _resumed and not _won:
		board.play_deal(ContentService.tile_back_texture(back), has_meta("pre_level"))
	_dealt = true
	controller.attach_view(board, tray)
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
		b.custom_minimum_size = Vector2(90, 72)
		bh2.add_child(b)
	bar.add_child(bh2)
	root.add_child(bar)
	_refresh_hud()
	_banner.visible = controller.dead_known
	tray.set_danger(session.tray_danger() and not session.failed)
	if session.failed and not session.completed and not has_meta("fail_open"):
		_open_fail.call_deferred()


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
	_hud_tiles.text = LocalizationService.format_number(session.tiles_left())
	AccessibilityService.set_access_name(_hud_tiles, t("tiles_left", {"count": session.tiles_left()}))
	_hud_score.text = LocalizationService.format_number(session.score)
	AccessibilityService.set_access_name(_hud_score, t("score_n", {"score": session.score}))
	_progress.value = session.progress() * 100.0
	_btn_undo.disabled = not session.can_undo()
	_btn_undo.tooltip_text = t("undo") if session.can_undo() else t("undo_nothing")
	_btn_undo.modulate.a = 1.0 if session.can_undo() else 0.45
	_hud_timer.text = _fmt_time(controller.elapsed_ms())
	if not controller.dead_known and _banner:
		_banner.visible = false
	_refresh_badges()


func _economy_on() -> bool:
	return not EconomyService.helpers_free()


func _refresh_badges() -> void:
	if _btn_hint == null or not is_instance_valid(_btn_hint):
		return
	if not _economy_on():
		for b in [_btn_shuffle, _btn_hint, _btn_undo]:
			UIKit.set_tool_badge(b, "", "")
		return
	_set_count_badge(_btn_hint, EconomyService.count("hint"))
	_set_count_badge(_btn_shuffle, EconomyService.count("shuffle"))
	if AssistPolicy.free_undos_left(session.assists, EconomyService.free_undos_per_board()) > 0:
		UIKit.set_tool_badge(_btn_undo, t("badge_free"), "BadgeGreen")
	else:
		_set_count_badge(_btn_undo, EconomyService.count("undo"))


func _set_count_badge(b: Button, n: int) -> void:
	if n > 0:
		UIKit.set_tool_badge(b, LocalizationService.format_number(n), "BadgeGold")
	else:
		UIKit.set_tool_badge(b, "+", "BadgeRed")


func _on_inventory_changed(_item: String) -> void:
	_refresh_badges()


func _exit_tree() -> void:
	if EconomyService.inventory_changed.is_connected(_on_inventory_changed):
		EconomyService.inventory_changed.disconnect(_on_inventory_changed)
	if has_meta("banner_suppressed"):
		remove_meta("banner_suppressed")
		AdsService.set_banner_suppressed(false)


# The board is the hero: thin margins so wide boards can use the whole width.
func side_pad() -> int:
	return 6


func top_pad() -> int:
	return 8


func bottom_pad() -> int:
	return 6


func _open_shop() -> void:
	if _won:
		return
	controller.stop_clock()
	controller.save()
	AnalyticsService.track("shop_opened", {"from": "gameplay"})
	Router.go("shop")


func _track_booster(item: String, free: bool) -> void:
	AnalyticsService.track("booster_used", {"item": item, "level": level.id, "free": free})


# --- toolbar -------------------------------------------------------------------------

func _on_undo_pressed() -> void:
	if not session.can_undo():
		Router.toast(t("undo_nothing"))
		return
	var cost := AssistPolicy.undo_cost(session.assists, EconomyService.free_undos_per_board(), EconomyService.count("undo"), _economy_on())
	if not cost.allowed:
		_open_get_more("undo")
		return
	if not controller.undo():
		return
	if cost.free:
		session.assists.free_undos_used = int(session.assists.free_undos_used) + 1
	else:
		EconomyService.consume("undo")
	controller.save()
	_track_booster("undo", cost.free)
	_refresh_badges()


func _on_hint_pressed() -> void:
	if session.completed:
		return
	if session.failed:
		_open_fail()
		return
	if _economy_on() and EconomyService.count("hint") <= 0 and not controller.can_repeat_hint():
		_open_get_more("hint")
		return
	controller.request_hint()


func _on_hint(res: Dictionary) -> void:
	var charged := AssistPolicy.hint_should_charge(res, _economy_on())
	if charged:
		EconomyService.consume("hint")
		controller.save()
		_track_booster("hint", false)
	AnalyticsService.track("hint_used", {"level": level.id, "safe": bool(res.get("safe", false)), "charged": charged})
	if PackedInt32Array(res.get("tiles", [])).is_empty():
		if session.failed:
			_open_fail()
	elif res.get("dead", false):
		Router.toast(t("hint_dead"), 3.5)
	elif not res.get("safe", false) and not res.get("repeat", false):
		Router.toast(t("hint_unverified"), 3.0)


func _on_shuffle_pressed() -> void:
	_try_shuffle(false)


func _shuffle_cost() -> Dictionary:
	return AssistPolicy.shuffle_cost(session.assists, EconomyService.free_rescue_shuffles_per_board(), controller.dead_known, EconomyService.count("shuffle"), _economy_on())


func _try_shuffle(from_rescue: bool) -> void:
	var cost := _shuffle_cost()
	if not cost.allowed:
		_open_get_more("shuffle", from_rescue)
		return
	_do_shuffle(from_rescue, cost.free)


func _do_shuffle(from_rescue: bool, free: bool) -> void:
	var res := controller.shuffle()
	if res.ok:
		# Charged only for a shuffle that actually happened.
		if free:
			if _economy_on():
				session.assists.rescue_shuffles_used = int(session.assists.rescue_shuffles_used) + 1
		else:
			EconomyService.consume("shuffle")
		controller.save()
		_track_booster("shuffle", free)
		_banner.visible = false
		if from_rescue:
			AnalyticsService.track("level_rescued", {"level": level.id, "method": "shuffle"})
		_refresh_hud()
		return
	_open_shuffle_failed()


func _open_get_more(item: String, rescue: bool = false) -> void:
	controller.stop_clock()
	var can_rewind := rescue and session.checkpoint < session.history.size()
	var m := GetMoreDialog.open(self, item, can_rewind, rescue)
	m.closed.connect(_on_get_more_closed)


func _on_get_more_closed(r: String) -> void:
	match r:
		"shop":
			_open_shop()
		"rewind":
			_rewind()
		"restart":
			_confirm_restart()
		_:
			controller.start_clock()
			_refresh_badges()


func _rewind() -> void:
	var n := controller.undo_to_checkpoint()
	AnalyticsService.track("level_rescued", {"level": level.id, "method": "rewind"})
	Router.toast(t("rewound_n", {"count": n}))
	controller.start_clock()


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
	if _streak_applies() and ProgressionService.streak_count() > 0:
		# Honest warning: a fresh restart of a new level ends the win streak.
		m.add_content(_streak_warning(t("restart_ends_streak", {"count": ProgressionService.streak_count()})))
	m.add_action(t("restart"), "yes", "rose")
	m.add_action(t("cancel"), "no", "cream", "small")
	m.closed.connect(func(r: String) -> void:
		if r == "yes":
			GameState.clear_active_session()
			var p := {"mode": mode, "level": level.id, "date": date, "restart": true}
			Router.replace("gameplay", p)
		else:
			controller.start_clock())


func _on_matched(_tile: int, _partner: int, combo: int, _points: int) -> void:
	tray.show_combo(combo, BoardController.COMBO_WINDOW_MS / 1000.0)
	# No board jolt on big combos (owner request 2026-10-20: the other tiles shaking felt bad).
	if not AccessibilityService.reduced_motion() and _hud_score:
		var tw := _hud_score.create_tween()
		tw.tween_property(_hud_score, "scale", Vector2(1.18, 1.18), 0.08)
		tw.tween_property(_hud_score, "scale", Vector2.ONE, 0.12)


func _streak_warning(text: String) -> Control:
	var h := UIKit.hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(StreakFlame.make(24.0, false))
	var l := UIKit.label(text, UITheme.FONT_SMALL, true, UITheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size.x = 320
	h.add_child(l)
	return h


func _on_tray_failed() -> void:
	if _streak_applies():
		var lost := ProgressionService.break_streak("fail")
		if lost > 0:
			set_meta("streak_lost", lost)
			if is_instance_valid(_hud_streak):
				_hud_streak.visible = false
	var delay := 0.05 if AccessibilityService.reduced_motion() else 0.7
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_inside_tree() and session.failed:
			_open_fail())


func _open_fail() -> void:
	## The tray is full. Ways forward, the free one first: send the newest tiles back to the
	## board (first time per board free, then coins), undo, try again, or leave. Never a
	## dead end and always a plain way out.
	if has_meta("fail_open") or not session.failed:
		return
	set_meta("fail_open", true)
	controller.stop_clock()
	AnalyticsService.track("tray_full_dialog", {"level": level.id, "continues_used": int(session.assists.continues_used)})
	var m := ModalDialog.open(self, t("tray_full_title"), t("tray_full_body"), false)
	if has_meta("streak_lost"):
		m.add_content(_streak_warning(t("streak_lost", {"count": int(get_meta("streak_lost"))})))
	var cc := AssistPolicy.continue_cost(session.assists, EconomyService.continue_costs(), EconomyService.coins(), _economy_on())
	# An owned Extra Slot keeps every tile where it is: offered first when there is one.
	if session.capacity < GameSession.MAX_CAPACITY and (not _economy_on() or EconomyService.count("extra_slot") > 0):
		var label := t("use_extra_slot") if not _economy_on() else t("use_extra_slot_n", {"count": EconomyService.count("extra_slot")})
		m.add_action(label, "slot", "green")
	if cc.free:
		m.add_action(t("send_back_free", {"count": SEND_BACK}), "send_back", "green")
	elif cc.allowed:
		m.add_action(t("send_back_coins", {"count": SEND_BACK, "coins": int(cc.coins)}), "send_back", "green")
	else:
		m.add_action(t("send_back_coins", {"count": SEND_BACK, "coins": int(cc.coins)}), "shop", "gold")
	if session.can_undo():
		m.add_action(t("undo"), "undo", "cream", "small")
	m.add_action(t("try_again"), "restart", "cream", "small")
	m.add_action(t("home"), "home", "cream", "small")
	m.closed.connect(_on_fail_closed.bind(cc))


const SEND_BACK := 3


func _on_fail_closed(r: String, cc: Dictionary) -> void:
	remove_meta("fail_open")
	match r:
		"slot":
			if not _use_extra_slot():
				_open_fail()
				return
			controller.start_clock()
		"send_back":
			if not cc.free and not EconomyService.spend_coins(int(cc.coins), "continue"):
				_open_fail()
				return
			controller.send_back(SEND_BACK)
			session.assists.continues_used = int(session.assists.continues_used) + 1
			controller.save()
			AnalyticsService.track("level_continued", {"level": level.id, "free": bool(cc.free), "coins": int(cc.coins)})
			controller.start_clock()
			_refresh_hud()
		"shop":
			_open_shop()
		"undo":
			_on_undo_pressed()
			controller.start_clock()
			if session.failed:
				_open_fail()
		"restart":
			AnalyticsService.track("level_failed_restart", {"level": level.id})
			GameState.clear_active_session()
			Router.replace("gameplay", {"mode": mode, "level": level.id, "date": date, "restart": true})
		_:
			controller.save()
			Router.reset_to("home")


func _use_extra_slot() -> bool:
	## Spends one Extra Slot booster (free when the economy is off) for one more tray slot.
	if session.capacity >= GameSession.MAX_CAPACITY:
		return false
	if _economy_on() and not EconomyService.consume("extra_slot"):
		return false
	if not controller.add_slot():
		return false
	session.assists.extra_slots_used = int(session.assists.extra_slots_used) + 1
	controller.save()
	_track_booster("extra_slot", not _economy_on())
	_refresh_hud()
	return true


func _open_level_start() -> void:
	## Before a new board: the streak bonus (if any) and the option to add an Extra Slot.
	## "Play" without a booster is the default, and closing the dialog just plays.
	if not is_inside_tree() or session.history.size() > 0 or _won:
		if board != null:
			board.release_deal()
		return
	controller.stop_clock()
	var m := ModalDialog.open(self, t("level_n", {"level": level.id}))
	var box := UIKit.vbox(10)
	if int(session.assists.streak_slot) == 1:
		var row := UIKit.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(StreakFlame.make(34.0))
		var l := UIKit.label(t("streak_bonus_slot", {"count": ProgressionService.streak_count()}), UITheme.FONT_BODY, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size.x = 300
		row.add_child(l)
		box.add_child(row)
	var owned := EconomyService.count("extra_slot")
	var can_add := session.capacity < GameSession.MAX_CAPACITY and owned > 0
	if can_add:
		box.add_child(UIKit.label(t("extra_slot_desc"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	m.add_content(box)
	if can_add:
		m.add_action(t("play_with_extra_slot", {"count": owned}), "slot", "gold")
	m.add_action(t("play"), "play", "green")
	m.closed.connect(func(r: String) -> void:
		if r == "slot":
			_use_extra_slot()
		controller.start_clock()
		board.release_deal())


func _open_rescue(no_moves: bool) -> void:
	## Free ways forward first: the free rescue shuffle (board proven stuck), then rewinding to
	## the last solvable point; paid helpers after; restart always.
	var title := t("no_moves") if no_moves else t("stuck_title")
	var m := ModalDialog.open(self, title, t("rescue_body"))
	var sc := _shuffle_cost()
	if sc.free:
		m.add_action(t("shuffle_free"), "shuffle", "green")
	elif sc.allowed:
		m.add_action("%s (%s)" % [t("shuffle"), LocalizationService.format_number(EconomyService.count("shuffle"))], "shuffle", "green")
	if session.checkpoint < session.history.size():
		m.add_action(t("rewind_free"), "rewind", "green" if not sc.allowed else "cream", "small")
	if not sc.allowed:
		m.add_action(t("get_shuffles"), "get_shuffle", "gold", "small")
	if session.can_undo():
		m.add_action(t("undo"), "undo", "cream", "small")
	m.add_action(t("restart"), "restart", "cream", "small")
	m.closed.connect(_on_rescue_closed)


func _on_rescue_closed(r: String) -> void:
	match r:
		"shuffle":
			_try_shuffle(true)
		"get_shuffle":
			_open_get_more("shuffle", true)
		"rewind":
			_rewind()
		"undo":
			_on_undo_pressed()
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
			_rewind()
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
	var fin := Scoring.final(session.score, level.tiles.size(), session.stats)
	stats.score = int(fin.score)
	stats.clean_bonus = int(fin.bonus)
	stats.stars = int(fin.stars)
	stats.retry = int(session.assists.retry)
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
	tray.celebrate()
	var delay := 0.05 if AccessibilityService.reduced_motion() else 0.75
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_inside_tree():
			_open_win(result, stats))


func _open_win(result: Dictionary, stats: Dictionary) -> void:
	var title := t("daily_solved") if mode == "daily" else t("level_complete")
	var m := ModalDialog.open(self, title, t("beautiful"), false)
	var box := UIKit.vbox(10)
	_add_stars(box, int(stats.get("stars", 1)))
	_add_score_row(box, int(stats.get("score", session.score)), int(stats.get("best_combo", 0)))
	if int(stats.get("clean_bonus", 0)) > 0:
		box.add_child(UIKit.label(t("clean_bonus", {"count": int(stats.clean_bonus)}), UITheme.FONT_SMALL, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER, false))
	if bool(result.get("new_best", false)):
		box.add_child(UIKit.label(t("new_best_score"), UITheme.FONT_SMALL, true, UITheme.VIOLET, HORIZONTAL_ALIGNMENT_CENTER, false))
	_add_streak_rows(box, result)
	if result.light_awarded:
		var row := UIKit.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UIKit.texrect(ContentService.tex("ui/rewards/light.png"), Vector2(44, 44)))
		row.add_child(UIKit.label(t("light_earned"), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER, false))
		box.add_child(row)
		AudioService.play("reward")
	elif not result.first_time:
		box.add_child(UIKit.label(t("replay_no_light"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	_add_coin_rows(box, result)
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
	for back in result.get("backs", []):
		var brow := UIKit.hbox(10)
		brow.alignment = BoxContainer.ALIGNMENT_CENTER
		brow.add_child(UIKit.texrect(ContentService.tile_back_texture(str(back)), Vector2(36, 45)))
		brow.add_child(UIKit.label(t("tile_back_unlocked", {"world": t(ContentService.world_name_key(str(back)))}), UITheme.FONT_BODY, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER))
		box.add_child(brow)
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
	m.add_action(t("home"), "home", "cream", "small")
	m.closed.connect(_on_win_closed.bind(result, stats))


func _on_win_closed(r: String, result: Dictionary, stats: Dictionary) -> void:
	match r:
		"next":
			# The continue callback lives on an autoload, so it is safe even if this screen is
			# gone by the time the ad closes.
			AdsService.show_interstitial("level_complete_continue", level.id,
				Router.replace.bind("gameplay", {"mode": "level", "level": level.id + 1}))
		"daily":
			Router.replace("daily")
		"bloom":
			Router.replace("bloom", {"world": str(result.discoveries[0].world)})
		_:
			Router.reset_to("home")


func _add_stars(box: VBoxContainer, n: int) -> void:
	## Earned stars pop in one after another (static under Reduced Motion).
	var row := UIKit.stars_row(n, 54.0)
	box.add_child(row)
	if AccessibilityService.reduced_motion():
		return
	for k in n:
		var s: TextureRect = row.get_node("Star%d" % k)
		s.scale = Vector2.ZERO
		var tw := s.create_tween()
		tw.tween_interval(0.15 + k * 0.22)
		tw.tween_callback(func() -> void: AudioService.play("soft_pop", 1.0 + k * 0.12))
		tw.tween_property(s, "scale", Vector2(1.25, 1.25), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "scale", Vector2.ONE, 0.08)


func _add_streak_rows(box: VBoxContainer, result: Dictionary) -> void:
	var n := int(result.get("streak", 0))
	if n <= 0:
		return
	var row := UIKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(StreakFlame.make(30.0))
	row.add_child(UIKit.label(t("streak_n", {"count": n}), UITheme.FONT_BODY, true, Color("D9731C"), HORIZONTAL_ALIGNMENT_CENTER, false))
	box.add_child(row)
	var gift: Dictionary = result.get("streak_gift", {})
	for item in gift:
		box.add_child(UIKit.label(t("streak_gift", {"item": t(str(item)), "count": int(gift[item])}), UITheme.FONT_SMALL, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER, false))
	if n == ProgressionService.STREAK_SLOT_AT:
		box.add_child(UIKit.label(t("streak_slot_unlocked"), UITheme.FONT_SMALL, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER))


func _add_score_row(box: VBoxContainer, score: int, best_combo: int) -> void:
	## The score counts up when the dialog opens (static under Reduced Motion).
	var l := UIKit.label(t("score_n", {"score": LocalizationService.format_number(score)}), UITheme.FONT_TITLE, true, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, false)
	l.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	box.add_child(l)
	if best_combo >= 2:
		box.add_child(UIKit.label(t("best_combo", {"count": best_combo}), UITheme.FONT_SMALL, true, UITheme.VIOLET, HORIZONTAL_ALIGNMENT_CENTER, false))
	if AccessibilityService.reduced_motion() or score <= 0:
		return
	var tw := l.create_tween()
	tw.tween_method(func(v: float) -> void:
		l.text = t("score_n", {"score": LocalizationService.format_number(int(v))}), 0.0, float(score), 0.9).set_ease(Tween.EASE_OUT)


func _add_coin_rows(box: VBoxContainer, result: Dictionary) -> void:
	var coins := int(result.get("coins", 0))
	if coins <= 0:
		return
	var row := UIKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.texrect(ContentService.icon("coin"), Vector2(34, 34)))
	var amount := UIKit.label(t("coin_reward", {"count": coins}), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER, false)
	row.add_child(amount)
	box.add_child(row)
	var bonus := int(result.get("world_bonus", 0))
	if bonus > 0:
		box.add_child(UIKit.label(t("world_bonus", {"count": bonus}), UITheme.FONT_BODY, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER))
	AudioService.play("coin")
	# Optional: double the level's coins by watching a video (only when a real ad is loaded).
	if not AdsService.is_rewarded_ready("win_double"):
		AdsService.load_rewarded("win_double")
		return
	var key := ("daily:" + date) if mode == "daily" else ("level:%d" % level.id)
	var gid := "ad:win_double:" + key
	var dbl := UIKit.button(t("watch_ad_double"), "violet", "small")
	box.add_child(dbl)
	dbl.pressed.connect(func() -> void:
		dbl.disabled = true
		AdsService.rewarded_result.connect(func(placement: String, status: String) -> void:
			if placement != "win_double":
				return
			if status == "granted":
				if is_instance_valid(amount):
					amount.text = t("coin_reward", {"count": coins * 2})
				if is_instance_valid(dbl):
					dbl.queue_free()
				AudioService.play("coin")
			elif is_instance_valid(dbl):
				if status == "not_completed":
					dbl.disabled = false
				else:
					dbl.visible = false
					Router.toast(t("ad_unavailable")), CONNECT_ONE_SHOT)
		AdsService.show_rewarded("win_double", gid, EconomyService.grant.bind(gid, {"coins": coins}, "ad_win_double")))


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
