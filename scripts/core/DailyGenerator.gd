class_name DailyGenerator
extends RefCounted
## One deterministic, verified board per calendar date ("YYYY-MM-DD").
##
## The seed is derived only from VERSION + date, so every player (any language, offline)
## gets the same board for the same date, and future app updates do not change boards that
## were already generated: changing the algorithm requires bumping VERSION, and saved
## completions are keyed by date, not by board contents.

const VERSION := "daily-5"  ## daily-5: layered template boards (daily-4: dense grids; daily-3: portrait pack/proc)
## Medium, readable structures for a daily board (LayoutTemplates).
const FAMILIES: PackedStringArray = ["pyramid", "turtle", "bridge", "twin", "ziggurat", "brick"]
const MIN_FIT_TILE := 84.0
const MIN_FILL := 0.88
const WORLDS := ["aurora_garden", "pearl_coast", "crystal_nocturne"]


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


static func build(date: String) -> LevelDefinition:
	if not is_valid_date(date):
		return null
	var seed_text := seed_text_for(date)
	var rng := SeededRng.new(SeededRng.hash_string(seed_text))
	var gen := BoardGenerator.new()
	var world: String = WORLDS[absi(SeededRng.hash_string(date)) % WORLDS.size()]
	var fallback: LevelDefinition = null
	for attempt in 12:
		# A medium layered board that fills the play area both ways (LayoutTemplates).
		var cols := 6 if rng.rand_float() < 0.75 else 5
		var layers := rng.rand_int(3, 4)
		var family: String = FAMILIES[rng.rand_int(0, FAMILIES.size() - 1)]
		var layout_id := "tpl:%s:%s" % [LayoutTemplates.VERSION, family]
		var target := 2 * rng.rand_int(28, 48)
		var positions := LayoutTemplates.generate(rng, family, target, cols, layers, LayoutTemplates.MODES[rng.rand_int(0, 1)])
		if positions.size() < 16 or LayoutTemplates.layer_count(positions) < 3:
			continue
		var L := gen.generate_level(positions, "%s|%d" % [seed_text, attempt], {
			"key": "daily:" + date, "world": world, "layout_id": layout_id, "difficulty_band": "daily",
		})
		if not L.is_valid():
			continue
		L.seed_text = seed_text
		var geo := BoardGeometry.from_positions(positions)
		var fr := LayoutGenerator.fill_ratio(positions)
		if BoardFit.fit_tile_width(geo, BoardFit.REFERENCE_AREA) >= MIN_FIT_TILE and fr.x >= MIN_FILL and fr.y >= MIN_FILL:
			return L
		if fallback == null:
			fallback = L
	if fallback == null:
		# Never reached in the tested range; a staggered pyramid always has room for 64 tiles.
		var pos := LayoutTemplates.generate(rng, "pyramid", 64, 6, 4, "edge")
		fallback = gen.generate_level(pos, "%s|fallback" % seed_text, {
			"key": "daily:" + date, "world": world, "layout_id": "tpl:%s:pyramid" % LayoutTemplates.VERSION, "difficulty_band": "daily",
		})
		fallback.seed_text = seed_text
	return fallback
