extends Node
## Read-only game content (levels, worlds, Bloom, cosmetics) and texture access.
##
## Memory policy: tile atlases and backgrounds are loaded on demand and cached by path;
## release_inactive() drops everything except the active world/theme (called on OS memory
## warnings and world changes) so only one world and one tile theme stay resident.

const WORLDS_PATH := "res://data/config/worlds.json"
const BLOOM_PATH := "res://data/config/bloom.json"
const COSMETICS_PATH := "res://data/config/cosmetics.json"
const RULES_PATH := "res://data/levels/tile_match_rules.json"
const ASSET_ROOT := "res://assets/veya/"
const WORLD_NAME_KEYS := {"aurora_garden": "world_aurora", "pearl_coast": "world_coast", "crystal_nocturne": "world_nocturne"}

var level_dicts: Array = []
var worlds: Array = []
var bloom: Dictionary = {}
var cosmetics: Dictionary = {}
var load_errors := PackedStringArray()
var _level_cache: Dictionary = {}
var _tex_cache: Dictionary = {}
var _atlas_maps: Dictionary = {}
var active_world: String = "aurora_garden"
var active_theme: String = "classic"


func _ready() -> void:
	load_content()


func load_content() -> void:
	load_errors.clear()
	var rules: Variant = _read_json(RULES_PATH)
	if typeof(rules) != TYPE_DICTIONARY or not MahjongRules.configure_from_rules_json(rules):
		load_errors.append("tile_match_rules.json invalid; using built-in defaults")
		MahjongRules.configure(MahjongRules.DEFAULT_GROUPS)
	# Levels 1-50 from the pack, 51-150 generated and difficulty-ordered (see LevelCatalog).
	level_dicts = LevelCatalog.load_merged(load_errors)
	if level_dicts.is_empty():
		load_errors.append("levels file missing or invalid")
	var w: Variant = _read_json(WORLDS_PATH)
	worlds = w if typeof(w) == TYPE_ARRAY else []
	var b: Variant = _read_json(BLOOM_PATH)
	bloom = b if typeof(b) == TYPE_DICTIONARY else {"lights_per_discovery": 5, "worlds": []}
	var c: Variant = _read_json(COSMETICS_PATH)
	cosmetics = c if typeof(c) == TYPE_DICTIONARY else {"default_theme": "classic", "themes": [{"id": "classic", "unlock": {"type": "default"}}]}


func _read_json(p: String) -> Variant:
	if not FileAccess.file_exists(p):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))


# --- levels -------------------------------------------------------------------------

func level_count() -> int:
	return level_dicts.size()


func get_level(id: int) -> LevelDefinition:
	## Returns null for unknown/invalid levels; invalid ones are logged, never played.
	if _level_cache.has(id):
		return _level_cache[id]
	if id < 1 or id > level_dicts.size():
		return null
	var L := LevelDefinition.from_dict(level_dicts[id - 1])
	if not L.is_valid() or L.id != id:
		push_error("Level %d rejected: %s" % [id, L.errors])
		return null
	_level_cache[id] = L
	return L


func world_for_level(id: int) -> Dictionary:
	for w in worlds:
		if id >= int(w.levels[0]) and id <= int(w.levels[1]):
			return w
	return worlds[0] if not worlds.is_empty() else {}


func world(world_id: String) -> Dictionary:
	for w in worlds:
		if w.id == world_id:
			return w
	return {}


func world_name_key(world_id: String) -> String:
	return WORLD_NAME_KEYS.get(world_id, world_id)


func world_range(world_id: String) -> Vector2i:
	var w := world(world_id)
	if w.is_empty():
		return Vector2i(1, 1)
	return Vector2i(int(w.levels[0]), int(w.levels[1]))


# --- bloom --------------------------------------------------------------------------

func lights_per_discovery() -> int:
	return int(bloom.get("lights_per_discovery", 5))


func all_discoveries() -> Array:
	## Flattened in unlock order: [{id, sprite, pos, size, world, index}]
	var out: Array = []
	for w in bloom.get("worlds", []):
		for d in w.discoveries:
			var e: Dictionary = d.duplicate()
			e["world"] = w.world
			e["index"] = out.size()
			out.append(e)
	return out


# --- cosmetics ----------------------------------------------------------------------

func themes() -> Array:
	return cosmetics.get("themes", [])


func theme_def(theme_id: String) -> Dictionary:
	for t in themes():
		if t.id == theme_id:
			return t
	return {}


# --- textures -----------------------------------------------------------------------

func tex(rel_path: String) -> Texture2D:
	var p := rel_path if rel_path.begins_with("res://") else ASSET_ROOT + rel_path
	if _tex_cache.has(p):
		return _tex_cache[p]
	if not ResourceLoader.exists(p):
		push_warning("Missing asset: " + p)
		return null
	var t: Texture2D = load(p)
	_tex_cache[p] = t
	return t


func icon(name: String, white: bool = false) -> Texture2D:
	return tex("ui/icons/%s/%s.png" % ["white" if white else "navy", name])


func world_bg(world_id: String, kind: String, low: bool) -> Texture2D:
	## kind: "world" (full art), "gameplay" (soft), "map"
	match kind:
		"gameplay":
			return tex("backgrounds/gameplay/%s_soft_1080x1920.png" % world_id)
		"map":
			return tex("backgrounds/maps/%s_map_1080x1920.png" % world_id)
		_:
			return tex("backgrounds/worlds/%s_%s.png" % [world_id, "540x960" if low else "1080x1920"])


func tile_texture(theme_id: String, face: String, hi_res: bool) -> Texture2D:
	## Tile faces come from the pack atlases (one texture per theme+size) as AtlasTextures.
	var size := 256 if hi_res else 128
	var atlas_path := "tiles/atlases/%s_%d_atlas.png" % [theme_id, size]
	var key := "%s|%s" % [atlas_path, face]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var map := _atlas_map(theme_id, size)
	var base := tex(atlas_path)
	if base == null or not map.has(face):
		# Fallback to the individual PNG so a missing atlas entry never breaks a board.
		return tex("tiles/%s/png_%d/%s.png" % [theme_id, size, face])
	var m: Dictionary = map[face]
	var at := AtlasTexture.new()
	at.atlas = base
	at.region = Rect2(m.x, m.y, m.width, m.height)
	_tex_cache[key] = at
	return at


func _atlas_map(theme_id: String, size: int) -> Dictionary:
	var k := "%s_%d" % [theme_id, size]
	if not _atlas_maps.has(k):
		var j: Variant = _read_json(ASSET_ROOT + "tiles/atlases/%s_atlas.json" % k)
		_atlas_maps[k] = j.get("mapping", {}) if typeof(j) == TYPE_DICTIONARY else {}
	return _atlas_maps[k]


func effect_frames(effect: String) -> Array[Texture2D]:
	var key := "fx|" + effect
	if _tex_cache.has(key):
		return _tex_cache[key]
	var out: Array[Texture2D] = []
	var meta: Variant = _read_json(ASSET_ROOT + "effects/atlases/%s_atlas.json" % effect)
	var base := tex("effects/atlases/%s_atlas.png" % effect)
	if base == null or typeof(meta) != TYPE_DICTIONARY:
		return out
	var fw := int(meta.frame_width)
	var fh := int(meta.frame_height)
	var cols := int(meta.columns)
	for i in int(meta.count):
		var at := AtlasTexture.new()
		at.atlas = base
		at.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
		out.append(at)
	_tex_cache[key] = out
	return out


func release_inactive() -> void:
	## Drops cached textures not belonging to the active world/theme.
	var keep := [active_world, active_theme, "ui/", "branding/", "effects/"]
	for k in _tex_cache.keys():
		var hold := false
		for token in keep:
			if str(k).contains(token):
				hold = true
				break
		if not hold:
			_tex_cache.erase(k)
