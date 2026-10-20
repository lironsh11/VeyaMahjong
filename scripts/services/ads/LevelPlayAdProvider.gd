class_name LevelPlayAdProvider
extends AdProviderBase
## Rewarded + interstitial through the native `LevelPlayBanner` singleton (Android and iOS),
## implementing docs/NATIVE_ADS_API.md. Ad unit NAMES (economy.json) are mapped to platform ad
## unit ids from data/config/levelplay.json:
##   "rewarded_ad_units":     {"rewarded_bonus_coins": "<id>", "rewarded_bloom_bonus": "<id>"}
##   "interstitial_ad_units": {"interstitial_level_complete": "<id>"}
## Every native close/fail callback is matched to its show by token and runs once.

const SINGLETON := "LevelPlayBanner"
const CONFIG := "res://data/config/levelplay.json"
## Debug builds only: when this file exists the LevelPlay Integration Test Suite opens after init
## (adb shell run-as com.lishimahjong.app.debug touch files/levelplay_test_suite.flag).
const TEST_SUITE_FLAG := "user://levelplay_test_suite.flag"

var _plugin: Object
var _cfg: Dictionary = {}
var _ids: Dictionary = {}          ## unit name -> ad unit id
var _names: Dictionary = {}        ## ad unit id -> unit name
var _rewarded_ready: Dictionary = {}
var _interstitial_ready: Dictionary = {}
var _rewarded_cb: Dictionary = {}       ## token -> Callable(earned, show_failed)
var _interstitial_cb: Dictionary = {}   ## token -> Callable()
var _next_token: int = 1
var _loading: Dictionary = {}   ## ad unit id -> true while a load is in flight (placements share units)


static func platform_config() -> Dictionary:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var section: Variant = parsed.get("ios" if OS.has_feature("ios") else "android", {})
	return section if typeof(section) == TYPE_DICTIONARY else {}


static func available() -> bool:
	## True only with the native plugin that implements the full contract AND configured ids.
	if not Engine.has_singleton(SINGLETON):
		return false
	# Android plugin methods are resolved over JNI, so has_method() is false for them there.
	if not OS.has_feature("android") and not Engine.get_singleton(SINGLETON).has_method("init_sdk"):
		return false
	var c := platform_config()
	if str(c.get("app_key", "")) == "":
		return false
	for key in ["rewarded_ad_units", "interstitial_ad_units"]:
		var units: Variant = c.get(key, {})
		if typeof(units) == TYPE_DICTIONARY:
			for v in units.values():
				if str(v) != "":
					return true
	return false


func initialize(personalized: bool) -> void:
	_plugin = Engine.get_singleton(SINGLETON)
	_cfg = platform_config()
	for key in ["rewarded_ad_units", "interstitial_ad_units"]:
		var units: Variant = _cfg.get(key, {})
		if typeof(units) == TYPE_DICTIONARY:
			for unit_name in units:
				var id := str(units[unit_name])
				if id != "":
					_ids[unit_name] = id
					_names[id] = unit_name
	_connect("rewarded_loaded", _on_rewarded_loaded)
	_connect("rewarded_load_failed", _on_rewarded_load_failed)
	_connect("rewarded_closed", _on_rewarded_closed)
	_connect("rewarded_show_failed", _on_rewarded_show_failed)
	_connect("interstitial_loaded", _on_interstitial_loaded)
	_connect("interstitial_load_failed", _on_interstitial_load_failed)
	_connect("interstitial_closed", _on_interstitial_closed)
	_connect("interstitial_show_failed", _on_interstitial_show_failed)
	if OS.is_debug_build() and FileAccess.file_exists(TEST_SUITE_FLAG):
		# QA: LevelPlay Integration Test Suite (adapters, networks, test ads). Debug builds only.
		_plugin.set_test_suite_enabled(true)
		_connect("sdk_ready", func() -> void: _plugin.launch_test_suite())
	_plugin.init_sdk(str(_cfg.get("app_key", "")), personalized)


func _connect(sig: String, target: Callable) -> void:
	if _plugin.has_signal(sig) and not _plugin.is_connected(sig, target):
		_plugin.connect(sig, target)


func set_personalized(personalized: bool) -> void:
	if _plugin:
		_plugin.set_personalized(personalized)


func _token() -> int:
	_next_token += 1
	return _next_token


# --- rewarded -----------------------------------------------------------------------

func load_rewarded(unit: String) -> void:
	if _plugin and _ids.has(unit) and not _loading.has(_ids[unit]) and not is_rewarded_loaded(unit):
		_loading[_ids[unit]] = true
		_plugin.load_rewarded(_ids[unit])


func is_rewarded_loaded(unit: String) -> bool:
	if _plugin == null or not _ids.has(unit):
		return false
	return bool(_plugin.is_rewarded_ready(_ids[unit]))


func show_rewarded(unit: String, placement: String, on_done: Callable) -> void:
	if _plugin == null or not _ids.has(unit):
		on_done.call(false, true)
		return
	var token := _token()
	_rewarded_cb[token] = on_done
	_plugin.show_rewarded(_ids[unit], placement, token)


func _on_rewarded_loaded(ad_unit_id: String) -> void:
	_loading.erase(ad_unit_id)
	load_state_changed.emit(str(_names.get(ad_unit_id, ad_unit_id)), true, false)


func _on_rewarded_load_failed(ad_unit_id: String, _code: int) -> void:
	_loading.erase(ad_unit_id)
	load_state_changed.emit(str(_names.get(ad_unit_id, ad_unit_id)), false, true)


func _on_rewarded_closed(token: int, earned: bool, _ad_unit_id: String) -> void:
	var cb: Callable = _rewarded_cb.get(token, Callable())
	_rewarded_cb.erase(token)
	if cb.is_valid():
		cb.call(earned, false)


func _on_rewarded_show_failed(token: int, _ad_unit_id: String) -> void:
	var cb: Callable = _rewarded_cb.get(token, Callable())
	_rewarded_cb.erase(token)
	if cb.is_valid():
		cb.call(false, true)


# --- interstitial -------------------------------------------------------------------

func load_interstitial(unit: String) -> void:
	if _plugin and _ids.has(unit) and not _loading.has(_ids[unit]) and not is_interstitial_loaded(unit):
		_loading[_ids[unit]] = true
		_plugin.load_interstitial(_ids[unit])


func is_interstitial_loaded(unit: String) -> bool:
	if _plugin == null or not _ids.has(unit):
		return false
	return bool(_plugin.is_interstitial_ready(_ids[unit]))


func show_interstitial(unit: String, placement: String, on_closed: Callable) -> void:
	if _plugin == null or not _ids.has(unit):
		on_closed.call()
		return
	var token := _token()
	_interstitial_cb[token] = on_closed
	_plugin.show_interstitial(_ids[unit], placement, token)


func _on_interstitial_loaded(ad_unit_id: String) -> void:
	_loading.erase(ad_unit_id)
	load_state_changed.emit(str(_names.get(ad_unit_id, ad_unit_id)), true, false)


func _on_interstitial_load_failed(ad_unit_id: String, _code: int) -> void:
	_loading.erase(ad_unit_id)
	load_state_changed.emit(str(_names.get(ad_unit_id, ad_unit_id)), false, true)


func _on_interstitial_closed(token: int) -> void:
	var cb: Callable = _interstitial_cb.get(token, Callable())
	_interstitial_cb.erase(token)
	if cb.is_valid():
		cb.call()


func _on_interstitial_show_failed(token: int, _ad_unit_id: String) -> void:
	_on_interstitial_closed(token)


func dispose() -> void:
	_rewarded_cb.clear()
	_interstitial_cb.clear()
	_loading.clear()
	_plugin = null
