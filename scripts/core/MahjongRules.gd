class_name MahjongRules
extends RefCounted
## Traditional Mahjong Solitaire matching semantics.
##
## - Ordinary faces (suits, winds, dragons) match only an identical face.
## - Any Flower matches any other Flower; any Season matches any other Season.
## - Flowers never match Seasons.
## Freedom (which tiles may be picked) is geometric and lives in BoardGeometry/BoardState.
##
## Group membership defaults to the asset pack's levels/tile_match_rules.json and can be
## re-configured from that file at boot so data and code cannot silently diverge.

const FACES: PackedStringArray = [
	"character_1", "character_2", "character_3", "character_4", "character_5",
	"character_6", "character_7", "character_8", "character_9",
	"circle_1", "circle_2", "circle_3", "circle_4", "circle_5",
	"circle_6", "circle_7", "circle_8", "circle_9",
	"bamboo_1", "bamboo_2", "bamboo_3", "bamboo_4", "bamboo_5",
	"bamboo_6", "bamboo_7", "bamboo_8", "bamboo_9",
	"wind_east", "wind_south", "wind_west", "wind_north",
	"dragon_red", "dragon_green", "dragon_white",
	"flower_plum", "flower_orchid", "flower_chrysanthemum", "flower_bamboo_flower",
	"season_spring", "season_summer", "season_autumn", "season_winter",
]

const DEFAULT_GROUPS := {
	"flower": ["flower_plum", "flower_orchid", "flower_chrysanthemum", "flower_bamboo_flower"],
	"season": ["season_spring", "season_summer", "season_autumn", "season_winter"],
}

## face -> group name (only for bonus faces)
static var _face_group: Dictionary = {}
## match key -> small int, so the solver can compare ints instead of strings
static var _key_ids: Dictionary = {}


static func _ensure() -> void:
	if _key_ids.is_empty():
		configure(DEFAULT_GROUPS)


static func configure(groups: Dictionary) -> void:
	_face_group.clear()
	_key_ids.clear()
	for group_name in groups:
		for face in groups[group_name]:
			_face_group[str(face)] = str(group_name)
	for face in FACES:
		var key: String = _face_group.get(face, face)
		if not _key_ids.has(key):
			_key_ids[key] = _key_ids.size()


static func configure_from_rules_json(rules: Dictionary) -> bool:
	## Accepts the pack's tile_match_rules.json structure. Returns false if malformed.
	var bonus: Variant = rules.get("bonus_matching", null)
	if typeof(bonus) != TYPE_DICTIONARY:
		return false
	for group_name in bonus:
		if typeof(bonus[group_name]) != TYPE_ARRAY:
			return false
		for face in bonus[group_name]:
			if not FACES.has(str(face)):
				return false
	configure(bonus)
	return true


static func is_valid_face(face: String) -> bool:
	return FACES.has(face)


static func match_key(face: String) -> String:
	_ensure()
	return _face_group.get(face, face)


static func key_id(face: String) -> int:
	_ensure()
	return int(_key_ids.get(match_key(face), -1))


static func key_count() -> int:
	_ensure()
	return _key_ids.size()


static func can_match(face_a: String, face_b: String) -> bool:
	if not is_valid_face(face_a) or not is_valid_face(face_b):
		return false
	return match_key(face_a) == match_key(face_b)


static func is_bonus(face: String) -> bool:
	_ensure()
	return _face_group.has(face)


static func is_flower(face: String) -> bool:
	return match_key(face) == "flower"


static func is_season(face: String) -> bool:
	return match_key(face) == "season"


static func suit(face: String) -> String:
	## "character", "circle", "bamboo", "wind", "dragon", "flower", "season"
	return face.get_slice("_", 0)
