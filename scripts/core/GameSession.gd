class_name GameSession
extends RefCounted
## Rules-level state of one board being played: the tray, picks, undo history, shuffles,
## score, stats and the last known-solvable checkpoint. Contains no nodes and no timing: the
## board and tray change the instant a tile is tapped, animations only follow, so visual
## effects can never cause double picks or delay the logical update.
##
## Tray play: tapping a free (uncovered) tile moves it into the tray. A tile whose twin is
## already there clears with it. A tray holding `capacity` tiles is a loss (`failed`); the
## player then undoes, sends tiles back to the board (second chance) or restarts.

enum Tap { IGNORED, BLOCKED, TO_TRAY, MATCHED, FAILED }

const SAVE_VERSION := 2
const MAX_CAPACITY := TrayRules.CAPACITY + 2   ## base 4 + streak bonus + Extra Slot booster

var level: LevelDefinition
var state: BoardState
var tray := PackedInt32Array()          ## tile indices in slot order (arrival order)
var capacity: int = TrayRules.CAPACITY
var failed: bool = false
var score: int = 0
## Each entry:
##   {"t": "p", "i": tile, "m": partner (-1 = went into the tray), "ms": partner's slot, "pts": points}
##   {"t": "s", "before": PackedStringArray}                      shuffle
##   {"t": "r", "tiles": PackedInt32Array, "slots": PackedInt32Array}  tiles sent back to the board
var history: Array = []
var stats := {
	"moves": 0, "hints": 0, "undos": 0, "shuffles": 0, "elapsed_ms": 0,
	"flowers_cleared": 0, "seasons_cleared": 0, "fails": 0, "best_combo": 0,
}
## history.size() at which the board was last proven solvable (0 = the verified start).
var checkpoint: int = 0
## Per-board helper allowances used so far (free undos, free rescue shuffle, continues). Saved
## with the board so quitting and resuming cannot refill them; a restart starts a fresh board.
## extra_slots_used: Extra Slot boosters spent here; streak_slot: 1 when the win-streak bonus
## slot was given; retry: 1 when this is not the first attempt at the level (no streak win).
var assists := {"free_undos_used": 0, "rescue_shuffles_used": 0, "continues_used": 0,
	"extra_slots_used": 0, "streak_slot": 0, "retry": 0}
var completed: bool = false
var shuffle_counter: int = 0


static func start(p_level: LevelDefinition) -> GameSession:
	var s := GameSession.new()
	s.level = p_level
	s.state = p_level.build_state()
	return s


func tap(i: int) -> Dictionary:
	if completed or failed or i < 0 or i >= state.size() or state.is_removed(i):
		return {"r": Tap.IGNORED}
	if not state.is_free(i):
		return {"r": Tap.BLOCKED, "tile": i}
	state.take(i)
	var ps := TrayRules.partner_slot(tray, state.keys, i)
	if ps >= 0:
		var p := tray[ps]
		tray.remove_at(ps)
		history.append({"t": "p", "i": i, "m": p, "ms": ps, "pts": 0})
		stats.moves += 1
		_count_family(i, 2)
		if state.remaining == 0 and tray.is_empty():
			completed = true
		return {"r": Tap.MATCHED, "tile": i, "partner": p, "slot": ps, "won": completed}
	tray.append(i)
	history.append({"t": "p", "i": i, "m": -1, "ms": -1, "pts": 0})
	var slot := tray.size() - 1
	if TrayRules.is_full(tray, capacity):
		failed = true
		stats.fails += 1
		return {"r": Tap.FAILED, "tile": i, "slot": slot}
	return {"r": Tap.TO_TRAY, "tile": i, "slot": slot}


func _count_family(i: int, n: int) -> void:
	if MahjongRules.is_flower(state.faces[i]):
		stats.flowers_cleared = maxi(0, stats.flowers_cleared + n)
	elif MahjongRules.is_season(state.faces[i]):
		stats.seasons_cleared = maxi(0, stats.seasons_cleared + n)


func award(points: int, combo: int) -> void:
	## Score for the match just made (the controller owns combo timing). Kept on the history
	## entry so undoing the match takes the points back.
	if history.is_empty() or history[-1].t != "p" or int(history[-1].m) < 0:
		return
	history[-1].pts = int(history[-1].pts) + points
	score += points
	stats.best_combo = maxi(int(stats.best_combo), combo)


func match_pair(a: int, b: int) -> bool:
	## Programmatic pair (tutorial/autoplay tests): picks a then b. Same legality as tapping.
	if completed or failed or not state.can_pair(a, b):
		return false
	if TrayRules.partner_slot(tray, state.keys, a) >= 0 or tray.size() + 1 >= capacity:
		return false
	tap(a)
	return tap(b).r == Tap.MATCHED


func can_undo() -> bool:
	return not history.is_empty() and not completed


func undo() -> Dictionary:
	## Reverts the most recent action (a pick, a shuffle or a send-back). Returns what changed:
	## {"t": "p", "tile", "partner", "slot"} | {"t": "s"} | {"t": "r", "tiles", "slots"}.
	if not can_undo():
		return {}
	var e: Dictionary = history.pop_back()
	stats.undos += 1
	checkpoint = mini(checkpoint, history.size())
	failed = false
	match e.t:
		"p":
			var i: int = e.i
			var slot: int
			if int(e.m) >= 0:
				slot = int(e.ms)
				tray.insert(slot, int(e.m))
				score = maxi(0, score - int(e.pts))
				_count_family(i, -2)
			else:
				slot = tray.find(i)
				tray.remove_at(slot)
			state.put_back(i)
			return {"t": "p", "tile": i, "partner": int(e.m), "slot": slot}
		"r":
			var tiles: PackedInt32Array = e.tiles
			var slots: PackedInt32Array = e.slots
			for k in tiles.size():
				state.take(tiles[k])
				tray.insert(slots[k], tiles[k])
			failed = TrayRules.is_full(tray, capacity)
			return {"t": "r", "tiles": tiles, "slots": slots}
	state.set_faces(e.before)
	return {"t": "s"}


func undo_to_checkpoint() -> int:
	## Rescue fallback: rewind to the last state proven solvable. Returns steps undone.
	var n := 0
	while history.size() > checkpoint and can_undo():
		undo()
		n += 1
	return n


func send_back(n: int) -> Dictionary:
	## Second chance: the last `n` tiles that entered the tray return to their board places
	## (they were uncovered when picked, and nothing can be stacked on them since). No match or
	## score is lost. Returns {"tiles", "slots"} or {} when there is nothing to send back.
	if completed or tray.is_empty() or n <= 0:
		return {}
	var k := mini(n, tray.size())
	var tiles := PackedInt32Array()
	var slots := PackedInt32Array()
	for s in range(tray.size() - k, tray.size()):
		slots.append(s)
		tiles.append(tray[s])
	for s in range(tray.size() - 1, tray.size() - k - 1, -1):
		state.put_back(tray[s])
		tray.remove_at(s)
	history.append({"t": "r", "tiles": tiles, "slots": slots})
	failed = false
	return {"tiles": tiles, "slots": slots}


func shuffle() -> Dictionary:
	## Rearranges the faces on the board into a provably clearable arrangement (tray tiles
	## keep theirs). Never touches progress, the tray or which tiles are on the board.
	if completed or failed:
		return {"ok": false, "reason": "completed" if completed else "failed"}
	shuffle_counter += 1
	var seed_value := SeededRng.hash_string("%s|shuffle|%d|%d" % [level.key, shuffle_counter, history.size()])
	var res := ShuffleRescue.rescue(state, seed_value, tray)
	if not res.ok:
		return res
	history.append({"t": "s", "before": state.faces.duplicate()})
	state.set_faces(res.faces)
	stats.shuffles += 1
	checkpoint = history.size()
	return res


func add_slot() -> bool:
	## One more tray slot for the rest of this board (Extra Slot booster, streak bonus). It is
	## not part of the history, so Undo never takes it away. A full tray becomes playable again.
	if completed or capacity >= MAX_CAPACITY:
		return false
	capacity += 1
	failed = TrayRules.is_full(tray, capacity)
	return true


func mark_solvable_now() -> void:
	checkpoint = history.size()


func has_moves() -> bool:
	## With the "uncovered" rule the topmost tile is always free, so only a full tray stops play.
	return not failed and not completed and state.remaining > 0


func tray_danger() -> bool:
	## One slot left: the next unmatched tile loses.
	return tray.size() >= capacity - 1


func tiles_left() -> int:
	return state.remaining + tray.size()


func progress() -> float:
	return 1.0 - float(tiles_left()) / float(maxi(1, state.size()))


func to_dict() -> Dictionary:
	var hist: Array = []
	for e in history:
		match e.t:
			"p":
				hist.append({"t": "p", "i": e.i, "m": e.m, "ms": e.ms, "pts": e.pts})
			"r":
				hist.append({"t": "r", "tiles": Array(e.tiles), "slots": Array(e.slots)})
			_:
				hist.append({"t": "s", "before": Array(e.before)})
	return {
		"v": SAVE_VERSION, "level_key": level.key, "layout": layout_hash(level), "faces": Array(state.faces),
		"removed": Array(state.removed_indices()), "tray": Array(tray), "capacity": capacity,
		"score": score, "history": hist, "stats": stats.duplicate(),
		"checkpoint": checkpoint, "shuffle_counter": shuffle_counter, "assists": assists.duplicate(),
	}


static func layout_hash(p_level: LevelDefinition) -> String:
	## Fingerprint of the tile positions, saved with every snapshot.
	return "%x" % SeededRng.hash_string(str(p_level.positions()))


static func restore(p_level: LevelDefinition, d: Dictionary) -> GameSession:
	## Rebuilds a half-finished board exactly. Returns null if the snapshot does not belong to
	## this level or is internally inconsistent (then the caller starts fresh, keeping progress).
	## Version 1 snapshots (classic pair play) convert: each pair becomes two picks.
	var v := int(d.get("v", 0))
	if (v != 1 and v != SAVE_VERSION) or str(d.get("level_key", "")) != p_level.key:
		return null
	# A rebuilt level keeps its key but not its tile positions: never restore onto other geometry.
	if d.has("layout") and str(d.layout) != layout_hash(p_level):
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
	s.capacity = clampi(int(d.get("capacity", TrayRules.CAPACITY)), TrayRules.CAPACITY, MAX_CAPACITY)
	s.tray = PackedInt32Array(d.get("tray", []))
	for t in s.tray:
		if t < 0 or t >= faces.size() or not s.state.is_removed(t):
			return null
	if s.tray.size() > s.capacity or not TrayRules.keys_valid(s.tray, s.state.keys):
		return null
	if not s.state.face_counts_valid(s.tray):
		return null
	var raw_hist: Array = d.get("history", [])
	var old_cp := clampi(int(d.get("checkpoint", 0)), 0, raw_hist.size())
	var cp := old_cp
	for n in raw_hist.size():
		var e: Variant = raw_hist[n]
		if n == old_cp and v == 1:
			cp = s.history.size()  # v1 checkpoints count pairs; picks double the index
		if typeof(e) != TYPE_DICTIONARY:
			return null
		match e.get("t"):
			"m":
				if v != 1:
					return null
				s.history.append({"t": "p", "i": int(e.a), "m": -1, "ms": -1, "pts": 0})
				s.history.append({"t": "p", "i": int(e.b), "m": int(e.a), "ms": 0, "pts": 0})
			"p":
				s.history.append({"t": "p", "i": int(e.i), "m": int(e.get("m", -1)), "ms": int(e.get("ms", -1)), "pts": maxi(0, int(e.get("pts", 0)))})
			"r":
				var tiles := PackedInt32Array(e.get("tiles", []))
				var slots := PackedInt32Array(e.get("slots", []))
				if tiles.size() != slots.size():
					return null
				s.history.append({"t": "r", "tiles": tiles, "slots": slots})
			"s":
				var before := PackedStringArray(e.get("before", []))
				if before.size() != faces.size():
					return null
				s.history.append({"t": "s", "before": before})
			_:
				return null
	if v == 1 and old_cp >= raw_hist.size():
		cp = s.history.size()
	var st: Dictionary = d.get("stats", {})
	for k in s.stats:
		s.stats[k] = int(st.get(k, 0))
	s.checkpoint = clampi(cp, 0, s.history.size())
	s.shuffle_counter = int(d.get("shuffle_counter", 0))
	s.score = maxi(0, int(d.get("score", 0)))
	var asg: Variant = d.get("assists", {})  # absent in snapshots from before the economy
	if typeof(asg) == TYPE_DICTIONARY:
		for k in s.assists:
			s.assists[k] = maxi(0, int(asg.get(k, 0)))
	s.failed = TrayRules.is_full(s.tray, s.capacity)
	s.completed = s.state.remaining == 0 and s.tray.is_empty()
	return s
