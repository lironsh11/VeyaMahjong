class_name TraySolver
extends RefCounted
## Bounded depth-first solver for tray play: a move is one pick of a free tile.
##
## Correctness notes:
## - Only legal picks are applied; a pick that would leave `capacity` unmatched tiles in the
##   tray (a loss) is never tried.
## - The tray is determined by the set of tiles off the board (see TrayRules), so dead states
##   are memoised by the board's Zobrist hash alone, like BoardSolver.
## - No pruning rule is assumed safe; move ORDER does the work: a pick that clears a tray tile
##   first, then the first tile of a free twin pair, then tiles that uncover the most.
## - Budgets work as in BoardSolver: BUDGET means "unknown", never solvable.
## Results reuse BoardSolver.Result so callers handle both solvers the same way.

var max_nodes: int = 250000
var time_budget_ms: int = 0
var nodes: int = 0
var capacity: int = TrayRules.CAPACITY
var _dead: Dictionary = {}
var _deadline: int = 0
var _path := PackedInt32Array()
var _in_tray := PackedByteArray()
var _tray_n: int = 0


func _init(p_max_nodes: int = 250000, p_time_budget_ms: int = 0, p_capacity: int = TrayRules.CAPACITY) -> void:
	max_nodes = p_max_nodes
	time_budget_ms = p_time_budget_ms
	capacity = p_capacity


func solve(state: BoardState, tray: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	## Returns {"result": BoardSolver.Result, "solution": PackedInt32Array (picks), "nodes": int}.
	## The input state is not modified.
	nodes = 0
	_dead.clear()
	_path.clear()
	_deadline = Time.get_ticks_msec() + time_budget_ms if time_budget_ms > 0 else 0
	if tray.size() >= capacity or not state.face_counts_valid(tray) or not TrayRules.keys_valid(tray, state.keys):
		return {"result": BoardSolver.Result.UNSOLVABLE, "solution": PackedInt32Array(), "nodes": 0}
	var s := state.clone()
	_in_tray.resize(MahjongRules.key_count())
	_in_tray.fill(0)
	for t in tray:
		_in_tray[s.keys[t]] = 1
	_tray_n = tray.size()
	var r := _dfs(s)
	var sol: PackedInt32Array = _path.duplicate() if r == BoardSolver.Result.SOLVED else PackedInt32Array()
	return {"result": r, "solution": sol, "nodes": nodes}


func _dfs(s: BoardState) -> int:
	if s.remaining == 0:
		return BoardSolver.Result.SOLVED if _tray_n == 0 else BoardSolver.Result.UNSOLVABLE
	nodes += 1
	if nodes > max_nodes:
		return BoardSolver.Result.BUDGET
	if _deadline > 0 and (nodes & 255) == 0 and Time.get_ticks_msec() > _deadline:
		return BoardSolver.Result.BUDGET
	if _dead.has(s.zhash):
		return BoardSolver.Result.UNSOLVABLE
	var moves := _moves(s)
	for m in moves:
		var i: int = m[1]
		_pick(s, i)
		_path.append(i)
		var r := _dfs(s)
		if r == BoardSolver.Result.SOLVED:
			return r
		_path.resize(_path.size() - 1)
		_unpick(s, i)
		if r == BoardSolver.Result.BUDGET:
			return r
	_dead[s.zhash] = true
	return BoardSolver.Result.UNSOLVABLE


func _moves(s: BoardState) -> Array:
	var free := s.free_tiles()
	var per_key := {}
	for i in free:
		per_key[s.keys[i]] = int(per_key.get(s.keys[i], 0)) + 1
	var room := _tray_n + 1 < capacity
	var moves: Array = []
	for i in free:
		var k := s.keys[i]
		if _in_tray[k] == 1:
			moves.append([100000 + score(s, i), i])
		elif room:
			moves.append([(1000 if int(per_key[k]) >= 2 else 0) + score(s, i), i])
	moves.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return moves


func _pick(s: BoardState, i: int) -> void:
	s.take(i)
	var k := s.keys[i]
	if _in_tray[k] == 1:
		_in_tray[k] = 0
		_tray_n -= 1
	else:
		_in_tray[k] = 1
		_tray_n += 1


func _unpick(s: BoardState, i: int) -> void:
	s.put_back(i)
	var k := s.keys[i]
	if _in_tray[k] == 1:
		_in_tray[k] = 0
		_tray_n -= 1
	else:
		_in_tray[k] = 1
		_tray_n += 1


static func score(s: BoardState, i: int) -> int:
	## Heuristic: prefer tiles that sit high and uncover the most tiles beneath them.
	var geo := s.geo
	var sc := geo.gz[i] * 8
	for t in geo.below[i]:
		if not s.is_removed(t):
			sc += 4 if s.cover_cnt[t] == 1 else 1
	return sc


static func flatten(pairs: Array) -> PackedInt32Array:
	## A classic pair witness as picks. Every pair witness is a tray witness: each pair's
	## second pick clears the first, so the tray never holds more than one tile.
	var out := PackedInt32Array()
	for p in pairs:
		var v: Vector2i = p
		out.append(v.x)
		out.append(v.y)
	return out


static func replay_is_legal(state: BoardState, tray: PackedInt32Array, picks: PackedInt32Array, capacity: int = TrayRules.CAPACITY) -> bool:
	## Verifies a pick sequence on a clone: every pick legal, the tray never fills, the board
	## and the tray both end empty.
	var s := state.clone()
	var t := tray.duplicate()
	for i in picks:
		if not s.take(i):
			return false
		var slot := TrayRules.partner_slot(t, s.keys, i)
		if slot >= 0:
			t.remove_at(slot)
		else:
			t.append(i)
			if t.size() >= capacity:
				return false
	return s.remaining == 0 and t.is_empty()
