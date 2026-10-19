extends Node
## Consent state and legal links.
##
## Ads consent comes from the game's own dialog (scripts/ui/ConsentDialog.gd), no Google UMP.
## It is asked only where opt-in consent is required: the device region (OS locale) or time
## zone is in the EEA, the UK or Switzerland. Everywhere else the answer is "not_required"
## (personalized). Settings > Privacy choices reopens the dialog for everyone. On iOS the ATT
## prompt follows the consent answer. Sequencing:
##   ads: AdsService.initialize() requires can_initialize_ads() (an answer is recorded)
##   analytics: AnalyticsService only queues when analytics_allowed() is true.
## Declining consent never blocks gameplay; ads then stay non-personalized.

signal consent_changed

const CONFIG_PATH := "res://data/config/privacy_config.json"

## EEA (EU + Iceland, Liechtenstein, Norway), UK and Switzerland, as ISO 3166 country codes.
const CONSENT_REGIONS := [
	"AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT",
	"LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
	"IS", "LI", "NO", "GB", "CH",
]
## IANA time zones that count as Europe/UK (all of "Europe/" is deliberately broad).
const CONSENT_ZONE_PREFIXES := [
	"Europe/", "Atlantic/Canary", "Atlantic/Madeira", "Atlantic/Azores", "Atlantic/Reykjavik",
	"Atlantic/Faroe", "Arctic/Longyearbyen", "Asia/Nicosia", "Asia/Famagusta",
]

var urls: Dictionary = {}


func _ready() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	urls = j if typeof(j) == TYPE_DICTIONARY else {}
	if ads_on():
		resolve_ads_consent_region()


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


func ads_on() -> bool:
	return FeatureFlags.enabled("ads_enabled") or FeatureFlags.enabled("banner_ads_enabled")


func ads_consent() -> String:
	## "obtained" | "denied" (dialog answer), "not_required" (outside Europe/UK) or "unset".
	return str(GameState.data.privacy.get("ads_consent", "unset"))


func record_ads_consent(status: String) -> void:
	## status: "obtained" | "not_required" | "denied"
	GameState.data.privacy.ads_consent = status
	GameState.save_now()
	consent_changed.emit()
	_maybe_request_tracking.call_deferred()


func can_initialize_ads() -> bool:
	return ads_consent() in ["obtained", "not_required", "denied"]


func needs_launch_prompt() -> bool:
	## Only a build that actually collects data asks at launch.
	return FeatureFlags.enabled("analytics_enabled") and analytics_consent() == "unset"


# --- ads consent region (own dialog, no Google UMP) and iOS tracking (ATT) -----------

const NATIVE := "LevelPlayBanner"


func _native() -> Object:
	return Engine.get_singleton(NATIVE) if Engine.has_singleton(NATIVE) else null


func device_region() -> String:
	## ISO country from the OS locale ("de_DE" -> "DE", "zh_Hant_TW" -> "TW"); "" if none.
	var parts := OS.get_locale().replace("-", "_").split("_")
	for i in range(1, parts.size()):
		if parts[i].length() == 2 and parts[i] == parts[i].to_upper():
			return parts[i]
	return ""


func device_time_zone() -> String:
	## IANA id ("Europe/Berlin") from the native plugin; the OS name elsewhere (desktop).
	# Android plugin methods are resolved over JNI, so has_method() is false for them there.
	var p := _native()
	if p and (OS.has_feature("android") or p.has_method("device_time_zone")):
		return str(p.device_time_zone())
	return str(Time.get_time_zone_from_system().get("name", ""))


func consent_region_required(region: String = device_region(), zone: String = device_time_zone()) -> bool:
	if region in CONSENT_REGIONS:
		return true
	for prefix: String in CONSENT_ZONE_PREFIXES:
		if zone.begins_with(prefix):
			return true
	return false


func resolve_ads_consent_region(required: bool = consent_region_required()) -> void:
	## At launch: outside Europe/UK no dialog is needed; a device that moved into Europe/UK
	## after "not_required" is asked again. Answers given in the dialog are kept.
	var status := ads_consent()
	if status == "unset" and not required:
		record_ads_consent("not_required")
	elif status == "not_required" and required:
		GameState.data.privacy.ads_consent = "unset"
		GameState.save_now()
		consent_changed.emit()


func needs_ads_consent_prompt() -> bool:
	## True at launch while a Europe/UK device has not answered the dialog yet.
	return ads_on() and ads_consent() == "unset"


func _maybe_request_tracking() -> void:
	var p := _native()
	if p == null or not OS.has_feature("ios") or not p.has_method("request_tracking_authorization"):
		return
	if bool(GameState.data.privacy.get("att_requested", false)):
		return
	GameState.data.privacy["att_requested"] = true
	GameState.save_now()
	p.request_tracking_authorization()
