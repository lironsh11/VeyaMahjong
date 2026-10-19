class_name GameSession
extends RefCounted
## Rules-level state of one board being played: selection, matches, undo history, shuffles,
## stats and the last known-solvable checkpoint. Contains no nodes and no timing: the board
## state changes the instant a legal pair is tapped, animations only follow it, so visual
## effects can never cause double matches or delay the logical update.

enum Tap { IGNORED, BLOCKED, SELECTED, DESELECTED, RESELECTED, MATCHED }

const SAVE_VERSION := 1

var level: LevelDefinition
var state: BoardState
var selected: int = -1
## Each entry: {"t": "m", "a": i, "b": j}  or  {"t": "s", "before": PackedStringArray}
var history: Array = []
var stats := {
	"moves": 0, "hints": 0, "undos": 0, "shuffles": 0, "elapsed_ms": 0,
	"flowers_cleared": 0, "seasons_cleared": 0,
}
## history.size() at which the board was last proven solvable (0 = the verified start).
var checkpoint: int = 0
## Per-board helper allowances used so far (free undos, free rescue shuffle). Saved with the
## board so quitting and resuming cannot refill them; a restart starts a fresh board.
var assists := {"free_undos_used": 0, "rescue_shuffles_used": 0}
var completed: bool = false
var shuffle_counter: int = 0


static func start(p_level: LevelDefinition) -> GameSession:
	var s := GameSession.new()
	s.level = p_level
	s.state = p_level.build_state()
	return s


func tap(i: int) -> Dictionary:
	if completed or i < 0 or i >= state.size() or state.is_removed(i):
		return {"r": Tap.IGNORED}
	if not state.is_free(i):
		return {"r": Tap.BLOCKED, "tile": i}
	if selected == -1:
		selected = i
		return {"r": Tap.SELECTED, "tile": i}
	if selected == i:
		selected = -1
		return {"r": Tap.DESELECTED, "tile": i}
	var a := selected
	if state.can_pair(a, i):
		_apply_match(a, i)
		return {"r": Tap.MATCHED, "a": a, "b": i, "won": completed}
	# Not a match: move the selection to the newly tapped free tile (gentle, no penalty).
	selected = i
	return {"r": Tap.RESELECTED, "prev": a, "tile": i}


func _apply_match(a: int, b: int) -> void:
	state.remove_pair(a, b)
	history.append({"t": "m", "a": a, "b": b})
	selected = -1
	stats.moves += 1
	if MahjongRules.is_flower(state.faces[a]):
		stats.flowers_cleared += 2
	elif MahjongRules.is_season(state.faces[a]):
		stats.seasons_cleared += 2
	if state.remaining == 0:
		completed = true


func match_pair(a: int, b: int) -> bool:
	## Programmatic match (tutorial/autoplay tests). Same legality as tapping.
	if completed or not state.can_pair(a, b):
		return false
	_apply_match(a, b)
	return true


func can_undo() -> bool:
	return not history.is_empty() and not completed


func undo() -> Dictionary:
	## Reverts the most recent action (a match or a shuffle). Returns what changed.
	if not can_undo():
		return {}
	var e: Dictionary = history.pop_back()
	selected = -1
	stats.undos += 1
	checkpoint = mini(checkpoint, history.size())
	if e.t == "m":
		state.restore_pair(e.a, e.b)
		if MahjongRules.is_flower(state.faces[e.a]):
			stats.flowers_cleared = maxi(0, stats.flowers_cleared - 2)
		elif MahjongRules.is_season(state.faces[e.a]):
			stats.seasons_cleared = maxi(0, stats.seasons_cleared - 2)
		return {"t": "m", "a": e.a, "b": e.b}
	state.set_faces(e.before)
	return {"t": "s"}


func undo_to_checkpoint() -> int:
	## Rescue fallback: rewind to the last state proven solvable. Returns steps undone.
	var n := 0
	while history.size() > checkpoint and can_undo():
		undo()
		n += 1
	return n


func shuffle() -> Dictionary:
	## Rearranges remaining faces into a provably clearable arrangement. Never touches
	## progress or the removed set.
	if completed:
		return {"ok": false, "reason": "completed"}
	shuffle_counter += 1
	var seed_value := SeededRng.hash_string("%s|shuffle|%d|%d" % [level.key, shuffle_counter, history.size()])
	var res := ShuffleRescue.rescue(state, seed_value)
	if not res.ok:
		return res
	history.append({"t": "s", "before": state.faces.duplicate()})
	state.set_faces(res.faces)
	selected = -1
	stats.shuffles += 1
	checkpoint = history.size()
	return res


func mark_solvable_now() -> void:
	checkpoint = history.size()


func legal_pairs() -> Array[Vector2i]:
	return state.available_pairs()


func has_moves() -> bool:
	return state.has_moves()


func progress() -> float:
	return 1.0 - float(state.remaining) / float(maxi(1, state.size()))


func to_dict() -> Dictionary:
	var hist: Array = []
	for e in history:
		if e.t == "m":
			hist.append({"t": "m", "a": e.a, "b": e.b})
		else:
			hist.append({"t": "s", "before": Array(e.before)})
	return {
		"v": SAVE_VERSION, "level_key": level.key, "faces": Array(state.faces),
		"removed": Array(state.removed_indices()), "history": hist, "stats": stats.duplicate(),
		"checkpoint": checkpoint, "shuffle_counter": shuffle_counter, "assists": assists.duplicate(),
	}


static func restore(p_level: LevelDefinition, d: Dictionary) -> GameSession:
	## Rebuilds a half-finished board exactly. Returns null if the snapshot does not belong to
	## this level or is internally inconsistent (then the caller starts fresh, keeping progress).
	if int(d.get("v", 0)) != SAVE_VERSION or str(d.get("level_key", "")) != p_level.key:
		return null
	var faces := PackedStringArray(d.get("faces", []))
	if faces.size() != p_level.tiles.size():
		return null
	# A shuffle only permutes faces, so the multiset must equal the level's original faces.
	var a := Array(faces)
	var b := Array(p_level.faces())
	a.sort()
	b.sort()
	if a != b:
		return null
	var s := GameSession.new()
	s.level = p_level
	s.state = BoardState.create(p_level.build_geometry(), faces)
	if not s.state.apply_removed(PackedInt32Array(d.get("removed", []))):
		return null
	if not s.state.face_counts_valid():
		return null
	for e in d.get("history", []):
		if typeof(e) != TYPE_DICTIONARY:
			return null
		if e.get("t") == "m":
			s.history.append({"t": "m", "a": int(e.a), "b": int(e.b)})
		elif e.get("t") == "s":
			var before := PackedStringArray(e.get("before", []))
			if before.size() != faces.size():
				return null
			s.history.append({"t": "s", "before": before})
		else:
			return null
	var st: Dictionary = d.get("stats", {})
	for k in s.stats:
		s.stats[k] = int(st.get(k, 0))
	s.checkpoint = clampi(int(d.get("checkpoint", 0)), 0, s.history.size())
	s.shuffle_counter = int(d.get("shuffle_counter", 0))
	var asg: Variant = d.get("assists", {})  # absent in snapshots from before the economy
	if typeof(asg) == TYPE_DICTIONARY:
		for k in s.assists:
			s.assists[k] = maxi(0, int(asg.get(k, 0)))
	s.completed = s.state.remaining == 0
	return s
