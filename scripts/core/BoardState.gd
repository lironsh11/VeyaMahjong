class_name BoardState
extends RefCounted
## Mutable board: which tiles remain and which face each slot shows.
##
## Tray rules (the game's only mode): a tile can be picked when nothing lies on top of it.
## Classic side blocking (left AND right neighbours) stays behind `side_blocking` for tools
## and tests; play never turns it on.
##
## Freedom is maintained incrementally: each tile keeps counts of remaining covering tiles
## and remaining left/right neighbours, updated in O(neighbours) on every removal/restore.
## This keeps per-tap work tiny and lets the solver explore many states cheaply.
## Pure data (no nodes) so it can be cloned onto worker threads.

var geo: BoardGeometry
var faces := PackedStringArray()
var keys := PackedInt32Array()          ## match-key id per tile (Flowers/Seasons share one)
var removed := PackedByteArray()
var cover_cnt := PackedInt32Array()
var left_cnt := PackedInt32Array()
var right_cnt := PackedInt32Array()
var key_remaining := PackedInt32Array() ## remaining tiles per match key
var remaining: int = 0
var zhash: int = 0                      ## Zobrist hash of the removed set
var side_blocking: bool = false         ## classic rule: a tile also needs a free left or right side


static func create(p_geo: BoardGeometry, p_faces: PackedStringArray) -> BoardState:
	var s := BoardState.new()
	s.geo = p_geo
	var n := p_geo.count
	s.removed.resize(n)
	s.removed.fill(0)
	s.cover_cnt.resize(n)
	s.left_cnt.resize(n)
	s.right_cnt.resize(n)
	for i in n:
		s.cover_cnt[i] = p_geo.above[i].size()
		s.left_cnt[i] = p_geo.left[i].size()
		s.right_cnt[i] = p_geo.right[i].size()
	s.remaining = n
	s._assign_faces(p_faces)
	return s


func _assign_faces(p_faces: PackedStringArray) -> void:
	faces = p_faces.duplicate()
	keys.resize(faces.size())
	key_remaining.resize(MahjongRules.key_count())
	key_remaining.fill(0)
	for i in faces.size():
		keys[i] = MahjongRules.key_id(faces[i])
		if removed[i] == 0 and keys[i] >= 0:
			key_remaining[keys[i]] += 1


func clone() -> BoardState:
	var s := BoardState.new()
	s.geo = geo
	s.faces = faces.duplicate()
	s.keys = keys.duplicate()
	s.removed = removed.duplicate()
	s.cover_cnt = cover_cnt.duplicate()
	s.left_cnt = left_cnt.duplicate()
	s.right_cnt = right_cnt.duplicate()
	s.key_remaining = key_remaining.duplicate()
	s.remaining = remaining
	s.zhash = zhash
	s.side_blocking = side_blocking
	return s


func size() -> int:
	return geo.count


func is_removed(i: int) -> bool:
	return removed[i] != 0


func is_covered(i: int) -> bool:
	return cover_cnt[i] > 0


func is_free(i: int) -> bool:
	if removed[i] != 0 or cover_cnt[i] != 0:
		return false
	return not side_blocking or left_cnt[i] == 0 or right_cnt[i] == 0


func can_pair(i: int, j: int) -> bool:
	if i == j or i < 0 or j < 0 or i >= geo.count or j >= geo.count:
		return false
	return is_free(i) and is_free(j) and keys[i] == keys[j] and keys[i] >= 0


func remove_pair(i: int, j: int) -> bool:
	## Validates and applies a match. Returns false (and changes nothing) if illegal.
	if not can_pair(i, j):
		return false
	_remove(i)
	_remove(j)
	key_remaining[keys[i]] -= 2
	return true


func restore_pair(i: int, j: int) -> void:
	## Exact inverse of remove_pair (used by undo and the solver's backtracking).
	_restore(j)
	_restore(i)
	key_remaining[keys[i]] += 2


func take(i: int) -> bool:
	## Picks one free tile off the board (into the tray). Returns false if it is not free.
	if i < 0 or i >= geo.count or not is_free(i) or keys[i] < 0:
		return false
	_remove(i)
	key_remaining[keys[i]] -= 1
	return true


func put_back(i: int) -> void:
	## Exact inverse of take (undo, and tiles sent back from the tray).
	_restore(i)
	key_remaining[keys[i]] += 1


func _remove(k: int) -> void:
	removed[k] = 1
	remaining -= 1
	zhash ^= geo.zobrist[k]
	for t in geo.right[k]:
		left_cnt[t] -= 1
	for t in geo.left[k]:
		right_cnt[t] -= 1
	for t in geo.below[k]:
		cover_cnt[t] -= 1


func _restore(k: int) -> void:
	removed[k] = 0
	remaining += 1
	zhash ^= geo.zobrist[k]
	for t in geo.right[k]:
		left_cnt[t] += 1
	for t in geo.left[k]:
		right_cnt[t] += 1
	for t in geo.below[k]:
		cover_cnt[t] += 1


func free_tiles() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in geo.count:
		if is_free(i):
			out.append(i)
	return out


func free_by_key() -> Dictionary:
	## key id -> PackedInt32Array of free tiles with that key
	var groups := {}
	for i in geo.count:
		if is_free(i):
			var k := keys[i]
			if not groups.has(k):
				groups[k] = PackedInt32Array()
			groups[k].append(i)
	return groups


func available_pairs() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var groups := free_by_key()
	for k in groups:
		var g: PackedInt32Array = groups[k]
		for a in g.size():
			for b in range(a + 1, g.size()):
				out.append(Vector2i(g[a], g[b]))
	return out


func has_moves() -> bool:
	var seen := {}
	for i in geo.count:
		if is_free(i):
			if seen.has(keys[i]):
				return true
			seen[keys[i]] = true
	return false


func is_won() -> bool:
	return remaining == 0


func remaining_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in geo.count:
		if removed[i] == 0:
			out.append(i)
	return out


func set_faces(p_faces: PackedStringArray) -> void:
	## Used by Shuffle/Rescue: same geometry and removed set, new face arrangement.
	_assign_faces(p_faces)


func removed_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in geo.count:
		if removed[i] != 0:
			out.append(i)
	return out


func apply_removed(indices: PackedInt32Array) -> bool:
	## Restores a serialized removed-set onto a fresh state (no legality replay).
	for i in indices:
		if i < 0 or i >= geo.count or removed[i] != 0:
			return false
		_remove(i)
		key_remaining[keys[i]] -= 1
	return true


func face_counts_valid(tray: PackedInt32Array = PackedInt32Array()) -> bool:
	## Every match key must have an even number of tiles still in play (board + tray) or the
	## board can't clear.
	var counts := key_remaining.duplicate()
	for i in tray:
		if i < 0 or i >= geo.count or keys[i] < 0:
			return false
		counts[keys[i]] += 1
	for k in counts.size():
		if counts[k] % 2 != 0:
			return false
	return true
