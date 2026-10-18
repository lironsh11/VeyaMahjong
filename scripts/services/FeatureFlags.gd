extends Node
## Local feature flags with safe offline defaults (data/config/feature_flags.json).
## There is intentionally no remote-config dependency; a future remote layer may only
## override flags after validation, never enable monetization without a real provider.

const PATH := "res://data/config/feature_flags.json"

const DEFAULTS := {
	"content_version": "dev",
	"effects_enabled": true,
	"daily_tasks_enabled": true,
	"shop_enabled": true,
	"analytics_enabled": false,
	"ads_enabled": false,
	"rewarded_ads_enabled": false,
	"interstitials_enabled": false,
	"interstitial_min_levels_between": 4,
	"interstitial_daily_cap": 4,
	"rewarded_daily_cap": 3,
	"qa_mock_services": false,
	"show_session_timer_option": true,
	"banner_ads_enabled": false,
}

var _flags: Dictionary = DEFAULTS.duplicate()
var _overrides: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_flags = DEFAULTS.duplicate()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed:
			# Only known keys with the right type are accepted.
			if DEFAULTS.has(k) and typeof(parsed[k]) in [typeof(DEFAULTS[k]), TYPE_FLOAT]:
				_flags[k] = parsed[k] if typeof(DEFAULTS[k]) != TYPE_INT else int(parsed[k])
	# QA mocks are only ever honoured in debug builds.
	if not OS.is_debug_build():
		_flags.qa_mock_services = false


func enabled(flag: String) -> bool:
	return bool(_overrides.get(flag, _flags.get(flag, false)))


func get_int(flag: String) -> int:
	return int(_overrides.get(flag, _flags.get(flag, 0)))


func get_str(flag: String) -> String:
	return str(_overrides.get(flag, _flags.get(flag, "")))


func set_override(flag: String, value: Variant) -> void:
	## Test/debug hook. Not persisted.
	_overrides[flag] = value


func clear_overrides() -> void:
	_overrides.clear()
