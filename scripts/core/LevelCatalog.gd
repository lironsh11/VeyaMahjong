class_name LevelCatalog
extends RefCounted
## Single source of truth for the shipped journey: 6 worlds x 100 levels (600 since 1.1.0).
## Used by ContentService, the tests and the content validator so they can never disagree.
##
## The game reads only data/levels/world_1.json ... world_6.json (minified, 100 levels each),
## written by tools/build_catalog.gd from the source files below. World w holds levels
## 100(w-1)+1 .. 100w:
##   - its first 50 are the 1.0 boards in the same order: 1.0 level o = 50(w-1)+k is level
##     100(w-1)+k since 1.1.0 (GameState migrates saves, see GameState.migrate_level_ids)
##   - its last 50 were added in 1.1.0 (tools/build_levels.gd --range=w<w>): they start where
##     the world's level 50 ends and finish a little harder, so the next world opens with a short
##     breather before it climbs again
##
## Sources (1.0 numbering for the first four; export_presets.cfg keeps data/levels/levels_* out
## of the app):
##   1.0 levels 1-3    : supplied pack levels, bonus pairs made identical (identical_pairs)
##   1.0 levels 4-50   : levels_004_050_regenerated.json (tools/build_early_levels.gd)
##   1.0 levels 51-150 : levels_051_150_generated.json (tools/build_levels.gd --range=51-150)
##   1.0 levels 151-300: levels_151_300_generated.json (tools/build_levels.gd --range=151-300)
##   1.1 second halves : levels_w<w>_051_100_generated.json, final ids (build_levels --range=w<w>)

const WORLD_PATH := "res://data/levels/world_%d.json"
const PACK_PATH := "res://data/levels/levels_001_150_verified.json"
const EARLY_PATH := "res://data/levels/levels_004_050_regenerated.json"
const GENERATED_PATH := "res://data/levels/levels_051_150_generated.json"
const LATE_PATH := "res://data/levels/levels_151_300_generated.json"
const HALF_PATH := "res://data/levels/levels_w%d_051_100_generated.json"
const WORLDS := 6
const PER_WORLD := 100
const TOTAL := WORLDS * PER_WORLD
const LEGACY_PER_WORLD := 50
const LEGACY_TOTAL := WORLDS * LEGACY_PER_WORLD
const PACK_LEVELS_KEPT := 3
const EARLY_LAST := 50
const PACK_TOTAL := 150
## Owner rule (2026-10-22): boards grow with the journey; a later level never drops back to a
## small board. Piecewise-linear [1.0 level, tiles]; 1.0 levels 1-3 (pack) have no floor. Since
## 1.1.0 a level's floor is read at its place on this scale (legacy_position).
const LEGACY_TILE_FLOOR := [[4, 24], [50, 60], [51, 64], [150, 112], [151, 112], [300, 128]]
## Builds order boards by their own difficulty, which can move a board a few places from the
## slot its floor was checked for; this much below the floor is tolerated.
const TILE_FLOOR_SLACK := 4


static func world_of(level_id: int) -> int:
	## 1-based world index of a level (1.1.0 numbering).
	return (level_id - 1) / PER_WORLD + 1


static func new_id(legacy_id: int) -> int:
	## 1.0 level id (50 per world) -> 1.1.0 level id (100 per world).
	var w := (legacy_id - 1) / LEGACY_PER_WORLD
	return legacy_id + w * (PER_WORLD - LEGACY_PER_WORLD)


static func legacy_position(level_id: float) -> float:
	## Where a level sits on the 1.0 scale (1-300). A world's first 50 levels are 1.0 levels; its
	## second half sits between its 1.0 level 50 and the next world's first 1.0 level.
	var w := int(floor((level_id - 1.0) / PER_WORLD))
	var k := level_id - w * PER_WORLD
	if k <= LEGACY_PER_WORLD:
		return w * LEGACY_PER_WORLD + k
	return w * LEGACY_PER_WORLD + LEGACY_PER_WORLD + (k - LEGACY_PER_WORLD) / float(PER_WORLD - LEGACY_PER_WORLD + 1)


static func min_tiles(level_id: float) -> int:
	## The fewest tiles a board at this level may have (1.1.0 numbering; 0 for levels 1-3).
	return legacy_min_tiles(legacy_position(level_id))


static func legacy_min_tiles(position: float) -> int:
	## The floor at a place on the 1.0 scale (0 before 1.0 level 4).
	if position < LEGACY_TILE_FLOOR[0][0]:
		return 0
	for i in range(1, LEGACY_TILE_FLOOR.size()):
		var a: Array = LEGACY_TILE_FLOOR[i - 1]
		var b: Array = LEGACY_TILE_FLOOR[i]
		if position <= b[0]:
			return int(round(lerpf(a[1], b[1], (position - a[0]) / float(b[0] - a[0]))))
	return LEGACY_TILE_FLOOR.back()[1]


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


static func load_world(w: int) -> Array:
	## The shipped levels of world w (1-based), or [] if its file is missing or malformed.
	return _load_range(WORLD_PATH % w, (w - 1) * PER_WORLD + 1, w * PER_WORLD)


static func load_merged(errors: PackedStringArray = PackedStringArray()) -> Array:
	## All shipped levels, ids 1..TOTAL. A missing or malformed world file ends the journey
	## before that world (reported).
	var out: Array = []
	for w in range(1, WORLDS + 1):
		var part := load_world(w)
		if part.is_empty():
			errors.append("world %d levels missing or invalid; the journey ends at level %d" % [w, out.size()])
			break
		out.append_array(part)
	return out


static func load_legacy(errors: PackedStringArray = PackedStringArray()) -> Array:
	## The 1.0 journey (300 levels, 1.0 ids and worlds) from the source files. Tools only.
	var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_PATH)) if FileAccess.file_exists(PACK_PATH) else null
	if typeof(pack) != TYPE_ARRAY or (pack as Array).size() != PACK_TOTAL:
		errors.append("pack levels missing or invalid")
		return []
	var out: Array = []
	for d in (pack as Array).slice(0, PACK_LEVELS_KEPT):
		out.append(identical_pairs(d))
	for part in [[EARLY_PATH, PACK_LEVELS_KEPT + 1, EARLY_LAST], [GENERATED_PATH, EARLY_LAST + 1, PACK_TOTAL], [LATE_PATH, PACK_TOTAL + 1, LEGACY_TOTAL]]:
		var got := _load_range(part[0], part[1], part[2])
		if got.is_empty():
			errors.append("%s missing or invalid" % part[0])
			return []
		out.append_array(got)
	return out


static func assemble(errors: PackedStringArray = PackedStringArray()) -> Array:
	## The full 1.1.0 journey from the source files (what tools/build_catalog.gd writes). Each
	## world: its 50 1.0 levels renumbered, then its 50 second-half levels. Tools and tests only.
	var legacy := load_legacy(errors)
	if legacy.is_empty():
		return []
	var out: Array = []
	for w in range(1, WORLDS + 1):
		for d in legacy.slice((w - 1) * LEGACY_PER_WORLD, w * LEGACY_PER_WORLD):
			var e: Dictionary = (d as Dictionary).duplicate(true)
			e.id = new_id(int(d.id))
			out.append(e)
		var half := _load_range(HALF_PATH % w, (w - 1) * PER_WORLD + LEGACY_PER_WORLD + 1, w * PER_WORLD)
		if half.is_empty():
			errors.append("%s missing or invalid" % (HALF_PATH % w))
			return []
		out.append_array(half)
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
