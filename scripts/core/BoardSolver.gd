class_name BoardSolver
extends RefCounted
## Bounded depth-first Mahjong Solitaire solver.
##
## Correctness notes:
## - Only legal moves (both tiles free, same match key) are ever applied.
## - SAFE-MOVE rule: if every remaining tile of a match key is currently free, removing them
##   all is never harmful (removals only ever free tiles, and there is no partner choice that
##   can go wrong), so such groups are cleared without branching.
## - Dead states are memoised by Zobrist hash of the removed set (faces are fixed during a
##   solve). A 64-bit collision could in theory wrongly prune a branch; the probability is
##   negligible (~2^-64 per pair of states) and only ever yields a false "unsolvable".
## - Budgets: max_nodes and/or time_budget_ms. Exceeding them returns BUDGET, never a guess.
##   Callers must treat BUDGET as "unknown", not as solvable.

enum Result { SOLVED, UNSOLVABLE, BUDGET }

var max_nodes: int = 250000
var time_budget_ms: int = 0
var nodes: int = 0
var _dead: Dictionary = {}
var _deadline: int = 0
var _aborted: bool = false
var _path: Array[Vector2i] = []


func _init(p_max_nodes: int = 250000, p_time_budget_ms: int = 0) -> void:
	max_nodes = p_max_nodes
	time_budget_ms = p_time_budget_ms


func solve(state: BoardState) -> Dictionary:
	## Returns {"result": Result, "solution": Array[Vector2i], "nodes": int}.
	## The input state is not modified (the solver works on a clone).
	nodes = 0
	_dead.clear()
	_path.clear()
	_aborted = false
	_deadline = Time.get_ticks_msec() + time_budget_ms if time_budget_ms > 0 else 0
	if not state.face_counts_valid():
		return {"result": Result.UNSOLVABLE, "solution": [], "nodes": 0}
	var s := state.clone()
	var r := _dfs(s)
	var sol: Array[Vector2i] = []
	if r == Result.SOLVED:
		sol = _path.duplicate()
	return {"result": r, "solution": sol, "nodes": nodes}


func _dfs(s: BoardState) -> int:
	if s.remaining == 0:
		return Result.SOLVED
	nodes += 1
	if nodes > max_nodes:
		_aborted = true
		return Result.BUDGET
	if _deadline > 0 and (nodes & 255) == 0 and Time.get_ticks_msec() > _deadline:
		_aborted = true
		return Result.BUDGET
	if _dead.has(s.zhash):
		return Result.UNSOLVABLE

	var groups := s.free_by_key()

	# 1) Safe group clearance (no branching).
	for k in groups:
		var g: PackedInt32Array = groups[k]
		if g.size() >= 2 and g.size() == s.key_remaining[k] and g.size() % 2 == 0:
			var applied: Array[Vector2i] = []
			for a in range(0, g.size(), 2):
				var p := Vector2i(g[a], g[a + 1])
				s.remove_pair(p.x, p.y)
				applied.append(p)
			_path.append_array(applied)
			var r := _dfs(s)
			if r == Result.SOLVED:
				return r
			for a in range(applied.size() - 1, -1, -1):
				s.restore_pair(applied[a].x, applied[a].y)
			_path.resize(_path.size() - applied.size())
			if r == Result.UNSOLVABLE:
				_dead[s.zhash] = true
			return r

	# 2) Branch over candidate pairs, best-first.
	var moves: Array = []
	for k in groups:
		var g: PackedInt32Array = groups[k]
		if g.size() < 2:
			continue
		for a in g.size():
			for b in range(a + 1, g.size()):
				moves.append([_score(s, g[a]) + _score(s, g[b]), g[a], g[b]])
	if moves.is_empty():
		_dead[s.zhash] = true
		return Result.UNSOLVABLE
	moves.sort_custom(func(m1: Array, m2: Array) -> bool: return m1[0] > m2[0])

	for m in moves:
		var i: int = m[1]
		var j: int = m[2]
		s.remove_pair(i, j)
		_path.append(Vector2i(i, j))
		var r := _dfs(s)
		if r == Result.SOLVED:
			return r
		_path.pop_back()
		s.restore_pair(i, j)
		if r == Result.BUDGET:
			return r
	_dead[s.zhash] = true
	return Result.UNSOLVABLE


func _score(s: BoardState, i: int) -> int:
	## Heuristic: prefer removing tiles that sit high and unblock many others.
	var geo := s.geo
	var sc := geo.gz[i] * 8 + geo.below[i].size() * 4
	for t in geo.left[i]:
		if not s.is_removed(t):
			sc += 1
	for t in geo.right[i]:
		if not s.is_removed(t):
			sc += 1
	return sc


static func replay_is_legal(state: BoardState, solution: Array) -> bool:
	## Verifies a witness move-by-move on a clone; true only if it clears the whole board.
	var s := state.clone()
	for p in solution:
		var v: Vector2i = p
		if not s.remove_pair(v.x, v.y):
			return false
	return s.remaining == 0
