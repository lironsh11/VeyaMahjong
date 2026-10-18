class_name BoardController
extends RefCounted
## Glue between a GameSession (rules) and a BoardView (visuals).
##
## - Every tap goes through GameSession first; the view only animates the result, so a
##   second tap during an animation acts on the already-updated state (no double matches).
## - After each pair the session is persisted (crash safety) and a bounded solvability check
##   runs on a worker thread. A proven-solvable result moves the rescue checkpoint forward;
##   a proven-unsolvable result raises a gentle "stuck" notice. "Unknown" (budget) is never
##   presented as either.
## - Hints search for a pair after which the solver can still clear the board; if that cannot
##   be proven within the time budget the hint is labelled as unverified, never as "safe".

signal blocked_tapped(index: int)
signal matched(a: int, b: int)
signal won
signal moves_exhausted
signal solvability(status: String)   # solvable | dead | unknown
signal hint_result(result: Dictionary)
signal changed

const CHECK_NODES := 40000
const CHECK_MS := 600
const HINT_TOTAL_MS := 700
const HINT_NODES_EACH := 25000

var session: GameSession
var view: BoardView
var mode: String = "level"
var persist: bool = true
var combo: int = 0
var dead_known: bool = false
var _gen: int = 0
var _hint_busy: bool = false
var _clock_start: int = -1


func _init(p_session: GameSession, p_mode: String, p_persist: bool = true) -> void:
	session = p_session
	mode = p_mode
	persist = p_persist


func attach_view(v: BoardView) -> void:
	view = v
	view.tile_tapped.connect(_on_tap)
	if session.selected >= 0:
		view.set_selected(session.selected, false)


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


func _on_tap(i: int) -> void:
	var r := session.tap(i)
	match r.r:
		GameSession.Tap.BLOCKED:
			view.play_blocked(i)
			AudioService.play("invalid")
			AccessibilityService.haptic("invalid")
			combo = 0
			blocked_tapped.emit(i)
		GameSession.Tap.SELECTED:
			view.clear_hint()
			view.set_selected(i, true)
			AudioService.play("select")
			AccessibilityService.haptic("tap")
		GameSession.Tap.DESELECTED:
			view.set_selected(i, false)
			AudioService.play("tap")
		GameSession.Tap.RESELECTED:
			view.set_selected(r.prev, false)
			view.set_selected(i, true)
			AudioService.play("select")
		GameSession.Tap.MATCHED:
			_after_match(r.a, r.b)


func _after_match(a: int, b: int) -> void:
	view.set_selected(a, false)
	view.set_selected(b, false)
	view.play_match(a, b)
	combo += 1
	# Gentle rising "harmonics" for consecutive matches; no timing pressure involved.
	AudioService.play("match", 1.0 + minf(combo - 1, 6) * 0.025)
	AccessibilityService.haptic("match")
	if mode != "tutorial":
		DailyService.record_match(session.state.faces[a])
	dead_known = false
	_gen += 1
	save()
	matched.emit(a, b)
	changed.emit()
	if session.completed:
		stop_clock()
		won.emit()
	elif not session.has_moves():
		moves_exhausted.emit()
	else:
		_schedule_check()


func undo() -> bool:
	if not session.can_undo():
		return false
	var prev_sel := session.selected
	var r := session.undo()
	if prev_sel >= 0:
		view.set_selected(prev_sel, false)
	view.clear_hint()
	if r.get("t") == "m":
		view.play_restore(r.a, r.b)
	else:
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


func undo_to_checkpoint() -> int:
	var n := 0
	while session.history.size() > session.checkpoint and session.can_undo():
		undo()
		n += 1
	return n


func shuffle() -> Dictionary:
	var prev_sel := session.selected
	var res := session.shuffle()
	if mode != "tutorial":
		AnalyticsService.track("shuffle_used", {"level": session.level.id, "ok": bool(res.ok)})
	if not res.ok:
		return res
	if prev_sel >= 0:
		view.set_selected(prev_sel, false)
	view.play_reshuffle()
	AudioService.play("shuffle")
	combo = 0
	dead_known = false
	_gen += 1
	save()
	solvability.emit("solvable")  # a successful shuffle is solvable by construction
	changed.emit()
	return res


func request_hint() -> void:
	if _hint_busy or session.completed:
		return
	_hint_busy = true
	session.stats.hints += 1
	var st := session.state.clone()
	var gen := _gen
	Jobs.run(func() -> Dictionary: return BoardController.compute_hint(st),
		_on_hint_done.bind(gen))


func _on_hint_done(res: Variant, gen: int) -> void:
	_hint_busy = false
	if gen != _gen or session.completed:
		return
	if res.get("pair") != null:
		var p: Vector2i = res.pair
		view.show_hint(p.x, p.y)
		AudioService.play("hint")
	save()
	hint_result.emit(res)


static func compute_hint(st: BoardState) -> Dictionary:
	## Worker-thread safe: operates only on the cloned state passed in.
	var pairs := st.available_pairs()
	if pairs.is_empty():
		return {"pair": null, "safe": false, "dead": false}
	var deadline := Time.get_ticks_msec() + HINT_TOTAL_MS
	var unknown: Variant = null
	var dead_count := 0
	var tried := 0
	for p in pairs:
		var remaining_ms := deadline - Time.get_ticks_msec()
		if remaining_ms <= 20 or tried >= 24:
			break
		tried += 1
		var s2 := st.clone()
		s2.remove_pair(p.x, p.y)
		var r := BoardSolver.new(HINT_NODES_EACH, remaining_ms).solve(s2)
		match r.result:
			BoardSolver.Result.SOLVED:
				return {"pair": p, "safe": true, "dead": false}
			BoardSolver.Result.UNSOLVABLE:
				dead_count += 1
			_:
				if unknown == null:
					unknown = p
	if unknown != null:
		return {"pair": unknown, "safe": false, "dead": false}
	return {"pair": pairs[0], "safe": false, "dead": dead_count == pairs.size()}


func _schedule_check() -> void:
	var st := session.state.clone()
	var gen := _gen
	Jobs.run(func() -> int: return BoardSolver.new(CHECK_NODES, CHECK_MS).solve(st).result,
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
