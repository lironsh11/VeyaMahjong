class_name BoardGenerator
extends RefCounted
## Deterministic, solvable-by-construction face assignment for a fixed geometry.
##
## Method ("reverse play"): start with every slot occupied, repeatedly pick two slots that are
## geometrically free *right now* and remove them together. The sequence of removed slot pairs
## is a legal clearing order for ANY faces, so assigning each removed slot-pair a matching face
## pair yields a board that is solvable by that witness. The witness is then independently
## replayed through BoardState's rules (forward validation) before the board is accepted.
##
## Physical layout difficulty (geometry) is separate from face order (this class + seed).

const VERSION := "gen-1"

## Removal order bias: 0 = uniform among free slots, higher = prefer far-apart pairs
## (gives less trivially "adjacent twins" boards).
var spread_bias: float = 0.6
var max_attempts: int = 60


func removal_order(geo: BoardGeometry, rng: SeededRng, present: PackedInt32Array = PackedInt32Array()) -> Array[Vector2i]:
	## Returns a legal pair-removal order for the occupied slots, or [] if the geometry
	## cannot be cleared from this configuration (e.g. a lone 2-high stack).
	var dummy := PackedStringArray()
	dummy.resize(geo.count)
	dummy.fill("dragon_white")
	var s := BoardState.create(geo, dummy)
	if not present.is_empty():
		var keep := {}
		for i in present:
			keep[i] = true
		var gone := PackedInt32Array()
		for i in geo.count:
			if not keep.has(i):
				gone.append(i)
		s.apply_removed(gone)
	var order: Array[Vector2i] = []
	while s.remaining > 0:
		var free := s.free_tiles()
		if free.size() < 2:
			return []
		var a: int = free[rng.rand_int(0, free.size() - 1)]
		var b := _pick_partner(geo, free, a, rng)
		# Free-ness is evaluated before either removal, so both are legal together.
		s._remove(a)
		s._remove(b)
		order.append(Vector2i(a, b))
	return order


func _pick_partner(geo: BoardGeometry, free: PackedInt32Array, a: int, rng: SeededRng) -> int:
	var best := -1
	var best_score := -1.0
	for c in free:
		if c == a:
			continue
		var dist := float(absi(geo.gx[c] - geo.gx[a]) + absi(geo.gy[c] - geo.gy[a])) + 2.0 * absi(geo.gz[c] - geo.gz[a])
		var score := rng.rand_float() * (1.0 - spread_bias) * 40.0 + dist * spread_bias
		if score > best_score:
			best_score = score
			best = c
	return best


static func face_pairs_for(tile_count: int, rng: SeededRng, allow_bonus: bool = true) -> Array:
	## Builds tile_count/2 matching face pairs. Faces are used in sets of four (two pairs),
	## like a real Mahjong set; Flowers/Seasons are paired across different bonus faces.
	var groups: Array = []
	for f in MahjongRules.FACES:
		if not MahjongRules.is_bonus(f):
			groups.append([[f, f], [f, f]])
	if allow_bonus:
		var fl: Array = MahjongRules.DEFAULT_GROUPS.flower.duplicate()
		var se: Array = MahjongRules.DEFAULT_GROUPS.season.duplicate()
		rng.shuffle(fl)
		rng.shuffle(se)
		groups.append([[fl[0], fl[1]], [fl[2], fl[3]]])
		groups.append([[se[0], se[1]], [se[2], se[3]]])
	rng.shuffle(groups)
	var pairs: Array = []
	var gi := 0
	while pairs.size() * 2 < tile_count:
		var grp: Array = groups[gi % groups.size()]
		pairs.append(grp[0])
		if pairs.size() * 2 < tile_count:
			pairs.append(grp[1])
		gi += 1
	rng.shuffle(pairs)
	return pairs


func generate(geo: BoardGeometry, seed_value: int, allow_bonus: bool = true) -> Dictionary:
	## Returns {"ok": bool, "faces": PackedStringArray, "solution": Array[Vector2i], "attempts": int}
	if geo.count % 2 != 0 or not geo.errors.is_empty():
		return {"ok": false, "faces": PackedStringArray(), "solution": [], "attempts": 0}
	var rng := SeededRng.new(seed_value)
	for attempt in max_attempts:
		var order := removal_order(geo, rng)
		if order.is_empty():
			continue
		var pairs := face_pairs_for(geo.count, rng, allow_bonus)
		var faces := PackedStringArray()
		faces.resize(geo.count)
		for k in order.size():
			faces[order[k].x] = pairs[k][0]
			faces[order[k].y] = pairs[k][1]
		var state := BoardState.create(geo, faces)
		if BoardSolver.replay_is_legal(state, order):
			return {"ok": true, "faces": faces, "solution": order, "attempts": attempt + 1}
	return {"ok": false, "faces": PackedStringArray(), "solution": [], "attempts": max_attempts}


func generate_level(positions: Array, seed_text: String, meta: Dictionary = {}) -> LevelDefinition:
	## Full pipeline: geometry -> solvable faces -> LevelDefinition with witness + metadata.
	var geo := BoardGeometry.from_positions(positions)
	var res := generate(geo, SeededRng.hash_string(VERSION + "|" + seed_text), meta.get("allow_bonus", true))
	var L := LevelDefinition.new()
	L.unit = LevelDefinition.UNIT_HALF
	L.seed_text = seed_text
	L.generator_version = VERSION
	L.id = int(meta.get("id", 0))
	L.key = str(meta.get("key", "gen:" + seed_text))
	L.world = str(meta.get("world", ""))
	L.layout_id = str(meta.get("layout_id", ""))
	L.difficulty_band = str(meta.get("difficulty_band", ""))
	if not res.ok:
		L.errors.append("generator could not build a solvable board")
		return L
	for i in geo.count:
		L.tiles.append(TileModel.make(i, geo.gx[i], geo.gy[i], geo.gz[i], res.faces[i]))
	L.solution.assign(res.solution)
	return L
