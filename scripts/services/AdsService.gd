extends Node
## Advertising facade. OFF by default (feature flags) and no ad SDK is bundled.
##
## Rules enforced here, independent of any provider:
## - Rewarded ads are optional bonuses only; nothing in the core loop requires them.
## - A reward is granted at most once per grant_id (persisted), so duplicate SDK callbacks,
##   app restarts mid-ad or double taps cannot double-grant.
## - Rewarded daily cap; interstitials only at natural breaks, never mid-board, never in the
##   tutorial, never right after a crash/restart, capped per day, and never with Remove Ads.
## - initialize() refuses to run before PrivacyService records a CMP consent result.
## - is_rewarded_ready() is false unless a real (or QA-mock, debug-only) ad is loaded, so
##   the UI never shows a fake "watch ad" button.

signal rewarded_result(placement: String, status: String)  # granted | not_completed | unavailable | duplicate | capped

enum State { DISABLED, NO_PROVIDER, WAITING_CONSENT, READY }

const LOAD_TIMEOUT_S := 8.0

var state: int = State.DISABLED
var state_reason: String = ""
var provider: AdProviderBase = null
var _session_started_unix: int = 0
var _loading: Dictionary = {}   # placement -> start msec


func _ready() -> void:
	_session_started_unix = int(Time.get_unix_time_from_system())
	initialize()


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
