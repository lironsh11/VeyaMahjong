extends Node
## Advertising facade. OFF by default (feature flags) and no ad SDK is bundled.
##
## Rules enforced here, independent of any provider:
## - Rewarded ads are optional bonuses only; nothing in the core loop requires them.
## - A reward is granted at most once per grant_id (persisted), so duplicate SDK callbacks,
##   app restarts mid-ad or double taps cannot double-grant.
## - Rewarded daily cap; interstitials only at natural breaks, never mid-board, never in the
##   tutorial, never right after a crash/restart, capped per day, and never with Remove Ads.
## - initialize() refuses to run a rewarded/interstitial provider before PrivacyService records
##   a CMP consent result.
## - The bottom banner is separate: it shows when banner_ads_enabled is on, hides for Remove Ads
##   and for a denied consent, and reserves no space until a real ad loads.
## - is_rewarded_ready() is false unless a real (or QA-mock, debug-only) ad is loaded, so
##   the UI never shows a fake "watch ad" button.

signal rewarded_result(placement: String, status: String)  # granted | not_completed | unavailable | duplicate | capped
signal banner_layout_changed

enum State { DISABLED, NO_PROVIDER, WAITING_CONSENT, READY }

const LOAD_TIMEOUT_S := 8.0
const LEVELPLAY_CONFIG := "res://data/config/levelplay.json"

var state: int = State.DISABLED
var state_reason: String = ""
var provider: AdProviderBase = null
var banner_height_px: int = 0
var _session_started_unix: int = 0
var _loading: Dictionary = {}   # placement -> start msec
var _banner_started: bool = false


func _ready() -> void:
	_session_started_unix = int(Time.get_unix_time_from_system())
	initialize()
	if not PrivacyService.consent_changed.is_connected(_sync_banner):
		PrivacyService.consent_changed.connect(_sync_banner)
	if not IAPService.entitlements_changed.is_connected(_sync_banner):
		IAPService.entitlements_changed.connect(_sync_banner)
	call_deferred("_connect_banner_lifecycle")
	_sync_banner()


func _connect_banner_lifecycle() -> void:
	if not Router.app_paused.is_connected(_on_banner_pause):
		Router.app_paused.connect(_on_banner_pause)
	if not Router.app_resumed.is_connected(_on_banner_resume):
		Router.app_resumed.connect(_on_banner_resume)


func initialize() -> void:
	if not FeatureFlags.enabled("ads_enabled"):
		state = State.DISABLED
		state_reason = "feature_flag_off"
		return
	if FeatureFlags.enabled("qa_mock_services") and OS.is_debug_build():
		provider = MockAdProvider.new()
	else:
		# Native AdMob/mediation adapters must be added and validated in an exported build
		# before being wired here. See docs/MONETIZATION.md.
		state = State.NO_PROVIDER
		state_reason = "no_native_ad_plugin_integrated"
		return
	if not PrivacyService.can_initialize_ads():
		state = State.WAITING_CONSENT
		state_reason = "consent_not_recorded"
		return
	provider.initialize(PrivacyService.ads_consent() == "obtained")
	state = State.READY
	state_reason = ""


func set_consent(personalized: bool) -> void:
	if provider:
		provider.set_personalized(personalized)


func _today() -> String:
	return Time.get_date_string_from_system(false)


func rewarded_remaining_today() -> int:
	var a: Dictionary = GameState.data.ads
	var used := int(a.get("rewarded_count", 0)) if str(a.get("rewarded_day", "")) == _today() else 0
	return maxi(0, FeatureFlags.get_int("rewarded_daily_cap") - used)


func load_rewarded(placement: String) -> void:
	if state != State.READY or not FeatureFlags.enabled("rewarded_ads_enabled"):
		return
	_loading[placement] = Time.get_ticks_msec()
	provider.load_rewarded(placement)


func is_rewarded_ready(placement: String) -> bool:
	if state != State.READY or not FeatureFlags.enabled("rewarded_ads_enabled") or rewarded_remaining_today() <= 0:
		return false
	return provider.is_rewarded_loaded(placement)


func show_rewarded(placement: String, grant_id: String, on_granted: Callable) -> void:
	## on_granted is called at most once per grant_id across the app's lifetime.
	if GameState.data.ads.reward_grants.has(grant_id):
		rewarded_result.emit(placement, "duplicate")
		return
	if not is_rewarded_ready(placement):
		rewarded_result.emit(placement, "unavailable" if rewarded_remaining_today() > 0 else "capped")
		return
	AnalyticsService.track("rewarded_ad_offered", {"placement": placement})
	provider.show_rewarded(placement, func(earned: bool) -> void:
		_on_reward_callback(placement, grant_id, earned, on_granted))


func _on_reward_callback(placement: String, grant_id: String, earned: bool, on_granted: Callable) -> void:
	if not earned:
		rewarded_result.emit(placement, "not_completed")
		return
	var a: Dictionary = GameState.data.ads
	if a.reward_grants.has(grant_id):
		rewarded_result.emit(placement, "duplicate")  # duplicate SDK callback
		return
	a.reward_grants.append(grant_id)
	if str(a.get("rewarded_day", "")) != _today():
		a.rewarded_day = _today()
		a.rewarded_count = 0
	a.rewarded_count = int(a.rewarded_count) + 1
	GameState.save_now()
	AnalyticsService.track("rewarded_ad_completed", {"placement": placement})
	on_granted.call()
	rewarded_result.emit(placement, "granted")


func _process(_dt: float) -> void:
	for p in _loading.keys():
		if provider and provider.is_rewarded_loaded(p):
			_loading.erase(p)
		elif Time.get_ticks_msec() - int(_loading[p]) > LOAD_TIMEOUT_S * 1000:
			_loading.erase(p)
			if provider:
				provider.cancel_load(p)


# --- interstitials (flag OFF by default) --------------------------------------------

func on_level_finished() -> void:
	GameState.data.ads.levels_since_interstitial = int(GameState.data.ads.levels_since_interstitial) + 1


func can_show_interstitial_now(context: String) -> bool:
	## context must be a natural break ("level_complete_continue"); never "board"/"tutorial".
	if context != "level_complete_continue":
		return false
	if state != State.READY or not FeatureFlags.enabled("interstitials_enabled"):
		return false
	if IAPService.has_entitlement("remove_ads"):
		return false
	if not bool(GameState.data.get("tutorial_done", false)):
		return false
	if int(Time.get_unix_time_from_system()) - _session_started_unix < 120:
		return false  # never right after launch / crash-restart
	var a: Dictionary = GameState.data.ads
	if int(a.levels_since_interstitial) < FeatureFlags.get_int("interstitial_min_levels_between"):
		return false
	var count := int(a.interstitial_count) if str(a.interstitial_day) == _today() else 0
	return count < FeatureFlags.get_int("interstitial_daily_cap") and provider.is_interstitial_loaded()


func load_interstitial() -> void:
	if state == State.READY and FeatureFlags.enabled("interstitials_enabled"):
		provider.load_interstitial()


func show_interstitial(context: String, on_closed: Callable) -> void:
	if not can_show_interstitial_now(context):
		on_closed.call()
		return
	var a: Dictionary = GameState.data.ads
	if str(a.interstitial_day) != _today():
		a.interstitial_day = _today()
		a.interstitial_count = 0
	a.interstitial_count = int(a.interstitial_count) + 1
	a.levels_since_interstitial = 0
	GameState.request_save()
	provider.show_interstitial(on_closed)


func dispose() -> void:
	if provider:
		provider.dispose()
	provider = null
	state = State.DISABLED


# --- bottom banner (LevelPlay + Meta) ------------------------------------------------

func banner_allowed() -> bool:
	if not FeatureFlags.enabled("banner_ads_enabled"):
		return false
	if IAPService.has_entitlement("remove_ads"):
		return false
	return PrivacyService.ads_consent() != "denied"


func banner_canvas_inset(vp: Viewport) -> int:
	## Extra bottom margin, in canvas pixels, once a real banner is on screen.
	if banner_height_px <= 0 or not banner_allowed():
		return 0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0
	return int(ceil(float(banner_height_px) * vp.get_visible_rect().size.y / float(win.y)))


func _sync_banner() -> void:
	var plugin := _banner_plugin()
	if not banner_allowed():
		banner_height_px = 0
		if plugin:
			plugin.set_enabled(false)
		banner_layout_changed.emit()
		return
	if plugin == null:
		return
	var cfg := _levelplay_config()
	if cfg.is_empty():
		return
	var personalized := PrivacyService.ads_consent() in ["obtained", "not_required"]
	if not _banner_started:
		if not plugin.banner_visibility.is_connected(_on_banner_visibility):
			plugin.banner_visibility.connect(_on_banner_visibility)
		plugin.start(str(cfg.app_key), str(cfg.banner_ad_unit_id), personalized)
		_banner_started = true
	else:
		plugin.set_personalized(personalized)
		plugin.set_enabled(true)


func _levelplay_config() -> Dictionary:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVELPLAY_CONFIG))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var section: Variant = parsed.get("ios" if OS.has_feature("ios") else "android", {})
	if typeof(section) != TYPE_DICTIONARY:
		return {}
	if str(section.get("app_key", "")) == "" or str(section.get("banner_ad_unit_id", "")) == "":
		return {}
	return section


func _banner_plugin() -> Object:
	if Engine.has_singleton("LevelPlayBanner"):
		return Engine.get_singleton("LevelPlayBanner")
	return null


func _on_banner_visibility(visible: bool, height_px: int) -> void:
	banner_height_px = height_px if visible and banner_allowed() else 0
	banner_layout_changed.emit()


func _on_banner_pause() -> void:
	var plugin := _banner_plugin()
	if plugin:
		plugin.on_pause()


func _on_banner_resume() -> void:
	var plugin := _banner_plugin()
	if plugin and banner_allowed():
		plugin.on_resume()
