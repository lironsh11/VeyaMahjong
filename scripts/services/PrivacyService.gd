extends Node
## Consent state and legal links.
##
## Current build: no advertising SDK and no analytics provider are integrated, so no personal
## data leaves the device and no consent prompt is required at launch. The sequencing below
## is still enforced so a future SDK cannot start before consent:
##   ads: AdsService.initialize() requires can_initialize_ads() (CMP/UMP result recorded)
##   analytics: AnalyticsService only queues when analytics_allowed() is true.
## Declining consent never blocks gameplay.

signal consent_changed

const CONFIG_PATH := "res://data/config/privacy_config.json"

var urls: Dictionary = {}


func _ready() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	urls = j if typeof(j) == TYPE_DICTIONARY else {}


func url(kind: String) -> String:
	## kind: privacy_policy | terms | support | data_deletion. "" when not configured.
	var v := str(urls.get(kind + "_url", "")).strip_edges()
	return v if v.begins_with("https://") else ""


func support_email() -> String:
	var e := str(urls.get("support_email", "")).strip_edges()
	return e if e.contains("@") else ""


func open(kind: String) -> bool:
	var u := url(kind)
	if u == "":
		return false
	OS.shell_open(u)
	return true


func analytics_consent() -> String:
	return str(GameState.data.privacy.get("analytics_consent", "unset"))


func analytics_allowed() -> bool:
	return analytics_consent() == "granted"


func set_analytics_consent(granted: bool) -> void:
	GameState.data.privacy.analytics_consent = "granted" if granted else "denied"
	if not granted:
		AnalyticsService.clear_local()
	GameState.save_now()
	consent_changed.emit()


func ads_consent() -> String:
	## Set only from a real CMP (e.g. Google UMP) result via record_ads_consent().
	return str(GameState.data.privacy.get("ads_consent", "unset"))


func record_ads_consent(status: String) -> void:
	## status: "obtained" | "not_required" | "denied"
	GameState.data.privacy.ads_consent = status
	GameState.save_now()
	consent_changed.emit()


func can_initialize_ads() -> bool:
	return ads_consent() in ["obtained", "not_required", "denied"]


func needs_launch_prompt() -> bool:
	## Only a build that actually collects data asks at launch.
	return FeatureFlags.enabled("analytics_enabled") and analytics_consent() == "unset"
