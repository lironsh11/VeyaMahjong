class_name ShuffleRescue
extends RefCounted
## Shuffle / Rescue: rearranges the faces of the tiles still ON THE BOARD so the board plus
## the tray is provably clearable again. Tiles already in the tray keep their faces.
##
## Guarantee: a random legal pick order of the board tiles is built first (there always is
## one: the leftmost tile of the highest layer is always free). The first picks get the twins of the tray tiles, so
## each clears a tray slot; the rest get matching pairs on consecutive picks, so the tray never
## holds more than one tile. The order is then independently replayed with TraySolver.
##
## The multiset of faces is preserved exactly, so progress/score cannot change.

const MAX_ATTEMPTS := 40


static func rescue(state: BoardState, seed_value: int, tray: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	## Returns {"ok": bool, "faces": PackedStringArray, "solution": PackedInt32Array (picks), "reason": String}
	var present := state.remaining_indices()
	if present.is_empty():
		return _fail("empty")
	if not state.face_counts_valid(tray) or not TrayRules.keys_valid(tray, state.keys):
		return _fail("odd_faces")
	var by_key := {}
	for i in present:
		var k := state.keys[i]
		if not by_key.has(k):
			by_key[k] = []
		by_key[k].append(state.faces[i])
	# One face per tray tile is reserved for its twin; the rest pair up by key.
	var singles: Array = []
	for t in tray:
		var fs: Array = by_key.get(state.keys[t], [])
		if fs.is_empty():
			return _fail("odd_faces")
		singles.append(fs.pop_back())
	var base_pairs: Array = []
	for k in by_key:
		var fs: Array = by_key[k]
		for a in range(0, fs.size(), 2):
			base_pairs.append([fs[a], fs[a + 1]])
	var rng := SeededRng.new(seed_value)
	for attempt in MAX_ATTEMPTS:
		var order := pick_order(state.geo, rng, present)
		if order.size() != present.size():
			continue
		var pairs := base_pairs.duplicate()
		rng.shuffle(pairs)
		var new_faces := state.faces.duplicate()
		var n := 0
		for f in singles:
			new_faces[order[n]] = f
			n += 1
		for p in pairs:
			new_faces[order[n]] = p[0]
			new_faces[order[n + 1]] = p[1]
			n += 2
		# Avoid "shuffles" that leave the board visually identical when an alternative exists.
		if new_faces == state.faces and attempt < MAX_ATTEMPTS - 1:
			continue
		var trial := state.clone()
		trial.set_faces(new_faces)
		if TraySolver.replay_is_legal(trial, tray, order):
			return {"ok": true, "faces": new_faces, "solution": order, "reason": ""}
	return _fail("geometry")


static func pick_order(geo: BoardGeometry, rng: SeededRng, present: PackedInt32Array) -> PackedInt32Array:
	## A random legal single-pick order for the occupied slots (faces are irrelevant).
	var dummy := PackedStringArray()
	dummy.resize(geo.count)
	dummy.fill("dragon_white")
	var s := BoardState.create(geo, dummy)
	var keep := {}
	for i in present:
		keep[i] = true
	var gone := PackedInt32Array()
	for i in geo.count:
		if not keep.has(i):
			gone.append(i)
	s.apply_removed(gone)
	var out := PackedInt32Array()
	while s.remaining > 0:
		var free := s.free_tiles()
		if free.is_empty():
			return PackedInt32Array()
		var a: int = free[rng.rand_int(0, free.size() - 1)]
		s._remove(a)
		out.append(a)
	return out


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "faces": PackedStringArray(), "solution": PackedInt32Array(), "reason": reason}
