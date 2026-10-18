class_name LevelDefinition
extends RefCounted
## Validated, typed view of one level / daily board definition.
##
## External JSON is never trusted: from_dict() collects errors instead of crashing, and
## callers must check is_valid() before building a board.

const UNIT_TILE := "tile"   ## pack convention: integer whole-tile coordinates
const UNIT_HALF := "half"   ## half-tile coordinates (allows offset rows / caps)

var id: int = 0
var key: String = ""                  ## stable identity, e.g. "level:12" or "daily:2026-10-18"
var world: String = ""
var layout_id: String = ""
var difficulty_band: String = ""
var unit: String = UNIT_TILE
var tiles: Array[TileModel] = []
var solution: Array[Vector2i] = []    ## witness as pairs of tile indices
var generator_version: String = ""    ## empty for handcrafted/pack levels
var seed_text: String = ""
var errors := PackedStringArray()


static func from_dict(d: Dictionary, p_key: String = "") -> LevelDefinition:
	var L := LevelDefinition.new()
	L.id = int(d.get("id", 0))
	L.key = p_key if p_key != "" else "level:%d" % L.id
	L.world = str(d.get("world", ""))
	L.layout_id = str(d.get("layout_id", ""))
	L.difficulty_band = str(d.get("difficulty_band", ""))
	L.unit = str(d.get("unit", UNIT_TILE))
	L.generator_version = str(d.get("generator_version", ""))
	L.seed_text = str(d.get("seed", ""))
	if L.unit != UNIT_TILE and L.unit != UNIT_HALF:
		L.errors.append("unknown coordinate unit '%s'" % L.unit)
		return L
	var mul := 2 if L.unit == UNIT_TILE else 1
	var raw_tiles: Variant = d.get("tiles", null)
	if typeof(raw_tiles) != TYPE_ARRAY or (raw_tiles as Array).is_empty():
		L.errors.append("missing tiles")
		return L
	var by_pos := {}
	for t in raw_tiles:
		if typeof(t) != TYPE_DICTIONARY:
			L.errors.append("tile entry is not an object")
			return L
		var face := str(t.get("face", ""))
		if not MahjongRules.is_valid_face(face):
			L.errors.append("unknown face '%s'" % face)
		if not (_is_int_like(t.get("x")) and _is_int_like(t.get("y")) and _is_int_like(t.get("z"))):
			L.errors.append("non-integer tile coordinate")
			return L
		var tm := TileModel.make(L.tiles.size(), int(t.x) * mul, int(t.y) * mul, int(t.z), face)
		by_pos[BoardGeometry.pos_key(tm.gx, tm.gy, tm.z)] = tm.id
		L.tiles.append(tm)
	if "tile_count" in d and int(d.tile_count) != L.tiles.size():
		L.errors.append("tile_count %d does not match %d tiles" % [int(d.tile_count), L.tiles.size()])
	if L.tiles.size() % 2 != 0:
		L.errors.append("odd tile count %d" % L.tiles.size())
	var raw_solution: Variant = d.get("verified_solution", d.get("solution", []))
	if typeof(raw_solution) == TYPE_ARRAY:
		for step in raw_solution:
			var pair := _parse_step(step, by_pos, mul)
			if pair.x < 0:
				L.errors.append("solution references unknown position")
				L.solution.clear()
				break
			L.solution.append(pair)
	return L


static func _is_int_like(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return is_equal_approx(v, roundf(v))
	return false


static func _parse_step(step: Variant, by_pos: Dictionary, mul: int) -> Vector2i:
	# Pack format: [[x,y,z],[x,y,z]] ; generated format: [i, j] tile indices
	if typeof(step) != TYPE_ARRAY or (step as Array).size() != 2:
		return Vector2i(-1, -1)
	var a: Variant = step[0]
	var b: Variant = step[1]
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY and a.size() == 3 and b.size() == 3:
		var ka := BoardGeometry.pos_key(int(a[0]) * mul, int(a[1]) * mul, int(a[2]))
		var kb := BoardGeometry.pos_key(int(b[0]) * mul, int(b[1]) * mul, int(b[2]))
		if not by_pos.has(ka) or not by_pos.has(kb):
			return Vector2i(-1, -1)
		return Vector2i(by_pos[ka], by_pos[kb])
	if _is_int_like(a) and _is_int_like(b):
		return Vector2i(int(a), int(b))
	return Vector2i(-1, -1)


func is_valid() -> bool:
	return errors.is_empty()


func positions() -> Array:
	var out: Array = []
	for t in tiles:
		out.append(Vector3i(t.gx, t.gy, t.z))
	return out


func faces() -> PackedStringArray:
	var out := PackedStringArray()
	for t in tiles:
		out.append(t.face)
	return out


func build_geometry() -> BoardGeometry:
	return BoardGeometry.from_positions(positions())


func build_state(geo: BoardGeometry = null) -> BoardState:
	if geo == null:
		geo = build_geometry()
	return BoardState.create(geo, faces())


func to_dict() -> Dictionary:
	## Serialises in half units with an index-based witness (used for generated boards).
	var t_out: Array = []
	for t in tiles:
		t_out.append({"x": t.gx, "y": t.gy, "z": t.z, "face": t.face})
	var s_out: Array = []
	for p in solution:
		s_out.append([p.x, p.y])
	return {
		"id": id, "world": world, "layout_id": layout_id, "difficulty_band": difficulty_band,
		"unit": UNIT_HALF, "tile_count": tiles.size(), "tiles": t_out, "solution": s_out,
		"generator_version": generator_version, "seed": seed_text,
	}
