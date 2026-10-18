class_name LevelCatalog
extends RefCounted
## Single source of truth for the shipped journey:
##   levels 1-3    : supplied pack levels (gentle follow-ups to the tutorial), same geometry and
##                   witness; bonus pairs made identical for the identical-tiles-only rule
##   levels 4-50   : the pack's own shapes with re-scattered faces, ordered by measured
##                   difficulty (data/levels/levels_004_050_regenerated.json,
##                   tools/build_early_levels.gd). The pack placed ~74% of tiles directly
##                   opposite their identical twin, so boards largely solved themselves.
##   levels 51-150 : generated, validated boards ordered by measured difficulty
##                   (data/levels/levels_051_150_generated.json, tools/build_levels.gd)
## Used by ContentService, the tests and the content validator so they can never disagree.
## Missing or malformed generated files fall back to the pack's own levels (reported).

const PACK_PATH := "res://data/levels/levels_001_150_verified.json"
const EARLY_PATH := "res://data/levels/levels_004_050_regenerated.json"
const GENERATED_PATH := "res://data/levels/levels_051_150_generated.json"
const PACK_LEVELS_KEPT := 3
const EARLY_LAST := 50
const TOTAL := 150


static func _load_range(path: String, first_id: int, last_id: int) -> Array:
	## Returns the dicts if the file holds exactly ids first..last in order, else [].
	if not FileAccess.file_exists(path):
		return []
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(j) != TYPE_ARRAY or (j as Array).size() != last_id - first_id + 1:
		return []
	for i in (j as Array).size():
		if typeof(j[i]) != TYPE_DICTIONARY or int(j[i].get("id", -1)) != first_id + i:
			return []
	return j


static func load_merged(errors: PackedStringArray = PackedStringArray()) -> Array:
	var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_PATH)) if FileAccess.file_exists(PACK_PATH) else null
	if typeof(pack) != TYPE_ARRAY or (pack as Array).size() != TOTAL:
		errors.append("pack levels missing or invalid")
		return []
	var out: Array = []
	for d in (pack as Array).slice(0, PACK_LEVELS_KEPT):
		out.append(identical_pairs(d))
	var early := _load_range(EARLY_PATH, PACK_LEVELS_KEPT + 1, EARLY_LAST)
	if early.is_empty():
		errors.append("re-scattered levels 4-50 missing or invalid; using pack levels 4-50")
		early = (pack as Array).slice(PACK_LEVELS_KEPT, EARLY_LAST).map(identical_pairs)
	out.append_array(early)
	var later := _load_range(GENERATED_PATH, EARLY_LAST + 1, TOTAL)
	if later.is_empty():
		errors.append("generated levels 51-150 missing or invalid; using pack levels 51-150")
		later = (pack as Array).slice(EARLY_LAST, TOTAL).map(identical_pairs)
	out.append_array(later)
	return out


static func identical_pairs(d: Dictionary) -> Dictionary:
	## Owner rule: a tile matches only an identical tile. The pack paired DIFFERENT Flowers (and
	## different Seasons) together; for each such pair in the verified witness, the second tile
	## takes the first tile's face. Geometry and witness order are unchanged, so the witness stays
	## legal and the board stays solvable.
	var out: Dictionary = d.duplicate(true)
	var by_pos := {}
	for i in out.tiles.size():
		var t: Dictionary = out.tiles[i]
		by_pos["%d,%d,%d" % [int(t.x), int(t.y), int(t.z)]] = i
	for step in out.get("verified_solution", []):
		var a: Variant = by_pos.get("%d,%d,%d" % [int(step[0][0]), int(step[0][1]), int(step[0][2])])
		var b: Variant = by_pos.get("%d,%d,%d" % [int(step[1][0]), int(step[1][1]), int(step[1][2])])
		if a == null or b == null:
			continue
		if out.tiles[b].face != out.tiles[a].face:
			out.tiles[b].face = out.tiles[a].face
			out["faces_adjusted_for_identical_rule"] = true
	return out

