extends "res://scripts/screens/GameplayScreen.gd"
## Play Together and Board Studio boards. Everything about the board, the tray, hints, rescue,
## rewinding and resuming is the normal gameplay screen; this screen changes what is around it:
## - Play Together ("duet"): two players take turns on one board and one tray, one tile per
##   turn (DuetTurns). A turn bar shows whose turn it is; a "Pass to …" cue appears over the
##   board for a moment at each change and input pauses briefly, so a quick double tap can't
##   use up the partner's turn. Combos are chains of consecutive matches (BoardController).
## - Board Studio ("studio"): one player plays a Studio board (made or entered as a code).
## - No coins, boosters, ads after the board, Lights, streak or Daily Tasks: each board has a
##   small allowance of free helpers (economy.json free_play_limits), and restart and rewinding
##   to the last solvable point stay available.
##
## Params: {"kind": "duet"|"studio", "code": "LS-…", "difficulty": "easy"|"medium"|"hard"|"",
##          "resume": bool, "restart": bool}

const PASS_CUE_S := 1.2
const INPUT_GUARD_S := 0.35

var kind: String = "duet"
var code: String = ""
var difficulty: String = ""
var first: int = 0
var slot: String = FreePlayService.SLOT_DUET
var _turn_bar: TurnBar
var _shown_player: int = -1
var _guard_until: int = 0


# --- session --------------------------------------------------------------------------

func _init_session() -> bool:
	var p := Router.params
	kind = "studio" if str(p.get("kind", "duet")) == "studio" else "duet"
	slot = FreePlayService.SLOT_STUDIO if kind == "studio" else FreePlayService.SLOT_DUET
	mode = kind
	var saved := GameState.session(slot)
	code = str(p.get("code", ""))
	if p.get("resume", false) and not saved.is_empty():
		code = str(saved.get("code", ""))
	var res := StudioBoard.from_code(code)
	if res.err != StudioCode.Err.OK:
		return false
	code = str(res.code)
	level = res.level
	level.world = _board_world()
	session = null
	if not p.get("restart", false) and str(saved.get("key", "")) == level.key:
		session = GameSession.restore(level, saved.get("session", {}))
		_resumed = session != null
		if _resumed:
			first = clampi(int(saved.get("first", 0)), 0, 1)
			difficulty = str(saved.get("difficulty", ""))
	if session == null:
		session = GameSession.start(level)
		first = FreePlayService.game_started() if kind == "duet" else 0
		difficulty = str(p.get("difficulty", ""))
	controller = BoardController.new(session, mode)
	controller.slot = slot
	controller.extra = {"code": code, "kind": kind, "first": first, "difficulty": difficulty}
	controller.chain_combo = kind == "duet"
	controller.won.connect(_on_won)
	controller.tray_failed.connect(_on_tray_failed)
	controller.matched.connect(_on_matched)
	controller.solvability.connect(_on_solvability)
	controller.hint_result.connect(_on_hint)
	controller.changed.connect(_refresh_hud)
	controller.changed.connect(_on_board_changed)
	controller.blocked_tapped.connect(_on_blocked)
	if kind == "duet":
		AnalyticsService.track("duet_started", {"difficulty": difficulty if difficulty != "" else "board", "resumed": _resumed})
	controller.save()
	return true


func _board_world() -> String:
	## Studio boards have no world: they use the backdrop of the world the player is in.
	var w := str(ContentService.world_for_level(GameState.next_level(ContentService.level_count())).get("id", ""))
	return w if w != "" else "aurora_garden"


func _restart() -> void:
	GameState.clear_session(slot)
	Router.replace("freeplay", {"kind": kind, "code": code, "difficulty": difficulty, "restart": true})


func _title_text() -> String:
	return t("play_together") if kind == "duet" else t("studio_board_title")


func _show_coins() -> bool:
	return false


func _counts_for_ads() -> bool:
	return false


func _economy_on() -> bool:
	return false


func _limits() -> Dictionary:
	return EconomyService.free_play_limits()


func _left(item: String) -> int:
	return AssistPolicy.free_play_left(item, session.assists, _limits())


# --- turns (Play Together) ------------------------------------------------------------

func _after_progress(root: VBoxContainer) -> void:
	if kind != "duet":
		return
	_turn_bar = TurnBar.new()
	_turn_bar.setup([FreePlayService.player_name(0), FreePlayService.player_name(1)],
		[FreePlayService.player_color(0), FreePlayService.player_color(1)])
	root.add_child(_turn_bar)
	_shown_player = -1
	_on_board_changed.call_deferred()


func current_player() -> int:
	return DuetTurns.current_player(session.history, first)


func _on_board_changed() -> void:
	if kind != "duet" or not is_instance_valid(_turn_bar):
		return
	var who := current_player()
	var colors: Array = []
	for owner in DuetTurns.tray_owners(session.history, first, session.tray):
		colors.append(FreePlayService.player_color(owner) if owner >= 0 else null)
	tray.set_slot_marks(colors)
	if who == _shown_player:
		return
	var first_show := _shown_player < 0
	_shown_player = who
	_turn_bar.set_active(who, not first_show)
	if first_show or session.completed or session.failed:
		return
	_guard_input()
	_show_pass_cue(who)
	AccessibilityService.haptic("tap")


func _guard_input() -> void:
	## A short pause after each turn change: a quick double tap can't take the partner's turn.
	board.input_enabled = false
	_guard_until = Time.get_ticks_msec() + int(INPUT_GUARD_S * 1000.0)
	get_tree().create_timer(INPUT_GUARD_S).timeout.connect(func() -> void:
		if is_instance_valid(board) and not _won and Time.get_ticks_msec() >= _guard_until:
			board.input_enabled = true)


func _show_pass_cue(who: int) -> void:
	## "Pass to Noam": over the board, never blocks taps, gone after PASS_CUE_S.
	var pill := UIKit.panel("Card")
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UIKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(TurnBar.token(who + 1, FreePlayService.player_color(who), 34))
	var l := UIKit.label(t("duet_pass_to", {"name": FreePlayService.player_name(who)}), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER, false)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	pill.add_child(h)
	add_child(pill)
	pill.z_index = 20
	pill.reset_size()
	pill.position = Vector2((size.x - pill.size.x) * 0.5, board.global_position.y - global_position.y + board.size.y * 0.42)
	if AccessibilityService.reduced_motion():
		get_tree().create_timer(PASS_CUE_S).timeout.connect(pill.queue_free)
		return
	pill.modulate.a = 0.0
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.12)
	tw.tween_interval(PASS_CUE_S - 0.4)
	tw.tween_property(pill, "modulate:a", 0.0, 0.28)
	tw.tween_callback(pill.queue_free)


func _on_matched(_tile: int, _partner: int, combo: int, _points: int) -> void:
	if kind != "duet":
		super._on_matched(_tile, _partner, combo, _points)
		return
	# The pick that finished the pair was made by the player before the turn passed.
	var who := (current_player() + 1) % 2
	if DuetTurns.is_team_up(session.history, first):
		session.award(DuetTurns.TEAM_UP_BONUS, combo)
		controller.save()
		tray.float_text(t("duet_team_up"), UITheme.GOLD)
		_refresh_hud()
	else:
		tray.float_text(FreePlayService.player_name(who), FreePlayService.player_color(who).lightened(0.35))
	if not AccessibilityService.reduced_motion() and _hud_score:
		var tw := _hud_score.create_tween()
		tw.tween_property(_hud_score, "scale", Vector2(1.18, 1.18), 0.08)
		tw.tween_property(_hud_score, "scale", Vector2.ONE, 0.12)


# --- free helpers (allowance per board, no coins) -------------------------------------

func _refresh_badges() -> void:
	if _btn_hint == null or not is_instance_valid(_btn_hint):
		return
	for pair in [[_btn_hint, "hint"], [_btn_shuffle, "shuffle"], [_btn_undo, "undo"]]:
		var n := _left(pair[1])
		UIKit.set_tool_badge(pair[0], LocalizationService.format_number(n), "BadgeGreen" if n > 0 else "BadgeRed")


func _on_undo_pressed() -> void:
	if not session.can_undo():
		Router.toast(t("undo_nothing"))
		return
	if _left("undo") <= 0:
		Router.toast(t("free_undos_used_up"), 3.0)
		return
	if not controller.undo():
		return
	AssistPolicy.free_play_use("undo", session.assists)
	controller.save()
	_refresh_badges()


func _on_hint_pressed() -> void:
	if session.completed:
		return
	if session.failed:
		_open_fail()
		return
	if _left("hint") <= 0 and not controller.can_repeat_hint():
		Router.toast(t("free_hints_used_up"), 3.0)
		return
	controller.request_hint()


func _on_hint(res: Dictionary) -> void:
	var useful := not PackedInt32Array(res.get("tiles", [])).is_empty() and not bool(res.get("dead", false)) and not bool(res.get("repeat", false))
	if useful:
		AssistPolicy.free_play_use("hint", session.assists)
		controller.save()
	_refresh_badges()
	if PackedInt32Array(res.get("tiles", [])).is_empty():
		if session.failed:
			_open_fail()
	elif res.get("dead", false):
		Router.toast(t("hint_dead"), 3.5)
	elif not res.get("safe", false) and not res.get("repeat", false):
		Router.toast(t("hint_unverified"), 3.0)


func _shuffle_cost() -> Dictionary:
	var ok := _left("shuffle") > 0
	return {"allowed": ok, "free": ok}


func _do_shuffle(from_rescue: bool, _free: bool) -> void:
	var res := controller.shuffle()
	if res.ok:
		AssistPolicy.free_play_use("shuffle", session.assists)
		controller.save()
		_banner.visible = false
		_refresh_hud()
		return
	_open_shuffle_failed()


func _open_get_more(_item: String, _rescue: bool = false) -> void:
	## No shop here: the allowance for this board is used up. Rewinding and restarting remain.
	controller.stop_clock()
	var m := ModalDialog.open(self, t("free_play_out_title"), t("free_play_out_body"))
	if session.checkpoint < session.history.size():
		m.add_action(t("rewind_free"), "rewind", "green")
	m.add_action(t("restart"), "restart", "cream", "small")
	m.add_action(t("ok"), "ok", "cream", "small")
	m.closed.connect(_on_get_more_closed)


func _open_fail() -> void:
	## Tray full: send tiles back (once per board), undo, try again or leave.
	if has_meta("fail_open") or not session.failed:
		return
	set_meta("fail_open", true)
	controller.stop_clock()
	var body := t("duet_tray_full_body") if kind == "duet" else t("tray_full_body")
	var m := ModalDialog.open(self, t("tray_full_title"), body, false)
	if _left("send_back") > 0:
		m.add_action(t("send_back_free", {"count": SEND_BACK}), "send_back", "green")
	if session.can_undo() and _left("undo") > 0:
		m.add_action(t("undo"), "undo", "cream", "small")
	m.add_action(t("try_again"), "restart", "cream", "small")
	m.add_action(t("home"), "home", "cream", "small")
	m.closed.connect(_on_free_fail_closed)


func _on_free_fail_closed(r: String) -> void:
	remove_meta("fail_open")
	match r:
		"send_back":
			controller.send_back(SEND_BACK)
			AssistPolicy.free_play_use("send_back", session.assists)
			controller.save()
			controller.start_clock()
			_refresh_hud()
		"undo":
			_on_undo_pressed()
			controller.start_clock()
			if session.failed:
				_open_fail()
		"restart":
			_restart()
		_:
			controller.save()
			Router.reset_to("home")


# --- winning --------------------------------------------------------------------------

func _on_won() -> void:
	if _won:
		return
	_won = true
	board.input_enabled = false
	var fin := Scoring.final(session.score, level.tiles.size(), session.stats)
	var stats := {"score": int(fin.score), "stars": int(fin.stars), "clean_bonus": int(fin.bonus),
		"best_combo": int(session.stats.best_combo), "elapsed_ms": controller.elapsed_ms()}
	var best := false
	if kind == "duet":
		best = FreePlayService.record_duet_win(difficulty if difficulty != "" else "board", int(stats.score))
	else:
		best = FreePlayService.record_studio_win(code, int(stats.score))
	if kind == "duet":
		AnalyticsService.track("duet_finished", {"difficulty": difficulty if difficulty != "" else "board", "stars": int(stats.stars)})
	else:
		AnalyticsService.track("studio_board_completed", {"stars": int(stats.stars)})
	GameState.clear_session(slot)
	GameState.save_now()
	AudioService.play("victory")
	AccessibilityService.haptic("win")
	board.play_win_fx()
	tray.celebrate()
	tray.set_slot_marks([])
	var delay := 0.05 if AccessibilityService.reduced_motion() else 0.75
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_inside_tree():
			_open_free_win(stats, best))


func _open_free_win(stats: Dictionary, best: bool) -> void:
	var title := t("duet_win_title") if kind == "duet" else t("studio_win_title")
	var m := ModalDialog.open(self, title, "", false)
	var box := UIKit.vbox(10)
	_add_stars(box, int(stats.stars))
	_add_score_row(box, int(stats.score), int(stats.best_combo))
	if int(stats.clean_bonus) > 0:
		box.add_child(UIKit.label(t("clean_bonus", {"count": int(stats.clean_bonus)}), UITheme.FONT_SMALL, true, UITheme.GREEN, HORIZONTAL_ALIGNMENT_CENTER, false))
	if best:
		box.add_child(UIKit.label(t("new_best_score"), UITheme.FONT_SMALL, true, UITheme.VIOLET, HORIZONTAL_ALIGNMENT_CENTER, false))
	if kind == "duet":
		var s := DuetTurns.summary(session.history, first)
		for i in 2:
			var row := UIKit.hbox(10)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_child(TurnBar.token(i + 1, FreePlayService.player_color(i)))
			var nl := UIKit.label(FreePlayService.player_name(i), UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER, false)
			nl.text_direction = Control.TEXT_DIRECTION_AUTO
			row.add_child(nl)
			row.add_child(UIKit.label(t("duet_pairs_n", {"count": int(s.pairs[i])}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER, false))
			box.add_child(row)
		var team_ups := int(s.team_ups[0]) + int(s.team_ups[1])
		if team_ups > 0:
			box.add_child(UIKit.label(t("duet_team_ups_n", {"count": team_ups}), UITheme.FONT_SMALL, true, UITheme.GOLD.darkened(0.25), HORIZONTAL_ALIGNMENT_CENTER, false))
	if bool(GameState.setting("show_timer")):
		box.add_child(UIKit.label(t("time_taken", {"time": _fmt_time(int(stats.elapsed_ms))}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(code_row(code))
	m.add_content(box)
	if kind == "duet":
		m.add_action(t("duet_new_board"), "new", "green")
		m.add_action(t("duet_same_board"), "again", "cream", "small")
	else:
		m.add_action(t("play_together"), "together", "green")
		m.add_action(t("play_again"), "again", "cream", "small")
	m.add_action(t("home"), "home", "cream", "small")
	m.closed.connect(_on_free_win_closed)


func _on_free_win_closed(r: String) -> void:
	match r:
		"new":
			Router.replace("duet", {"auto": true})
		"again":
			_restart()
		"together":
			Router.replace("freeplay", {"kind": "duet", "code": code, "restart": true})
		_:
			Router.reset_to("home")


static func code_row(p_code: String) -> Control:
	## The board's share code (always left-to-right) with a Copy button.
	var row := UIKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UIKit.label(p_code, UITheme.FONT_H2, true, UITheme.NAVY, HORIZONTAL_ALIGNMENT_CENTER, false)
	l.text_direction = Control.TEXT_DIRECTION_LTR
	AccessibilityService.set_access_name(l, LocalizationService.t("studio_code_label") + " " + p_code)
	row.add_child(l)
	var copy := UIKit.button(LocalizationService.t("copy_code"), "cream", "small", func() -> void:
		DisplayServer.clipboard_set(LocalizationService.t("studio_share_text", {"code": p_code}))
		Router.toast(LocalizationService.t("code_copied")))
	AccessibilityService.set_access_name(copy, LocalizationService.t("a11y_copy_code"))
	row.add_child(copy)
	return row
