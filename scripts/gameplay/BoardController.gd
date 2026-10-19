class_name BoardController
extends RefCounted
## Glue between a GameSession (rules), the BoardView and the TrayView (visuals).
##
## - Every tap goes through GameSession first; the views only animate the result, so a
##   second tap during an animation acts on the already-updated state (no double picks).
## - After each pick the session is persisted (crash safety) and a bounded solvability check
##   (TraySolver) runs on a worker thread. A proven-solvable result moves the rescue
##   checkpoint forward; a proven-unsolvable result raises a gentle "stuck" notice. "Unknown"
##   (budget) is never presented as either.
## - Combo: matches less than COMBO_WINDOW_MS apart build a combo that multiplies points and
##   raises the match sound's pitch. It is presentation and score only; it never gates play.
## - Hints name the next pick(s) of a proven solution when one is found in the time budget;
##   otherwise the hint is labelled as unverified, never as "safe".

signal blocked_tapped(index: int)
signal picked(tile: int, slot: int)
signal matched(tile: int, partner: int, combo: int, points: int)
signal tray_failed
signal won
signal solvability(status: String)   # solvable | dead | unknown
signal hint_result(result: Dictionary)
signal changed

const CHECK_NODES := 40000
const CHECK_MS := 600
const HINT_TOTAL_MS := 700
const HINT_NODES := 60000
const COMBO_WINDOW_MS := 3000

var session: GameSession
var view: BoardView
var tray_view: TrayView
var mode: String = "level"
var persist: bool = true
var combo: int = 0
var dead_known: bool = false
var _last_match_ms: int = -COMBO_WINDOW_MS
var _gen: int = 0
var _hint_busy: bool = false
var _hint_shown_gen: int = -1   ## _gen at which the last hint was shown (repeat is free)
var _hint_last: Dictionary = {}
var _clock_start: int = -1


func _init(p_session: GameSession, p_mode: String, p_persist: bool = true) -> void:
	session = p_session
	mode = p_mode
	persist = p_persist


func attach_view(v: BoardView, t: TrayView = null) -> void:
	view = v
	view.tile_tapped.connect(_on_tap)
	tray_view = t
	if tray_view:
		tray_view.show_tray(session.tray, session.state.faces, session.capacity)
		tray_view.popped.connect(_on_popped)


func start_clock() -> void:
	if _clock_start < 0 and not session.completed:
		_clock_start = Time.get_ticks_msec()


func stop_clock() -> void:
	if _clock_start >= 0:
		session.stats.elapsed_ms = int(session.stats.elapsed_ms) + (Time.get_ticks_msec() - _clock_start)
		_clock_start = -1


func elapsed_ms() -> int:
	var e := int(session.stats.elapsed_ms)
	if _clock_start >= 0:
		e += Time.get_ticks_msec() - _clock_start
	return e


func combo_left() -> float:
	## 1.0 right after a match, draining to 0.0 when the combo window closes.
	if combo <= 0:
		return 0.0
	return clampf(1.0 - float(Time.get_ticks_msec() - _last_match_ms) / COMBO_WINDOW_MS, 0.0, 1.0)


static func points_for(p_combo: int) -> int:
	return Scoring.points_for(p_combo)


func add_slot() -> bool:
	## Extra slot (booster or streak bonus): one more tray slot for this board. Never undone.
	if not session.add_slot():
		return false
	if tray_view:
		tray_view.show_tray(session.tray, session.state.faces, session.capacity, true)
		tray_view.set_danger(session.tray_danger() and not session.failed)
	AudioService.play("reward")
	dead_known = false
	_gen += 1
	save()
	changed.emit()
	_schedule_check()
	return true


func _on_tap(i: int) -> void:
	var from := view.tile_global_rect(i) if session.state.size() > i and i >= 0 else Rect2()
	var r := session.tap(i)
	match r.r:
		GameSession.Tap.BLOCKED:
			view.play_blocked(i)
			AudioService.play("invalid")
			AccessibilityService.haptic("invalid")
			blocked_tapped.emit(i)
		GameSession.Tap.TO_TRAY, GameSession.Tap.FAILED:
			view.clear_hint()
			view.lift(i)
			if tray_view:
				tray_view.fly_in(i, session.state.faces[i], from, session.tray)
			AudioService.play("select")
			AccessibilityService.haptic("tap")
			if r.r == GameSession.Tap.FAILED:
				_after_fail()
			else:
				_after_pick(i, int(r.slot))
		GameSession.Tap.MATCHED:
			view.clear_hint()
			view.lift(i)
			_after_match(i, int(r.partner), int(r.slot), from)


func _after_pick(i: int, slot: int) -> void:
	if tray_view:
		tray_view.set_danger(session.tray_danger())
	if session.tray_danger():
		AudioService.play("tray_alert")
	_gen += 1
	save()
	picked.emit(i, slot)
	changed.emit()
	_schedule_check()


func _after_match(i: int, partner: int, partner_slot: int, from: Rect2) -> void:
	var now := Time.get_ticks_msec()
	combo = combo + 1 if now - _last_match_ms <= COMBO_WINDOW_MS else 1
	_last_match_ms = now
	var pts := points_for(combo)
	session.award(pts, combo)
	if tray_view:
		# Sound and haptic land with the burst (_on_popped), not with the tap.
		tray_view.fly_match(i, session.state.faces[i], from, partner, partner_slot, session.tray, combo, pts)
		tray_view.set_danger(session.tray_danger())
	else:
		_on_popped(Vector2.ZERO, combo)
	if mode != "tutorial":
		DailyService.record_match(session.state.faces[i])
	dead_known = false
	_gen += 1
	save()
	matched.emit(i, partner, combo, pts)
	changed.emit()
	if session.completed:
		stop_clock()
		won.emit()
	else:
		_schedule_check()


func _on_popped(_center: Vector2, p_combo: int) -> void:
	# The owner's match sound from the asset pack (owner request 2026-10-19: no generated layer
	# on top), rising gently in pitch for consecutive matches.
	AudioService.play_match(p_combo)
	AccessibilityService.haptic("combo" if p_combo >= 4 else "match")


func _after_fail() -> void:
	combo = 0
	if tray_view:
		tray_view.play_fail()
	AudioService.play("fail")
	AccessibilityService.haptic("fail")
	_gen += 1
	save()
	if mode != "tutorial":
		AnalyticsService.track("tray_full", {"level": session.level.id, "tiles_left": session.tiles_left()})
	changed.emit()
	tray_failed.emit()


func undo() -> bool:
	if not session.can_undo():
		return false
	var r := session.undo()
	view.clear_hint()
	match r.get("t"):
		"p":
			_return_to_board(PackedInt32Array([int(r.tile)]))
		"r":
			for i in r.tiles:
				view.lift(i)
			_sync_tray()
		_:
			view.play_reshuffle()
	AudioService.play("undo")
	combo = 0
	dead_known = false
	_gen += 1
	save()
	changed.emit()
	_schedule_check()
	if mode != "tutorial":
		AnalyticsService.track("undo_used", {"level": session.level.id})
	return true


func send_back(n: int) -> bool:
	## Second chance after a full tray: the newest tray tiles return to their board places.
	var r := session.send_back(n)
	if r.is_empty():
		return false
	_return_to_board(r.tiles)
	AudioService.play("undo")
	combo = 0
	dead_known = false
	_gen += 1
	save()
	changed.emit()
	_schedule_check()
	return true


func _return_to_board(tiles: PackedInt32Array) -> void:
	var targets := {}
	for i in tiles:
		targets[i] = view.tile_global_rect(i)
	if tray_view:
		tray_view.send_home(targets, session.tray, session.state.faces, func(i: int) -> void:
			if is_instance_valid(view):
				view.restore_one(i))
	else:
		for i in tiles:
			view.restore_one(i)
	_sync_tray()


func _sync_tray() -> void:
	if tray_view:
		tray_view.show_tray(session.tray, session.state.faces, session.capacity, true)
		tray_view.set_danger(session.tray_danger())
	view.refresh_free()


func undo_to_checkpoint() -> int:
	## Free rescue: rewinds to the last state proven solvable (never charged by the economy).
	var n := 0
	while session.history.size() > session.checkpoint and session.can_undo():
		undo()
		n += 1
	return n


func shuffle() -> Dictionary:
	var res := session.shuffle()
	if mode != "tutorial":
		AnalyticsService.track("shuffle_used", {"level": session.level.id, "ok": bool(res.ok)})
	if not res.ok:
		return res
	view.play_reshuffle()
	AudioService.play("shuffle")
	combo = 0
	dead_known = false
	_gen += 1
	save()
	solvability.emit("solvable")  # a successful shuffle is solvable by construction
	changed.emit()
	return res


func can_repeat_hint() -> bool:
	return _hint_shown_gen == _gen and not PackedInt32Array(_hint_last.get("tiles", [])).is_empty()


func request_hint() -> void:
	if _hint_busy or session.completed or session.failed:
		return
	if can_repeat_hint():
		# Nothing changed since the last hint: show the same tiles again (free).
		view.show_hint(_hint_last.tiles)
		var again := _hint_last.duplicate()
		again["repeat"] = true
		hint_result.emit(again)
		return
	_hint_busy = true
	var st := session.state.clone()
	var tray := session.tray.duplicate()
	var cap := session.capacity
	var gen := _gen
	Jobs.run(func() -> Dictionary: return BoardController.compute_hint(st, tray, cap),
		_on_hint_done.bind(gen))


func _on_hint_done(res: Variant, gen: int) -> void:
	_hint_busy = false
	if gen != _gen or session.completed:
		return
	var tiles := PackedInt32Array(res.get("tiles", []))
	if not tiles.is_empty():
		view.show_hint(tiles)
		AudioService.play("hint")
		# Counted (for no-hint records and tasks) only when a useful pick was actually shown.
		if not bool(res.get("dead", false)):
			session.stats.hints += 1
			_hint_shown_gen = gen
			_hint_last = res
	save()
	hint_result.emit(res)


static func compute_hint(st: BoardState, tray: PackedInt32Array, capacity: int = TrayRules.CAPACITY) -> Dictionary:
	## Worker-thread safe: operates only on the cloned state passed in.
	## Returns {"tiles": PackedInt32Array (1 or 2 picks), "safe": bool, "dead": bool}.
	if st.free_tiles().is_empty() or tray.size() >= capacity:
		return {"tiles": PackedInt32Array(), "safe": false, "dead": false}
	var r := TraySolver.new(HINT_NODES, HINT_TOTAL_MS, capacity).solve(st, tray)
	if r.result == BoardSolver.Result.SOLVED and not r.solution.is_empty():
		var sol: PackedInt32Array = r.solution
		var tiles := PackedInt32Array([sol[0]])
		if sol.size() > 1 and st.keys[sol[1]] == st.keys[sol[0]] and TrayRules.partner_slot(tray, st.keys, sol[0]) < 0:
			tiles.append(sol[1])
		return {"tiles": tiles, "safe": true, "dead": false}
	return {"tiles": best_guess(st, tray), "safe": false, "dead": r.result == BoardSolver.Result.UNSOLVABLE}


static func best_guess(st: BoardState, tray: PackedInt32Array) -> PackedInt32Array:
	## Without a proof: a tile that clears a tray slot, else a free twin pair, else the tile
	## that uncovers the most.
	var free := st.free_tiles()
	var by_key := {}
	var best := -1
	var best_score := -1
	for i in free:
		if TrayRules.partner_slot(tray, st.keys, i) >= 0:
			return PackedInt32Array([i])
		if by_key.has(st.keys[i]):
			return PackedInt32Array([by_key[st.keys[i]], i])
		by_key[st.keys[i]] = i
		var sc := TraySolver.score(st, i)
		if sc > best_score:
			best_score = sc
			best = i
	return PackedInt32Array([best]) if best >= 0 else PackedInt32Array()


func _schedule_check() -> void:
	if session.failed or session.completed:
		return
	var st := session.state.clone()
	var tray := session.tray.duplicate()
	var cap := session.capacity
	var gen := _gen
	Jobs.run(func() -> int: return TraySolver.new(CHECK_NODES, CHECK_MS, cap).solve(st, tray).result,
		_on_check_done.bind(gen))


func _on_check_done(result: Variant, gen: int) -> void:
	if gen != _gen:
		return  # superseded by a newer move
	var r := int(result)
	if r == BoardSolver.Result.SOLVED:
		session.mark_solvable_now()
		solvability.emit("solvable")
	elif r == BoardSolver.Result.UNSOLVABLE:
		dead_known = true
		solvability.emit("dead")
	else:
		solvability.emit("unknown")


func save() -> void:
	if not persist or session.completed:
		return
	var snap := session.to_dict()
	snap.stats.elapsed_ms = elapsed_ms()
	GameState.set_active_session({"mode": mode, "key": session.level.key, "level_id": session.level.id, "session": snap})
