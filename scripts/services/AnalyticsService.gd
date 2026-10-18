extends Node
## Provider-agnostic, consent-aware analytics.
##
## - Every event and parameter is validated against data/config/analytics_events.json;
##   unknown events/params are rejected. String values are sanitised to short identifiers.
## - Nothing leaves the device unless ALL of: the analytics feature flag is on, the player
##   granted analytics consent, and a real provider is attached. No provider ships today.
## - Events are batched (no per-tap network traffic). In debug builds a local ring buffer
##   keeps recent events for inspection; it is never transmitted.

const SCHEMA_PATH := "res://data/config/analytics_events.json"
const BATCH_SIZE := 20
const DEBUG_RING := 200

var schema_version: int = 0
var _events: Dictionary = {}
var _queue: Array = []
var debug_log: Array = []
var provider: Object = null   # must implement send_batch(events: Array) -> void


func _ready() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCHEMA_PATH))
	if typeof(j) == TYPE_DICTIONARY:
		_events = j.get("events", {})
		schema_version = int(j.get("schema_version", 0))


func validate(event: String, params: Dictionary) -> String:
	## Returns "" if valid, otherwise a reason.
	if not _events.has(event):
		return "unknown_event"
	var spec: Dictionary = _events[event]
	for k in params:
		if not spec.has(k):
			return "unknown_param:" + str(k)
		var want := str(spec[k])
		var v: Variant = params[k]
		match want:
			"int":
				if typeof(v) != TYPE_INT:
					return "type:" + str(k)
			"bool":
				if typeof(v) != TYPE_BOOL:
					return "type:" + str(k)
			"str":
				if typeof(v) != TYPE_STRING:
					return "type:" + str(k)
	return ""


static func sanitize(s: String) -> String:
	var out := ""
	for ch in s.to_lower().left(40):
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in ["_", "-", ":", "."]:
			out += ch
	return out


func collecting() -> bool:
	return FeatureFlags.enabled("analytics_enabled") and PrivacyService.analytics_allowed() and provider != null


func track(event: String, params: Dictionary = {}) -> bool:
	var reason := validate(event, params)
	if reason != "":
		if OS.is_debug_build():
			push_warning("Analytics rejected %s: %s" % [event, reason])
		return false
	var clean := {}
	for k in params:
		clean[k] = sanitize(params[k]) if typeof(params[k]) == TYPE_STRING else params[k]
	var e := {"e": event, "p": clean, "v": schema_version, "t": int(Time.get_unix_time_from_system())}
	if OS.is_debug_build():
		debug_log.append(e)
		if debug_log.size() > DEBUG_RING:
			debug_log.pop_front()
	if collecting():
		_queue.append(e)
		if _queue.size() >= BATCH_SIZE:
			flush()
	return true


func flush() -> void:
	if not collecting():
		_queue.clear()
		return
	if _queue.is_empty():
		return
	provider.call("send_batch", _queue.duplicate())
	_queue.clear()


func clear_local() -> void:
	## Used when consent is withdrawn.
	_queue.clear()
	debug_log.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()
