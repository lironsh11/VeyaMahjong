class_name LevelCatalog
extends RefCounted
## Single source of truth for the shipped journey:
##   levels 1-3    : supplied pack levels, unchanged (gentle follow-ups to the tutorial)
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
	var out: Array = (pack as Array).slice(0, PACK_LEVELS_KEPT)
	var early := _load_range(EARLY_PATH, PACK_LEVELS_KEPT + 1, EARLY_LAST)
	if early.is_empty():
		errors.append("re-scattered levels 4-50 missing or invalid; using pack levels 4-50")
		early = (pack as Array).slice(PACK_LEVELS_KEPT, EARLY_LAST)
	out.append_array(early)
	var later := _load_range(GENERATED_PATH, EARLY_LAST + 1, TOTAL)
	if later.is_empty():
		errors.append("generated levels 51-150 missing or invalid; using pack levels 51-150")
		later = (pack as Array).slice(EARLY_LAST, TOTAL)
	out.append_array(later)
	return out
