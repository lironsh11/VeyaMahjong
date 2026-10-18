extends Node
## Accessibility and performance settings applied app-wide:
## reduced motion, haptics, graphics profile (Low / Standard, with an automatic choice),
## and helpers for screen-reader names where the engine exposes them.

signal profile_changed(low: bool)

var low_profile: bool = false
var auto_reason: String = ""


func _ready() -> void:
	apply()
	GameState.settings_changed.connect(_on_setting)


func _on_setting(key: String) -> void:
	if key in ["graphics", "reduced_motion"]:
		apply()


func reduced_motion() -> bool:
	return bool(GameState.setting("reduced_motion"))


func effects_on() -> bool:
	return not reduced_motion() and not low_profile and FeatureFlags.enabled("effects_enabled")


func auto_is_low() -> bool:
	## Heuristic for the automatic profile: weak devices get the Low profile.
	var mem: Dictionary = OS.get_memory_info()
	var phys := int(mem.get("physical", -1))
	if phys > 0 and phys < 3 * 1024 * 1024 * 1024:
		auto_reason = "memory"
		return true
	if OS.get_processor_count() <= 4 and OS.has_feature("mobile"):
		auto_reason = "cpu"
		return true
	auto_reason = ""
	return false


func apply() -> void:
	var mode := str(GameState.setting("graphics"))
	var was := low_profile
	low_profile = mode == "low" or (mode == "auto" and auto_is_low())
	# Low profile caps to 30 FPS (battery/thermal); the game is turn-based so this is
	# imperceptible for input. Low-processor mode already redraws only on change.
	Engine.max_fps = 30 if low_profile else 60
	if was != low_profile:
		profile_changed.emit(low_profile)


func haptic(kind: String = "tap") -> void:
	if not bool(GameState.setting("haptics")):
		return
	if not OS.has_feature("mobile"):
		return
	var ms := 12
	match kind:
		"match": ms = 20
		"invalid": ms = 30
		"win": ms = 40
	Input.vibrate_handheld(ms, 0.35)


static func set_access_name(node: Control, name: String, description: String = "") -> void:
	## Godot 4.5+ exposes accessibility properties (AccessKit). Guarded so older engines and
	## platforms without screen-reader support keep working.
	if "accessibility_name" in node:
		node.set("accessibility_name", name)
	if description != "" and "accessibility_description" in node:
		node.set("accessibility_description", description)
