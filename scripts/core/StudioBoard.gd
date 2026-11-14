class_name StudioBoard
extends RefCounted
## Board Studio boards: build a board from its share-code settings, check it is winnable, and
## the preset boards Play Together deals.
##
## Determinism contract: a code (StudioCode) must rebuild the identical board on every device
## and in every future version. Everything the v1 build depends on is pinned here instead of
## read from shared live settings: the seed derivation, the area the shape fills, and the
## face generator's tuning. If a shared algorithm (LayoutTemplates, BoardGenerator,
## MahjongRules.FACES order, SeededRng) ever has to change in a way that alters these boards,
## copy the old one next to this file, call it from _build_v1, and give new codes VERSION 2.
## tests/test_studio_code.gd pins fingerprints of real codes to catch that.

const SEED_PREFIX := "studio-1"
## A ready-made board for App Review notes and the store screenshots (pyramid, 72 tiles, 3 layers).
const SAMPLE_CODE := "LS-5VSW-11BK"
const AREA_V1 := Vector2(528, 893)       ## BoardFit.REFERENCE_AREA when v1 was made
const SPREAD_BIAS_V1 := 0.6
const MAX_ATTEMPTS_V1 := 60
const VALIDATE_NODES := 20000
const SMALL_TILE_PX := 70.0
const DIFFICULTIES: PackedStringArray = ["easy", "medium", "hard"]
## Play Together boards. A preset is just a Studio board, so every Duet board has a code.
const PRESETS := {
	"easy": {"families": ["pyramid", "ziggurat", "terraces", "twin"], "tiles": [40, 56], "layers": [2, 3], "cols": [5, 5]},
	"medium": {"families": ["pyramid", "turtle", "bridge", "twin", "ziggurat", "brick"], "tiles": [64, 88], "layers": [3, 4], "cols": [5, 6]},
	"hard": {"families": ["turtle", "bridge", "cross", "frame", "ridge", "brick"], "tiles": [96, 120], "layers": [4, 5], "cols": [6, 6]},
}

static var _cache := {}   ## code -> LevelDefinition (built boards are reused within a run)


static func _shape_rng(p: Dictionary) -> SeededRng:
	## The shape's randomness depends on everything but the tile count, so one seed has one
	## uncarved structure and its exact room (tile_range) is known before choosing a size.
	return SeededRng.new(SeededRng.hash_string("%s|shape|%s|%d|%d|%s|%d" % [SEED_PREFIX, p.family, int(p.cols), int(p.layers), p.mode, int(p.seed)]))


static func positions_for(p: Dictionary) -> Array:
	## The shape only (no faces): the live preview, and step one of build(). [] when this
	## structure cannot be carved to exactly that many tiles.
	if not StudioCode.params_valid(p):
		return []
	return LayoutTemplates.generate(_shape_rng(p), str(p.family), int(p.tiles), int(p.cols), int(p.layers), str(p.mode), AREA_V1)


static func build(p: Dictionary) -> LevelDefinition:
	## The board for these settings, or null when they don't make a board. Not validated.
	## Main thread only (it uses the cache); make() builds without it.
	var code := StudioCode.encode(p)
	if code == "":
		return null
	if _cache.has(code):
		return _cache[code]
	var L := _build_v1(p, code)
	if L != null:
		_cache[code] = L
	return L


static func _build_v1(p: Dictionary, code: String) -> LevelDefinition:
	var positions := positions_for(p)
	if positions.size() != int(p.tiles):
		return null
	var geo := BoardGeometry.from_positions(positions)
	if not geo.errors.is_empty():
		return null
	var gen := BoardGenerator.new()
	gen.spread_bias = SPREAD_BIAS_V1
	gen.max_attempts = MAX_ATTEMPTS_V1
	var res := gen.generate(geo, SeededRng.hash_string("%s|faces|%s" % [SEED_PREFIX, code]))
	if not res.ok:
		return null
	var L := LevelDefinition.new()
	L.unit = LevelDefinition.UNIT_HALF
	L.key = "studio:" + code
	L.seed_text = code
	L.generator_version = SEED_PREFIX
	L.layout_id = "tpl:%s:%s" % [LayoutTemplates.VERSION, p.family]
	L.difficulty_band = "studio"
	for i in geo.count:
		L.tiles.append(TileModel.make(i, geo.gx[i], geo.gy[i], geo.gz[i], res.faces[i]))
	L.solution.assign(res.solution)
	return L


static func from_code(text: String) -> Dictionary:
	## {"err": StudioCode.Err, "code", "params", "level"}. A code that decodes but cannot build a
	## board (shape too small for the tiles) is reported as Err.BOARD.
	var d := StudioCode.decode(text)
	if d.err != StudioCode.Err.OK:
		d["level"] = null
		return d
	var L := build(d.params)
	if L == null or not L.is_valid():
		return {"err": StudioCode.Err.BOARD, "code": d.code, "params": d.params, "level": null}
	d["level"] = L
	return d


static func tile_range(p: Dictionary) -> Vector2i:
	## Even tile counts this shape (family, width, layers, carve, seed) can hold: (min, max), or
	## (0, 0) when it holds too few.
	if not LayoutTemplates.FAMILIES.has(str(p.get("family", ""))):
		return Vector2i.ZERO
	var b := LayoutTemplates.structure(str(p.family), int(p.cols), BoardFit.rows_to_fill(int(p.cols), AREA_V1), int(p.layers), _shape_rng(p))
	var cap := mini(StudioCode.MAX_TILES, b.count())
	cap -= cap % 2
	if cap < StudioCode.MIN_TILES:
		return Vector2i.ZERO
	return Vector2i(StudioCode.MIN_TILES, cap)


static func fit_tiles(p: Dictionary) -> int:
	## The nearest tile count at or below p.tiles (within the shape's room) that this structure
	## can be carved to exactly; 0 if none. The editor uses it so the preview always shows a board.
	var r := tile_range(p)
	if r.y <= 0:
		return 0
	var q := p.duplicate()
	var n := clampi(int(p.tiles), r.x, r.y)
	n -= n % 2
	while n >= r.x:
		q.tiles = n
		if not positions_for(q).is_empty():
			return n
		n -= 2
	return 0


static func make(p: Dictionary) -> Dictionary:
	## Check & Play (worker-thread safe: pure data). Builds the board and proves it winnable;
	## if these exact settings don't make a board, tries the next 8 variations, then up to 8
	## fewer tiles. {"ok", "params" (as built), "code", "level", "band", "adjusted": ""|"seed"|"tiles", "small"}.
	var tries: Array = []
	for k in 9:
		var q := p.duplicate()
		q.seed = (int(p.seed) + k) % (StudioCode.SEED_MAX + 1)
		tries.append([q, "" if k == 0 else "seed"])
	for less in [2, 4, 6, 8]:
		if int(p.tiles) - less >= StudioCode.MIN_TILES:
			var q2 := p.duplicate()
			q2.tiles = int(p.tiles) - less
			tries.append([q2, "tiles"])
	for t in tries:
		var q: Dictionary = t[0]
		var L := _build_v1(q, StudioCode.encode(q))  # no cache: this may run on a worker thread
		if L == null or not L.is_valid():
			continue
		var report := BoardValidator.validate(L, VALIDATE_NODES)
		if not report.ok:
			continue
		var band := str(DifficultyAnalyzer.analyze(L, 12).band)
		var tile_w := BoardFit.fit_tile_width(L.build_geometry(), AREA_V1)
		return {"ok": true, "params": q, "code": StudioCode.encode(q), "level": L, "band": band,
			"adjusted": t[1], "small": tile_w < SMALL_TILE_PX}
	return {"ok": false, "params": p, "code": "", "level": null, "band": "", "adjusted": "", "small": false}


static func preset(difficulty: String, seed_value: int) -> Dictionary:
	## Settings for a Play Together board of this difficulty (always a shape that can be carved
	## to its tile count).
	var cfg: Dictionary = PRESETS.get(difficulty, PRESETS.medium)
	var rng := SeededRng.new(SeededRng.hash_string("%s|preset|%s|%d" % [SEED_PREFIX, difficulty, seed_value]))
	var fams: Array = cfg.families
	for attempt in 16:
		var p := {"family": fams[rng.rand_int(0, fams.size() - 1)], "cols": rng.rand_int(int(cfg.cols[0]), int(cfg.cols[1])),
			"layers": rng.rand_int(int(cfg.layers[0]), int(cfg.layers[1])), "mode": LayoutTemplates.MODES[rng.rand_int(0, 1)],
			"tiles": 2 * rng.rand_int(int(cfg.tiles[0]) / 2, int(cfg.tiles[1]) / 2), "seed": rng.rand_int(0, StudioCode.SEED_MAX)}
		var n := fit_tiles(p)
		if n >= int(cfg.tiles[0]):
			p.tiles = n
			return p
	return {"family": "pyramid", "cols": 5, "layers": 3, "mode": "top", "tiles": int(cfg.tiles[0]), "seed": seed_value % (StudioCode.SEED_MAX + 1)}


static func remember(L: LevelDefinition) -> void:
	## Main thread only: keep a board made on a worker thread for the screen that plays it.
	if L != null and L.key.begins_with("studio:"):
		_cache[L.key.trim_prefix("studio:")] = L


static func clear_cache() -> void:
	_cache.clear()
