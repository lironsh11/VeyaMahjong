class_name TestCase
extends RefCounted
## Minimal assertion base for the headless runner (tests/run_tests.gd).
## Every method starting with "test_" is executed; failures are collected, not thrown.

var failures: PackedStringArray = []
var _current: String = ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func check(cond: bool, msg: String = "expected true") -> bool:
	if not cond:
		fail(msg)
	return cond


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	if typeof(actual) != typeof(expected) and not (typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]):
		fail("%s expected %s (%s) got %s (%s)" % [msg, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])
		return false
	if actual != expected:
		fail("%s expected %s got %s" % [msg, str(expected), str(actual)])
		return false
	return true


static func level_from_rows(rows: Array, layers: Array = [], faces: Array = []) -> LevelDefinition:
	## Test helper: builds a LevelDefinition from ASCII rows ("X" = tile) with optional
	## extra layer rows and an explicit face list (row-major order across layers).
	var tiles: Array = []
	var all_layers: Array = [rows]
	all_layers.append_array(layers)
	for z in all_layers.size():
		var lr: Array = all_layers[z]
		for y in lr.size():
			var line: String = lr[y]
			for x in line.length():
				if line[x] == "X":
					tiles.append({"x": x, "y": y, "z": z, "face": "dragon_white"})
	for k in mini(faces.size(), tiles.size()):
		tiles[k].face = faces[k]
	return LevelDefinition.from_dict({"id": 9999, "tiles": tiles}, "test:%d" % tiles.size())
