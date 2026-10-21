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
const ASSET_ROOT := "res://assets/veya/"   ## audio, effects and legacy art
const ART_ROOT := "res://art/lishi_v2/"
## "Three New Worlds" pack (tools/import_lishi_worlds.ps1): one folder per world with its own
## backgrounds, UI and props, as the pack ships them.
const WORLDS_ART_ROOT := "res://art/lishi_worlds/"
const PACK_WORLDS := ["jade_bamboo_valley", "sunset_lotus_palace", "frostlight_village"]
const WORLD_NAME_KEYS := {
	"aurora_garden": "world_aurora", "pearl_coast": "world_coast", "crystal_nocturne": "world_nocturne",
	"jade_bamboo_valley": "world_jade", "sunset_lotus_palace": "world_sunset", "frostlight_village": "world_frost",
}
## Tile theme ids are save keys and never change; only the art each one shows does.
const TILE_THEME_ART := {"classic": "sakura_premium", "sakura": "jade_garden", "ocean": "pearl_ocean", "nocturne": "moonlit_lilac"}
## Pearl Coast keeps its legacy illustration until the pack provides a matching one.
const WORLD_BACKGROUNDS := {
	"aurora_garden": {"world": "aurora_garden_home", "map": "aurora_garden_journey", "gameplay": "aurora_garden_gameplay"},
	"pearl_coast": {"world": "pearl_coast_original_art"},
	"crystal_nocturne": {"world": "crystal_nocturne_night"},
}
const SCREEN_BACKGROUNDS := {"daily": "aurora_garden_journey", "settings": "aurora_garden_home"}
## Icon names the game uses that the pack names differently.
const ICON_ALIASES := {"calendar_check": "check", "sparkle": "star", "volume_off": "muted", "extra_slot": "plus"}

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


func tile_backs() -> Array:
	## [{id}], the id being the world whose completion unlocks it.
	return cosmetics.get("tile_backs", [])


func has_tile_back(back_id: String) -> bool:
	return tile_backs().any(func(b: Dictionary) -> bool: return str(b.id) == back_id)


func tile_back_texture(back_id: String) -> Texture2D:
	return world_art(back_id, "ui/cosmetic_tile_back_256x320.png")


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


func art(rel_path: String) -> Texture2D:
	## Texture from the LiShi v2 graphics pack (res://art/lishi_v2/, see tools/import_lishi_v2.gd).
	return tex(ART_ROOT + rel_path)


func icon(name: String, white: bool = false) -> Texture2D:
	## Ivory icons sit on dark/coloured surfaces, emerald icons on light ones.
	return art("ui/icons/%s/%s.png" % ["ivory" if white else "emerald", ICON_ALIASES.get(name, name)])


func world_bg(world_id: String, kind: String, low: bool) -> Texture2D:
	## kind: "world" (full art), "gameplay" (pre-blurred board art), "map", "bloom" (the world
	## art pre-blurred, so discoveries read as the sharp focal objects)
	if PACK_WORLDS.has(world_id):
		# The pack's gameplay backdrop is already subdued and defocused, so it serves Bloom too.
		# Its map_background has a painted route of 12 round markers that read as level buttons
		# behind the real level grid, so the map uses the world art instead.
		var pack_kind: String = {"bloom": "gameplay", "map": "world"}.get(kind, kind)
		return world_art(world_id, "backgrounds/%s_background_%s.jpg" % [pack_kind, "720x1280" if low else "1440x2560"])
	var names: Dictionary = WORLD_BACKGROUNDS.get(world_id, WORLD_BACKGROUNDS.aurora_garden)
	var file: String = names.get(kind, names.world)
	if kind == "gameplay" or kind == "bloom":
		return art("backgrounds/%s/%s.png" % ["soft_low" if low else "soft", file])
	return art("backgrounds/%s/%s.png" % ["low" if low else "full", file])


func world_art(world_id: String, rel_path: String) -> Texture2D:
	## Texture from a world of the "Three New Worlds" pack, e.g. "ui/world_badge_512.png".
	return tex(WORLDS_ART_ROOT + world_id + "/" + rel_path)


func is_pack_world(world_id: String) -> bool:
	return PACK_WORLDS.has(world_id)


func screen_bg(screen: String, low: bool) -> Texture2D:
	## Backgrounds for screens that are not tied to one world (always new-style art).
	var file: String = SCREEN_BACKGROUNDS.get(screen, "aurora_garden_gameplay")
	return art("backgrounds/%s/%s.png" % ["soft_low" if low else "soft", file])


func tile_art(theme_id: String) -> String:
	return TILE_THEME_ART.get(theme_id, TILE_THEME_ART.classic)


func tile_texture(theme_id: String, face: String, hi_res: bool) -> Texture2D:
	## Tile faces come from per-theme atlases (one texture per theme+size) as AtlasTextures.
	## Cells already match the logical tile slot (BoardFit.ASPECT, BoardView.BODY).
	var art_id := tile_art(theme_id)
	var size := 192 if hi_res else 96
	var atlas_path := ART_ROOT + "tiles/%s/%s_%d_atlas.png" % [art_id, art_id, size]
	var key := "%s|%s" % [atlas_path, face]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var map := _atlas_map(art_id, size)
	var base := tex(atlas_path)
	if base == null or not map.has(face):
		push_error("Tile face missing from atlas: %s %s" % [atlas_path, face])
		return null
	var m: Dictionary = map[face]
	var at := AtlasTexture.new()
	at.atlas = base
	at.region = Rect2(m.x, m.y, m.width, m.height)
	_tex_cache[key] = at
	return at


func tile_overlay(state: String, hi_res: bool) -> Texture2D:
	## selected / hint / blocked / match / pressed, drawn over a tile at the slot size.
	return art("tiles/states/%s%s.png" % [state, "" if hi_res else "_lo"])


func discovery_texture(d: Dictionary, hi: bool) -> Texture2D:
	## Bloom sprite: a "Three New Worlds" prop named by "world_art", the v2 pack prop named by
	## "art", else the legacy decoration (Pearl Coast and objects the pack does not cover yet).
	if d.has("world_art"):
		return world_art(str(d.world), "props/%s_%d.png" % [d.world_art, 512 if hi else 256])
	if d.has("art"):
		return art("props/%s/%s.png" % ["hi" if hi else "lo", d.art])
	return tex("decorations/%s_%d.png" % [d.sprite, 512 if hi else 256])


func _atlas_map(art_id: String, size: int) -> Dictionary:
	var k := "%s_%d" % [art_id, size]
	if not _atlas_maps.has(k):
		var j: Variant = _read_json(ART_ROOT + "tiles/%s/%s_atlas.json" % [art_id, k])
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
	var keep := [active_world, active_theme, tile_art(active_theme), "tiles/states/", "ui/", "branding/", "effects/"]
	for k in _tex_cache.keys():
		var hold := false
		for token in keep:
			if str(k).contains(token):
				hold = true
				break
		if not hold:
			_tex_cache.erase(k)
