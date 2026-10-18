class_name DailyGenerator
extends RefCounted
## One deterministic, verified board per calendar date ("YYYY-MM-DD").
##
## The seed is derived only from VERSION + date, so every player (any language, offline)
## gets the same board for the same date, and future app updates do not change boards that
## were already generated: changing the algorithm requires bumping VERSION, and saved
## completions are keyed by date, not by board contents.

const VERSION := "daily-3"  ## daily-3: portrait orientation (daily-2: identical-tiles-only pairs)
const LAYOUTS_PATH := "res://data/levels/layouts_50.json"
const WORLDS := ["aurora_garden", "pearl_coast", "crystal_nocturne"]

static var _layouts: Array = []


static func seed_text_for(date: String) -> String:
	return "%s|%s" % [VERSION, date]


static func is_valid_date(date: String) -> bool:
	var parts := date.split("-")
	if parts.size() != 3 or parts[0].length() != 4:
		return false
	var y := int(parts[0])
	var m := int(parts[1])
	var d := int(parts[2])
	if y < 2000 or m < 1 or m > 12 or d < 1:
		return false
	return d <= days_in_month(y, m)


static func days_in_month(y: int, m: int) -> int:
	if m == 2:
		var leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
		return 29 if leap else 28
	return 30 if m in [4, 6, 9, 11] else 31


static func _load_layouts() -> void:
	if not _layouts.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS_PATH))
	if typeof(parsed) == TYPE_ARRAY:
		_layouts = parsed


static func build(date: String) -> LevelDefinition:
	if not is_valid_date(date):
		return null
	_load_layouts()
	var seed_text := seed_text_for(date)
	var rng := SeededRng.new(SeededRng.hash_string(seed_text))
	var gen := BoardGenerator.new()
	var world: String = WORLDS[absi(SeededRng.hash_string(date)) % WORLDS.size()]
	for attempt in 8:
		var positions: Array = []
		var layout_id := ""
		var candidates: Array = []
		for l in _layouts:
			var n := int(l.get("position_count", 0))
			if n >= 40 and n <= 110:
				candidates.append(l)
		if rng.rand_float() < 0.6 and not candidates.is_empty():
			var l: Dictionary = candidates[rng.rand_int(0, candidates.size() - 1)]
			layout_id = str(l.id)
			for p in l.positions:
				positions.append(Vector3i(int(p[0]) * 2, int(p[1]) * 2, int(p[2])))
		else:
			layout_id = "proc:%s" % LayoutGenerator.VERSION
			positions = LayoutGenerator.generate(rng, rng.rand_int(56, 96))
		if positions.size() < 16:
			continue
		positions = BoardFit.best_orientation(positions)
		var L := gen.generate_level(positions, "%s|%d" % [seed_text, attempt], {
			"key": "daily:" + date, "world": world, "layout_id": layout_id, "difficulty_band": "daily",
		})
		if L.is_valid():
			L.seed_text = seed_text
			return L
	return null
