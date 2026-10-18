class_name ShuffleRescue
extends RefCounted
## Shuffle / Rescue: rearranges the faces of the REMAINING tiles on the CURRENT geometry so
## the board is provably clearable again.
##
## Guarantee: the new arrangement is built from a legal removal order of the remaining slots
## (same reverse-play method as BoardGenerator) and is then independently replayed. If no
## clearing order exists for the remaining slots (e.g. two tiles stacked on each other), no
## face arrangement can help and we report failure honestly so the UI can offer free
## alternatives (undo to a checkpoint or restart) instead of a fake shuffle.
##
## The multiset of remaining faces is preserved exactly, so progress/score cannot change.

const MAX_ATTEMPTS := 40


static func rescue(state: BoardState, seed_value: int) -> Dictionary:
	## Returns {"ok": bool, "faces": PackedStringArray, "solution": Array[Vector2i], "reason": String}
	var present := state.remaining_indices()
	if present.is_empty():
		return {"ok": false, "faces": PackedStringArray(), "solution": [], "reason": "empty"}
	if not state.face_counts_valid():
		return {"ok": false, "faces": PackedStringArray(), "solution": [], "reason": "odd_faces"}
	# Group remaining faces into matching pairs (by match key; Flowers pair with Flowers).
	var by_key := {}
	for i in present:
		var k := state.keys[i]
		if not by_key.has(k):
			by_key[k] = []
		by_key[k].append(state.faces[i])
	var base_pairs: Array = []
	for k in by_key:
		var fs: Array = by_key[k]
		for a in range(0, fs.size(), 2):
			base_pairs.append([fs[a], fs[a + 1]])
	var gen := BoardGenerator.new()
	var rng := SeededRng.new(seed_value)
	for attempt in MAX_ATTEMPTS:
		var order := gen.removal_order(state.geo, rng, present)
		if order.is_empty():
			continue
		var pairs := base_pairs.duplicate()
		rng.shuffle(pairs)
		var new_faces := state.faces.duplicate()
		for n in order.size():
			new_faces[order[n].x] = pairs[n][0]
			new_faces[order[n].y] = pairs[n][1]
		# Avoid "shuffles" that leave the board visually identical when an alternative exists.
		if new_faces == state.faces and attempt < MAX_ATTEMPTS - 1:
			continue
		var trial := state.clone()
		trial.set_faces(new_faces)
		if BoardSolver.replay_is_legal(trial, order):
			return {"ok": true, "faces": new_faces, "solution": order, "reason": ""}
	return {"ok": false, "faces": PackedStringArray(), "solution": [], "reason": "geometry"}
