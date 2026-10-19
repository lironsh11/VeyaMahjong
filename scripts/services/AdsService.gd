extends Node
## Advertising facade: rewarded ads, interstitials and the bottom banner.
##
## Rules enforced here, independent of any provider:
## - Rewarded ads are opt-in. App placements (win_double, booster, shop_coins, bloom_bonus) map
##   to ad units in data/config/economy.json, each with its own daily cap plus a global cap.
## - A reward is granted at most once per grant_id (persisted), so duplicate SDK callbacks,
##   app restarts mid-ad or double taps cannot double-grant. Grant ids from next_grant_id()
##   use a lifetime sequence, so turning the clock back cannot replay one. Daily caps count by
##   EconomyService.cap_day(), which never moves backwards.
## - Interstitials only at "Next level" after a win, from level `interstitial_first_level`, at
##   least `interstitial_min_levels_between` levels and `fullscreen_min_seconds_between`
##   seconds after the previous full-screen ad (rewarded included; app start counts as one),
##   never right after a rewarded ad in the same level, never in the tutorial or for Remove
##   Ads owners, capped per day. The continue callback always runs exactly once.
## - Callbacks passed in must not capture a screen (pass autoload methods / bound callables);
##   screens refresh through the rewarded_result signal.
## - initialize() refuses to start rewarded/interstitial before PrivacyService has a consent
##   result (or, in internal test builds only, ads_allow_unset_consent with consent unset).
## - is_rewarded_ready() is false unless a real (or QA-mock, debug-only) ad is loaded, so the
##   UI never shows a fake "watch a video" button.
## - The bottom banner is separate: it shows when banner_ads_enabled is on, hides for Remove Ads
##   and while a Europe/UK device has not answered the consent dialog (non-personalized after a
##   decline), and reserves no space until a real ad loads.

signal rewarded_result(placement: String, status: String)  # granted | not_completed | failed | unavailable | duplicate | capped | busy
signal availability_changed   # a rewarded/interstitial unit finished loading or failed
signal banner_layout_changed

enum State { DISABLED, NO_PROVIDER, WAITING_CONSENT, READY }

const LEVELPLAY_CONFIG := "res://data/config/levelplay.json"
const RETRY_STEPS_S := [30, 60, 120, 300]
const INTERSTITIAL_RESUME_GRACE_S := 8.0
const INTERSTITIAL_HARD_TIMEOUT_S := 150.0

var state: int = State.DISABLED
var state_reason: String = ""
var provider: AdProviderBase = null
var banner_height_px: int = 0
var _banner_started: bool = false
var _showing: bool = false
var _rewarded_since_level_start: bool = false
var _last_fullscreen_ticks: int = 0      ## msec ticks; app start counts as a full-screen moment
var _retry_index: Dictionary = {}       ## unit -> index into RETRY_STEPS_S
var _pending_close: Callable = Callable()
var _close_serial: int = 0


func _ready() -> void:
	_last_fullscreen_ticks = Time.get_ticks_msec()
	initialize()
	_debug_log_state()
	if not PrivacyService.consent_changed.is_connected(_on_consent_changed):
		PrivacyService.consent_changed.connect(_on_consent_changed)
	if not IAPService.entitlements_changed.is_connected(_sync_banner):
		IAPService.entitlements_changed.connect(_sync_banner)
	call_deferred("_connect_lifecycle")
	_sync_banner()


func _connect_lifecycle() -> void:
	if not Router.app_paused.is_connected(_on_banner_pause):
		Router.app_paused.connect(_on_banner_pause)
	if not Router.app_resumed.is_connected(_on_app_resumed):
		Router.app_resumed.connect(_on_app_resumed)


func _on_consent_changed() -> void:
	_sync_banner()
	if state == State.WAITING_CONSENT:
		initialize()
	elif provider:
		provider.set_personalized(_personalized())


func _personalized() -> bool:
	return PrivacyService.ads_consent() in ["obtained", "not_required"]


func _consent_allows() -> bool:
	if PrivacyService.can_initialize_ads():
		return true
	return FeatureFlags.enabled("ads_allow_unset_consent") and PrivacyService.ads_consent() == "unset"


func initialize() -> void:
	if not FeatureFlags.enabled("ads_enabled"):
		state = State.DISABLED
		state_reason = "feature_flag_off"
		return
	if provider == null:
		if FeatureFlags.enabled("qa_mock_services") and OS.is_debug_build():
			provider = MockAdProvider.new()
		elif LevelPlayAdProvider.available():
			provider = LevelPlayAdProvider.new()
		else:
			state = State.NO_PROVIDER
			state_reason = "no_native_ad_plugin_integrated"
			return
		provider.load_state_changed.connect(_on_load_state)
	if not _consent_allows():
		state = State.WAITING_CONSENT
		state_reason = "consent_not_recorded"
		return
	provider.initialize(_personalized())
	state = State.READY
	state_reason = ""
	preload_all()


func _debug_log_state() -> void:
	if OS.is_debug_build():
		print("AdsService state=%s reason=%s consent=%s tz=%s region=%s" % [State.keys()[state], state_reason,
			PrivacyService.ads_consent(), PrivacyService.device_time_zone(), PrivacyService.device_region()])


func set_consent(personalized: bool) -> void:
	if provider:
		provider.set_personalized(personalized)


func _today() -> String:
	return EconomyService.cap_day(Time.get_date_string_from_system(false))


func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())


# --- rewarded -----------------------------------------------------------------------

func unit_for(placement: String) -> String:
	return EconomyService.ad_unit_for(placement)


func _counts() -> Dictionary:
	## Today's per-placement counts (reset when the cap day changes).
	var a: Dictionary = GameState.data.ads
	if str(a.get("rewarded_day", "")) != _today():
		a.rewarded_day = _today()
		a.rewarded_count = 0
		a.rewarded_counts = {}
	return a.rewarded_counts


func rewarded_remaining_today() -> int:
	_counts()
	return maxi(0, FeatureFlags.get_int("rewarded_daily_cap") - int(GameState.data.ads.rewarded_count))


func placement_remaining_today(placement: String) -> int:
	var cap := int(EconomyService.rewarded_cfg(placement).get("daily_cap", 0))
	var used := int(_counts().get(placement, 0))
	return mini(maxi(0, cap - used), rewarded_remaining_today())


func next_grant_id(placement: String) -> String:
	## Unique for every watched ad of a placement over the app's lifetime.
	return "ad:%s:%d" % [placement, int(GameState.data.ads.placement_seq.get(placement, 0)) + 1]


func load_rewarded(placement: String) -> void:
	if state != State.READY or not FeatureFlags.enabled("rewarded_ads_enabled"):
		return
	var unit := unit_for(placement)
	if unit != "" and not provider.is_rewarded_loaded(unit):
		provider.load_rewarded(unit)


func is_rewarded_ready(placement: String) -> bool:
	if state != State.READY or not FeatureFlags.enabled("rewarded_ads_enabled") or _showing:
		return false
	if placement_remaining_today(placement) <= 0:
		return false
	var unit := unit_for(placement)
	return unit != "" and provider.is_rewarded_loaded(unit)


func show_rewarded(placement: String, grant_id: String, on_granted: Callable) -> void:
	## on_granted is called at most once per grant_id across the app's lifetime.
	if GameState.data.ads.reward_grants.has(grant_id):
		rewarded_result.emit(placement, "duplicate")
		return
	if _showing:
		rewarded_result.emit(placement, "busy")
		return
	if not is_rewarded_ready(placement):
		rewarded_result.emit(placement, "unavailable" if placement_remaining_today(placement) > 0 else "capped")
		load_rewarded(placement)
		return
	_showing = true
	AnalyticsService.track("rewarded_ad_offered", {"placement": placement})
	var done := [false]
	provider.show_rewarded(unit_for(placement), placement, func(earned: bool, show_failed: bool) -> void:
		# The first callback decides; a later duplicate only matters if it carries the reward
		# (the grant id still prevents a second grant).
		if done[0] and not earned:
			return
		done[0] = true
		_on_reward_callback(placement, grant_id, earned, show_failed, on_granted))


func _on_reward_callback(placement: String, grant_id: String, earned: bool, show_failed: bool, on_granted: Callable) -> void:
	_showing = false
	_stamp_fullscreen()
	if not earned:
		if show_failed:
			AnalyticsService.track("rewarded_ad_failed", {"placement": placement, "reason": "show_failed"})
		rewarded_result.emit(placement, "failed" if show_failed else "not_completed")
		load_rewarded(placement)
		return
	var a: Dictionary = GameState.data.ads
	if a.reward_grants.has(grant_id):
		rewarded_result.emit(placement, "duplicate")  # duplicate SDK callback
		return
	a.reward_grants.append(grant_id)
	if a.reward_grants.size() > 400:
		a.reward_grants = a.reward_grants.slice(a.reward_grants.size() - 400)
	var counts := _counts()
	counts[placement] = int(counts.get(placement, 0)) + 1
	a.rewarded_count = int(a.rewarded_count) + 1
	a.placement_seq[placement] = int(a.placement_seq.get(placement, 0)) + 1
	_rewarded_since_level_start = true
	GameState.save_now()
	AnalyticsService.track("rewarded_ad_completed", {"placement": placement})
	if on_granted.is_valid():
		on_granted.call()
	rewarded_result.emit(placement, "granted")
	load_rewarded(placement)


func _stamp_fullscreen() -> void:
	_last_fullscreen_ticks = Time.get_ticks_msec()
	GameState.data.ads.last_fullscreen_unix = _now_unix()


func preload_all() -> void:
	## Keeps every unit the player can currently use loaded (the SDK caches one ad each).
	if state != State.READY:
		return
	if FeatureFlags.enabled("rewarded_ads_enabled"):
		for p in EconomyService.rewarded_placements():
			if placement_remaining_today(p) > 0:
				load_rewarded(p)
	if _interstitial_eligible_soon():
		load_interstitial()


func _on_load_state(unit: String, loaded: bool, failed: bool) -> void:
	if loaded:
		_retry_index.erase(unit)
	elif failed and is_inside_tree():
		var i := int(_retry_index.get(unit, 0))
		_retry_index[unit] = mini(i + 1, RETRY_STEPS_S.size() - 1)
		get_tree().create_timer(RETRY_STEPS_S[i]).timeout.connect(preload_all)
	availability_changed.emit()


# --- interstitials ------------------------------------------------------------------

func on_level_started() -> void:
	_rewarded_since_level_start = false


func on_level_finished() -> void:
	GameState.data.ads.levels_since_interstitial = int(GameState.data.ads.levels_since_interstitial) + 1


func _interstitial_eligible_soon() -> bool:
	return FeatureFlags.enabled("interstitials_enabled") and not IAPService.has_entitlement("remove_ads") \
		and bool(GameState.data.get("tutorial_done", false)) \
		and GameState.highest_completed() + 1 >= FeatureFlags.get_int("interstitial_first_level")


func _seconds_since_fullscreen() -> float:
	var in_session := (Time.get_ticks_msec() - _last_fullscreen_ticks) / 1000.0
	var across := float(_now_unix() - int(GameState.data.ads.get("last_fullscreen_unix", 0)))
	if across < 0.0:
		across = 0.0  # clock moved back: treat as "just now"
	return minf(in_session, across)


func can_show_interstitial_now(context: String, level_id: int = 0) -> bool:
	## context must be the natural break "level_complete_continue"; never mid-board/tutorial.
	if context != "level_complete_continue":
		return false
	if state != State.READY or not FeatureFlags.enabled("interstitials_enabled") or _showing:
		return false
	if IAPService.has_entitlement("remove_ads"):
		return false
	if not bool(GameState.data.get("tutorial_done", false)):
		return false
	if level_id < FeatureFlags.get_int("interstitial_first_level"):
		return false
	if _rewarded_since_level_start:
		return false
	if _seconds_since_fullscreen() < FeatureFlags.get_int("fullscreen_min_seconds_between"):
		return false
	var a: Dictionary = GameState.data.ads
	if int(a.levels_since_interstitial) < FeatureFlags.get_int("interstitial_min_levels_between"):
		return false
	var count := int(a.interstitial_count) if str(a.interstitial_day) == _today() else 0
	if count >= FeatureFlags.get_int("interstitial_daily_cap"):
		return false
	return provider.is_interstitial_loaded(unit_for("interstitial"))


func load_interstitial() -> void:
	if state == State.READY and FeatureFlags.enabled("interstitials_enabled"):
		var unit := unit_for("interstitial")
		if unit != "" and not provider.is_interstitial_loaded(unit):
			provider.load_interstitial(unit)


func show_interstitial(context: String, level_id: int, on_closed: Callable) -> void:
	## on_closed runs exactly once: right away when no ad is due, else when the ad closes.
	if not can_show_interstitial_now(context, level_id):
		load_interstitial()
		on_closed.call()
		return
	var a: Dictionary = GameState.data.ads
	if str(a.interstitial_day) != _today():
		a.interstitial_day = _today()
		a.interstitial_count = 0
	a.interstitial_count = int(a.interstitial_count) + 1
	a.levels_since_interstitial = 0
	_stamp_fullscreen()
	GameState.save_now()
	AnalyticsService.track("interstitial_shown", {"level": level_id})
	_showing = true
	_close_serial += 1
	var serial := _close_serial
	_pending_close = on_closed
	if is_inside_tree():
		get_tree().create_timer(INTERSTITIAL_HARD_TIMEOUT_S).timeout.connect(_finish_interstitial.bind(serial))
	provider.show_interstitial(unit_for("interstitial"), "interstitial_level_complete", _finish_interstitial.bind(serial))


func _finish_interstitial(serial: int) -> void:
	if serial != _close_serial or not _pending_close.is_valid():
		return
	var cb := _pending_close
	_pending_close = Callable()
	_showing = false
	_stamp_fullscreen()
	cb.call()
	load_interstitial()


func _on_app_resumed() -> void:
	_on_banner_resume()
	# If the SDK never reports the close (rare), continue shortly after the app is back.
	if _pending_close.is_valid() and is_inside_tree():
		get_tree().create_timer(INTERSTITIAL_RESUME_GRACE_S).timeout.connect(_finish_interstitial.bind(_close_serial))


func dispose() -> void:
	if provider:
		provider.dispose()
	provider = null
	state = State.DISABLED
	_showing = false
	_pending_close = Callable()
	_rewarded_since_level_start = false
	_retry_index.clear()


# --- bottom banner (LevelPlay + Meta) ------------------------------------------------

func banner_allowed() -> bool:
	if not FeatureFlags.enabled("banner_ads_enabled"):
		return false
	if IAPService.has_entitlement("remove_ads"):
		return false
	# "unset" only means a Europe/UK device that has not answered the consent dialog yet.
	# A decline still allows non-personalized ads.
	return PrivacyService.ads_consent() != "unset"


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
