extends TestCase
## Service-level tests (run inside the real autoload tree, isolated save directory).

func _reset() -> void:
	FeatureFlags.clear_overrides()
	SaveService.save_dir = "user://test_run"
	SaveService.delete_all()
	GameState.data = GameState.defaults()
	DailyService.today_override = ""
	AdsService.dispose()
	AdsService.initialize()


# --- persistence ---------------------------------------------------------------------

func test_save_roundtrip_and_checksum() -> void:
	_reset()
	var payload := {"a": 1, "b": "x", "schema_version": 1}
	check(SaveService.write(payload), "write ok")
	var r := SaveService.read()
	check_eq(r.source, "primary")
	check_eq(int(r.payload.a), 1)
	var text := SaveService.encode({"a": 1})
	var tampered := text.replace("\\\"a\\\":1", "\\\"a\\\":2")
	check(text != tampered, "tamper applied")
	check(SaveService.decode(tampered) == null, "checksum mismatch rejected")
	check(SaveService.decode("{not json") == null, "garbage rejected")


func test_corrupt_primary_recovers_backup() -> void:
	_reset()
	SaveService.write({"gen": 1})
	SaveService.write({"gen": 2})  # gen 1 rotates to .bak
	var f := FileAccess.open(SaveService.path(), FileAccess.WRITE)
	f.store_string("{\"format\":\"veya-save\",\"payload\":\"trunc")  # simulated torn write
	f.close()
	var r := SaveService.read()
	check_eq(r.source, "bak", "fell back to backup")
	check_eq(int(r.payload.gen), 1)
	var quarantined := false
	for fn in DirAccess.get_files_at(SaveService.save_dir):
		if fn.contains(".corrupt-"):
			quarantined = true
	check(quarantined, "corrupt file kept aside for support")


func test_tmp_recovery_after_interrupted_rename() -> void:
	_reset()
	SaveService.write({"gen": 1})
	var tmp := FileAccess.open(SaveService.path() + ".tmp", FileAccess.WRITE)
	tmp.store_string(SaveService.encode({"gen": 7}))
	tmp.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveService.path()))
	var r := SaveService.read()
	check_eq(r.source, "tmp")
	check_eq(int(r.payload.gen), 7)


func test_migration_from_v0() -> void:
	var old := {"schema_version": 0, "progress": {"completed": [1, 2, 3]}, "settings": {"music_on": false}}
	var m := GameState.migrate(old)
	check_eq(int(m.schema_version), GameState.defaults().schema_version)
	check(typeof(m.progress.completed) == TYPE_DICTIONARY and m.progress.completed.has("2"), "list migrated to dict")
	check_eq(m.settings.music_on, false, "existing settings kept")
	check(m.settings.has("reduced_motion"), "missing defaults filled")
	check(m.has("daily") and m.daily.has("completed"), "new sections added")


func test_dim_blocked_tiles_turned_off_once_in_old_saves() -> void:
	# Saves made before settings rev 1 stored "highlight_free": true (the old default).
	var old := {"schema_version": 1, "settings": {"highlight_free": true, "music_on": false}}
	var m := GameState.migrate(old)
	check_eq(m.settings.highlight_free, false, "old default switched off")
	check_eq(m.settings.music_on, false, "other settings kept")
	check_eq(int(m.settings_rev), GameState.SETTINGS_REV)
	# A player who turns it back on keeps it on later loads.
	m.settings.highlight_free = true
	check_eq(GameState.migrate(m).settings.highlight_free, true, "explicit choice respected")
	check_eq(GameState.defaults().settings.highlight_free, false, "new saves start with it off")


func test_full_state_persists_through_reload() -> void:
	_reset()
	ProgressionService.complete_level(1, {"moves": 8})
	GameState.set_setting("high_contrast", false)
	GameState.data.cosmetics.equipped_theme = "classic"
	GameState.save_now()
	GameState.data = {}
	GameState.load_game()
	check(GameState.is_level_completed(1), "completion persisted")
	check_eq(GameState.lights(), 1, "light persisted")


# --- progression ---------------------------------------------------------------------

func test_level_completion_is_idempotent() -> void:
	_reset()
	var r1 := ProgressionService.complete_level(1, {"moves": 8, "hints": 0})
	var r2 := ProgressionService.complete_level(1, {"moves": 8, "hints": 0})
	check(r1.first_time and r1.light_awarded, "first completion awards a Light")
	check(not r2.first_time and not r2.light_awarded, "replay awards nothing")
	check_eq(GameState.lights(), 1)
	check(not ProgressionService.award_light("level:1"), "same source cannot be re-awarded")


func test_discoveries_every_five_lights() -> void:
	_reset()
	for id in range(1, 5):
		ProgressionService.complete_level(id, {})
	check_eq(ProgressionService.discoveries_unlocked_count(), 0)
	var r := ProgressionService.complete_level(5, {})
	check_eq(ProgressionService.discoveries_unlocked_count(), 1)
	check_eq(r.discoveries.size(), 1, "result reports the new discovery")
	check_eq(ProgressionService.lights_progress(), Vector2i(0, 5))


func test_theme_unlocks_and_equip() -> void:
	_reset()
	check(ProgressionService.is_theme_unlocked("classic"))
	check(not ProgressionService.is_theme_unlocked("sakura"))
	check(not ProgressionService.equip_theme("sakura"), "locked theme cannot be equipped")
	for id in range(1, 11):
		ProgressionService.complete_level(id, {})
	check(ProgressionService.is_theme_unlocked("sakura"), "10 Lights unlock Sakura")
	check(ProgressionService.equip_theme("sakura"))
	check_eq(ProgressionService.equipped_theme(), "sakura")


func test_world_unlock_reported_once() -> void:
	_reset()
	for id in range(1, 100):
		GameState.data.progress.completed[str(id)] = {"t": 0}
	check(not GameState.is_level_unlocked(101), "world 2 waits for level 100")
	var r := ProgressionService.complete_level(100, {})
	check_eq(r.world_unlocked, "pearl_coast")
	check(GameState.is_level_unlocked(101))
	check_eq(ProgressionService.complete_level(100, {}).world_unlocked, "", "not reported again")


func test_level_300_opens_the_newer_worlds() -> void:
	_reset()
	for id in range(1, 300):
		GameState.data.progress.completed[str(id)] = {"t": 0}
	check_eq(ProgressionService.complete_level(300, {}).world_unlocked, "jade_bamboo_valley")
	check(GameState.is_level_unlocked(301))
	check(ContentService.get_level(301) != null and ContentService.get_level(600) != null, "levels 301-600 load")
	check(ContentService.get_level(601) == null, "no level 601")
	check_eq(str(ContentService.world_for_level(600).id), "frostlight_village")
	check(EconomyService.level_reward(600) > EconomyService.level_reward(500), "the last world pays the most first-clear coins")


func test_tile_back_earned_by_finishing_its_world() -> void:
	_reset()
	check_eq(ProgressionService.equipped_back(), "", "no back by default")
	check(not ProgressionService.equip_back("jade_bamboo_valley"), "locked back cannot be equipped")
	for id in range(1, 400):
		GameState.data.progress.completed[str(id)] = {"t": 0}
	var r := ProgressionService.complete_level(400, {})
	check_eq(r.backs, ["jade_bamboo_valley"], "finishing Jade Bamboo Valley earns its back")
	check_eq(r.world_unlocked, "sunset_lotus_palace")
	check_eq(ProgressionService.complete_level(400, {}).backs, [], "not reported again")
	check(not ProgressionService.is_back_unlocked("sunset_lotus_palace"))
	check(ProgressionService.equip_back("jade_bamboo_valley"))
	check(SaveService.write(GameState.data))
	GameState.data = GameState.migrate(SaveService.read().payload)
	check_eq(ProgressionService.equipped_back(), "jade_bamboo_valley", "equipped back persists")
	check(ProgressionService.equip_back(""), "back can be taken off")
	check_eq(ProgressionService.equipped_back(), "")
	# An old save without the key still loads with no back.
	var old := GameState.defaults()
	old.cosmetics.erase("equipped_back")
	check_eq(str(GameState.migrate(old).cosmetics.equipped_back), "")


# --- daily ---------------------------------------------------------------------------

func test_daily_dates_and_archive() -> void:
	_reset()
	DailyService.today_override = "2026-10-18"
	check(DailyService.is_playable("2026-10-18"), "today")
	check(DailyService.is_playable("2026-09-18"), "30 days back")
	check(not DailyService.is_playable("2026-09-17"), "31 days back")
	check(not DailyService.is_playable("2026-10-19"), "future locked")
	check(not DailyService.is_playable("2026-13-01"), "invalid month")
	check(DailyGenerator.is_valid_date("2028-02-29"), "leap day")
	check(not DailyGenerator.is_valid_date("2026-02-29"), "non-leap")
	check(not DailyGenerator.is_valid_date("2100-02-29"), "century non-leap")
	check_eq(DailyService.add_days("2026-10-24", 2), "2026-10-26", "across EU DST end")
	check_eq(DailyService.add_days("2026-03-07", 2), "2026-03-09", "across US DST start")
	check_eq(DailyService.days_between("2026-03-28", "2026-03-30"), 2)
	check_eq(DailyService.add_days("2028-02-28", 1), "2028-02-29")


func test_daily_claim_once_per_date() -> void:
	_reset()
	var r1 := ProgressionService.complete_daily("2026-10-18", {"moves": 30})
	var r2 := ProgressionService.complete_daily("2026-10-18", {"moves": 30})
	check(r1.light_awarded and not r2.light_awarded, "one Light per date")
	check(DailyService.is_completed("2026-10-18"))
	check_eq(GameState.lights(), 1)


func test_daily_board_deterministic() -> void:
	var a := DailyGenerator.build("2026-10-18")
	var b := DailyGenerator.build("2026-10-18")
	var c := DailyGenerator.build("2026-10-19")
	check(a != null and a.is_valid(), "valid daily board")
	check(a.faces() == b.faces() and a.positions() == b.positions(), "same date -> same board")
	check(a.faces() != c.faces(), "different date -> different board")
	check(BoardValidator.validate(a).ok, "daily board validated")


func test_daily_board_fingerprints_pinned() -> void:
	# Daily boards must never change silently. Fingerprints recorded 2026-10-22 for "daily-5"
	# (layered template boards). A mismatch means an algorithm change that requires bumping
	# DailyGenerator.VERSION and re-pinning; completions are keyed by date and survive.
	check_eq(DailyGenerator.VERSION.get_slice(" ", 0), "daily-5")
	var pinned := {
		"2026-10-18": "3d3addc3436c485e", "2026-10-19": "0ef58c8a39d9791a",
		"2026-11-03": "92da0335d5965bfb", "2027-02-28": "66404cb4e4458bb2",
		"2028-02-29": "ab05d1afdb8c69cd",
	}
	for d in pinned:
		var L := DailyGenerator.build(d)
		var fp := (",".join(L.faces()) + "|" + str(L.positions())).sha256_text().left(16)
		check_eq(fp, pinned[d], "daily %s fingerprint" % d)


func test_daily_tasks_claim() -> void:
	_reset()
	DailyService.today_override = "2026-10-18"
	check(not DailyService.claim_tasks_reward(), "cannot claim before completion")
	for t in DailyService.tasks_today():
		GameState.data.daily.task_stats[t.stat] = int(t.target)
	check(DailyService.all_tasks_done())
	check(DailyService.claim_tasks_reward(), "claim once")
	check(not DailyService.claim_tasks_reward(), "no double claim")
	check_eq(GameState.lights(), 1)
	DailyService.today_override = "2026-10-19"
	check(not DailyService.tasks_claimed(), "new day starts fresh without penalty")


# --- ads -----------------------------------------------------------------------------

func test_ads_never_ready_without_native_plugin() -> void:
	## Flags ship on; headless desktop has no LevelPlay plugin, so nothing may look ready.
	_reset()
	check(AdsService.state in [AdsService.State.DISABLED, AdsService.State.NO_PROVIDER], "no provider on desktop")
	check(not AdsService.is_rewarded_ready("win_double"), "never a fake ready ad")
	check(not AdsService.can_show_interstitial_now("level_complete_continue", 50))


func _ads_mock(mode: int) -> void:
	AdsService.dispose()
	FeatureFlags.set_override("ads_enabled", true)
	FeatureFlags.set_override("rewarded_ads_enabled", true)
	FeatureFlags.set_override("qa_mock_services", true)
	PrivacyService.record_ads_consent("not_required")
	MockAdProvider.mode = mode
	AdsService.initialize()


func test_ads_wait_for_consent() -> void:
	_reset()
	FeatureFlags.set_override("ads_enabled", true)
	FeatureFlags.set_override("qa_mock_services", true)
	AdsService.initialize()
	check_eq(AdsService.state, AdsService.State.WAITING_CONSENT, "no SDK init before consent")
	FeatureFlags.set_override("ads_allow_unset_consent", true)
	AdsService.initialize()
	check_eq(AdsService.state, AdsService.State.READY, "internal builds may run with consent unset")
	_reset()


func test_rewarded_duplicate_callback_grants_once() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.DUPLICATE_CALLBACK)
	AdsService.load_rewarded("shop_coins")
	check(AdsService.is_rewarded_ready("shop_coins"))
	var grants := [0]
	var gid := AdsService.next_grant_id("shop_coins")
	AdsService.show_rewarded("shop_coins", gid, func() -> void: grants[0] += 1)
	check_eq(grants[0], 1, "duplicate SDK callback granted once")
	AdsService.load_rewarded("shop_coins")
	AdsService.show_rewarded("shop_coins", gid, func() -> void: grants[0] += 1)
	check_eq(grants[0], 1, "same grant id never granted twice")
	check(AdsService.next_grant_id("shop_coins") != gid, "next id moves on after a grant")
	_reset()


func test_rewarded_no_fill_not_completed_and_show_failure() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.NO_FILL)
	AdsService.load_rewarded("booster")
	check(not AdsService.is_rewarded_ready("booster"), "no-fill -> no button")
	var statuses: Array = []
	var cb := func(_p: String, s: String) -> void: statuses.append(s)
	AdsService.rewarded_result.connect(cb)
	for mode in [MockAdProvider.Mode.NOT_COMPLETED, MockAdProvider.Mode.SHOW_FAILS]:
		_ads_mock(mode)
		AdsService.load_rewarded("booster")
		var grants := [0]
		AdsService.show_rewarded("booster", AdsService.next_grant_id("booster"), func() -> void: grants[0] += 1)
		check_eq(grants[0], 0, "no grant when the ad was not finished or failed to show")
		check(not AdsService._showing, "busy flag cleared after the callback")
	AdsService.rewarded_result.disconnect(cb)
	check(statuses.has("not_completed") and statuses.has("failed"), "both outcomes reported: %s" % [statuses])
	_reset()


func test_rewarded_caps_per_placement_and_global() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.FILL)
	var cap := int(EconomyService.rewarded_cfg("bloom_bonus").daily_cap)
	var grants := [0]
	for k in cap + 2:
		AdsService.load_rewarded("bloom_bonus")
		AdsService.show_rewarded("bloom_bonus", AdsService.next_grant_id("bloom_bonus"), func() -> void: grants[0] += 1)
	check_eq(grants[0], cap, "per-placement daily cap")
	check(AdsService.placement_remaining_today("shop_coins") > 0, "other placements unaffected")
	FeatureFlags.set_override("rewarded_daily_cap", cap + 1)
	AdsService.load_rewarded("shop_coins")
	AdsService.show_rewarded("shop_coins", AdsService.next_grant_id("shop_coins"), func() -> void: grants[0] += 1)
	AdsService.load_rewarded("shop_coins")
	AdsService.show_rewarded("shop_coins", AdsService.next_grant_id("shop_coins"), func() -> void: grants[0] += 1)
	check_eq(grants[0], cap + 1, "global cap applies across placements")
	_reset()


func test_rewarded_cap_survives_clock_rollback() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.FILL)
	GameState.data.economy.clock_hw_day = "2099-01-01"   # a later day was already seen
	AdsService.load_rewarded("bloom_bonus")
	AdsService.show_rewarded("bloom_bonus", AdsService.next_grant_id("bloom_bonus"), func() -> void: pass)
	check_eq(AdsService.placement_remaining_today("bloom_bonus"), 0, "cap counted on the high-water day")
	check_eq(str(GameState.data.ads.rewarded_day), "2099-01-01", "today (earlier) never resets the cap")
	_reset()


func test_rewarded_busy_guard() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.FILL)
	AdsService._showing = true
	var statuses: Array = []
	var cb := func(_p: String, s: String) -> void: statuses.append(s)
	AdsService.rewarded_result.connect(cb)
	AdsService.show_rewarded("booster", "ad:booster:x", func() -> void: pass)
	AdsService.rewarded_result.disconnect(cb)
	check_eq(statuses, ["busy"], "a second show while one is on screen is refused")
	_reset()


func _interstitial_ready_state() -> void:
	_ads_mock(MockAdProvider.Mode.FILL)
	FeatureFlags.set_override("interstitials_enabled", true)
	GameState.data.tutorial_done = true
	AdsService._last_fullscreen_ticks -= 600000
	GameState.data.ads.last_fullscreen_unix = 0
	GameState.data.ads.levels_since_interstitial = 10
	AdsService.on_level_started()
	AdsService.load_interstitial()


func test_interstitial_policy() -> void:
	_reset()
	_interstitial_ready_state()
	check(not AdsService.can_show_interstitial_now("board", 20), "never mid-board")
	check(AdsService.can_show_interstitial_now("level_complete_continue", 20), "allowed at natural break")
	check(not AdsService.can_show_interstitial_now("level_complete_continue", 5), "none before level 6")
	GameState.data.ads.levels_since_interstitial = 1
	check(not AdsService.can_show_interstitial_now("level_complete_continue", 20), "every 2 levels at most")
	GameState.data.ads.levels_since_interstitial = 10
	AdsService._last_fullscreen_ticks = Time.get_ticks_msec()
	check(not AdsService.can_show_interstitial_now("level_complete_continue", 20), "90 s after any full-screen ad")
	_interstitial_ready_state()
	AdsService._rewarded_since_level_start = true
	check(not AdsService.can_show_interstitial_now("level_complete_continue", 20), "never right after a rewarded ad")
	_interstitial_ready_state()
	GameState.data.entitlements["remove_ads"] = {"state": "active"}
	check(not AdsService.can_show_interstitial_now("level_complete_continue", 20), "Remove Ads respected")
	_reset()


func test_interstitial_continue_runs_exactly_once() -> void:
	_reset()
	_interstitial_ready_state()
	var calls := [0]
	AdsService.show_interstitial("level_complete_continue", 20, func() -> void: calls[0] += 1)
	check_eq(calls[0], 1, "continued after the ad")
	AdsService._finish_interstitial(AdsService._close_serial)   # late watchdog
	check_eq(calls[0], 1, "watchdog never continues twice")
	AdsService.show_interstitial("level_complete_continue", 20, func() -> void: calls[0] += 1)
	check_eq(calls[0], 2, "not due -> continues immediately")
	check_eq(int(GameState.data.ads.levels_since_interstitial), 0, "counter reset by the shown ad")
	_reset()


# --- IAP -----------------------------------------------------------------------------

func test_iap_unavailable_without_plugin() -> void:
	_reset()
	IAPService.provider = null
	IAPService.initialize()
	check(IAPService.status in [IAPService.Status.UNAVAILABLE, IAPService.Status.NOT_CONFIGURED], "no fake store")
	check(IAPService.offered_products().is_empty(), "no products without real store data")
	check(not IAPService.restore(), "restore honestly unavailable")


func _iap_mock() -> MockIAPProvider:
	FeatureFlags.set_override("qa_mock_services", true)
	IAPService.provider = null
	IAPService.initialize()
	return IAPService.provider as MockIAPProvider


func test_iap_purchase_flows() -> void:
	_reset()
	var mock := _iap_mock()
	check_eq(IAPService.status, IAPService.Status.READY)
	check_eq(IAPService.price_text("remove_ads"), "TEST 0.00", "price comes from the store layer")
	MockIAPProvider.next_outcome = MockIAPProvider.Outcome.CANCEL
	IAPService.purchase("remove_ads")
	check(not IAPService.has_entitlement("remove_ads"), "cancel grants nothing")
	MockIAPProvider.next_outcome = MockIAPProvider.Outcome.PENDING
	IAPService.purchase("remove_ads")
	check(not IAPService.has_entitlement("remove_ads"), "pending grants nothing yet")
	mock.complete_pending("qa.remove_ads")
	check(IAPService.has_entitlement("remove_ads"), "granted once completed")
	MockIAPProvider.next_outcome = MockIAPProvider.Outcome.DUPLICATE
	var results: Array = []
	var cb := func(_p: String, s: String, _m: String) -> void: results.append(s)
	IAPService.purchase_result.connect(cb)
	IAPService.purchase("theme_bundle")
	IAPService.purchase_result.disconnect(cb)
	check_eq(results.count("success"), 1, "duplicate store callback -> one success")
	check(ProgressionService.is_theme_unlocked("nocturne"), "bundle entitlement unlocks themes")
	# Refund / revocation detected on restore.
	mock.refund("qa.theme_bundle")
	IAPService.restore()
	check(not IAPService.has_entitlement("theme_bundle"), "refunded item revoked")
	check(IAPService.has_entitlement("remove_ads"), "other purchases intact")
	MockIAPProvider.next_outcome = MockIAPProvider.Outcome.SUCCESS
	FeatureFlags.clear_overrides()
	IAPService.provider = null
	IAPService.initialize()


func test_local_reset_keeps_store_restorable() -> void:
	_reset()
	var mock := _iap_mock()
	IAPService.purchase("remove_ads")
	check(IAPService.has_entitlement("remove_ads"))
	GameState.reset_local_data()
	check(not IAPService.has_entitlement("remove_ads"), "local reset clears local copy")
	IAPService.restore()
	check(IAPService.has_entitlement("remove_ads"), "restore brings the purchase back")
	FeatureFlags.clear_overrides()
	IAPService.provider = null
	IAPService.initialize()
	check(mock != null)


func test_iap_consumables_and_bundle() -> void:
	_reset()
	EconomyService._apply_start_grants()
	var mock := _iap_mock()
	var c0 := EconomyService.coins()
	var pack := int(EconomyService.iap_contents("coins_s").coins)
	check(not IAPService.is_owned(IAPService._product_by_platform_id("qa.coins_s")), "consumables are never 'owned'")
	IAPService.purchase("coins_s")
	check_eq(EconomyService.coins(), c0 + pack, "coins credited")
	check_eq(mock.consumed.size(), 1, "consumed after the grant")
	IAPService.purchase("coins_s")
	check_eq(EconomyService.coins(), c0 + pack * 2, "can be bought again")
	# App dies before the consume reaches the store: the next sync replays it once.
	MockIAPProvider.consume_works = false
	IAPService.purchase("coins_m")
	MockIAPProvider.consume_works = true
	var after := EconomyService.coins()
	IAPService.restore()
	check_eq(EconomyService.coins(), after, "replayed purchase not credited twice")
	check(mock.owned.is_empty() or not mock.owned.has("qa.coins_m"), "and finally consumed")
	# Duplicate store callback for a consumable.
	MockIAPProvider.next_outcome = MockIAPProvider.Outcome.DUPLICATE
	var c1 := EconomyService.coins()
	IAPService.purchase("coins_l")
	check_eq(EconomyService.coins(), c1 + int(EconomyService.iap_contents("coins_l").coins), "duplicate callback credited once")
	MockIAPProvider.next_outcome = MockIAPProvider.Outcome.SUCCESS
	# Starter bundle: Remove Ads + contents, once.
	var h0 := EconomyService.count("hint")
	IAPService.purchase("starter_bundle")
	check(IAPService.has_entitlement("remove_ads"), "bundle grants Remove Ads")
	check_eq(EconomyService.count("hint"), h0 + int(EconomyService.iap_contents("starter_bundle").hint))
	IAPService.restore()
	check_eq(EconomyService.count("hint"), h0 + int(EconomyService.iap_contents("starter_bundle").hint), "restore does not repeat contents")
	var results: Array = []
	var cb := func(_p: String, s: String, _m: String) -> void: results.append(s)
	IAPService.purchase_result.connect(cb)
	IAPService.purchase("starter_bundle")
	IAPService.purchase_result.disconnect(cb)
	check_eq(results, ["already_owned"], "bundle cannot be bought twice")
	# After a local reset, Restore brings back the bundle (entitlement + contents).
	GameState.reset_local_data()
	IAPService.restore()
	check(IAPService.has_entitlement("remove_ads"), "bundle entitlement restored")
	check(EconomyService.count("hint") >= int(EconomyService.iap_contents("starter_bundle").hint), "bundle contents restored")
	FeatureFlags.clear_overrides()
	IAPService.provider = null
	IAPService.initialize()


# --- analytics -----------------------------------------------------------------------

func test_analytics_schema_and_consent() -> void:
	_reset()
	check(not AnalyticsService.track("made_up_event"), "unknown event rejected")
	check(not AnalyticsService.track("level_started", {"level": "1"}), "wrong type rejected")
	check(not AnalyticsService.track("level_started", {"email": "x"}), "unknown param rejected")
	check(AnalyticsService.track("level_started", {"level": 1, "world": "aurora_garden", "resumed": false}))
	check(not AnalyticsService.collecting(), "nothing collected without flag+consent+provider")
	check_eq(AnalyticsService.sanitize("Hello World!/<script>"), "helloworldscript")


func test_banner_respects_flag_consent_and_remove_ads() -> void:
	_reset()
	FeatureFlags.set_override("banner_ads_enabled", false)
	check(not AdsService.banner_allowed(), "flag off")
	FeatureFlags.set_override("banner_ads_enabled", true)
	check(not AdsService.banner_allowed(), "no banner while a Europe/UK device has not answered")
	PrivacyService.record_ads_consent("denied")
	check(AdsService.banner_allowed(), "declined consent -> non-personalized banner")
	PrivacyService.record_ads_consent("not_required")
	check(AdsService.banner_allowed())
	GameState.data.entitlements["remove_ads"] = {"state": "active"}
	check(not AdsService.banner_allowed(), "Remove Ads hides the banner")


func test_consent_region_detection() -> void:
	check(PrivacyService.consent_region_required("DE", ""), "EU locale")
	check(PrivacyService.consent_region_required("GB", "America/New_York"), "UK locale abroad")
	check(PrivacyService.consent_region_required("US", "Europe/Berlin"), "US locale in a European time zone")
	check(PrivacyService.consent_region_required("", "Atlantic/Canary"), "Canary Islands")
	check(not PrivacyService.consent_region_required("US", "America/New_York"))
	check(not PrivacyService.consent_region_required("IL", "Asia/Jerusalem"))
	check(not PrivacyService.consent_region_required("", ""), "unknown region and zone")


func test_consent_resolution_at_launch() -> void:
	_reset()
	PrivacyService.resolve_ads_consent_region(false)
	check_eq(PrivacyService.ads_consent(), "not_required", "outside Europe/UK: no dialog")
	check(not PrivacyService.needs_ads_consent_prompt())
	PrivacyService.resolve_ads_consent_region(true)
	check_eq(PrivacyService.ads_consent(), "unset", "moved into Europe/UK: ask again")
	check(PrivacyService.needs_ads_consent_prompt())
	PrivacyService.record_ads_consent("denied")
	PrivacyService.resolve_ads_consent_region(false)
	check_eq(PrivacyService.ads_consent(), "denied", "a dialog answer is kept")
	PrivacyService.record_ads_consent("obtained")
	PrivacyService.resolve_ads_consent_region(true)
	check_eq(PrivacyService.ads_consent(), "obtained")
	_reset()


# --- save versions (regression: 1.0.0 re-ran old migrations on every launch) ---------

func test_streak_and_level_in_progress_survive_a_relaunch() -> void:
	_reset()
	GameState.data.streak = {"count": 4, "best": 6, "run": 3, "attempt": 12}
	GameState.data.active_session = {"mode": "level", "key": "level:12", "level_id": 12, "session": {"v": 2}}
	check(SaveService.write(GameState.data), "saved")
	var res := SaveService.read()
	var loaded := GameState.migrate(res.payload)
	check_eq(int(loaded.schema_version), int(GameState.defaults().schema_version), "loaded at the current schema")
	check_eq(int(loaded.streak.count), 4, "win streak kept")
	check_eq(int(loaded.streak.run), 3, "streak run kept (gifts are keyed by it)")
	check_eq(str(loaded.active_session.get("key", "")), "level:12", "level in progress kept")
	# A second launch changes nothing either.
	SaveService.write(loaded)
	var again := GameState.migrate(SaveService.read().payload)
	check_eq(int(again.streak.count), 4)
	check_eq(str(again.active_session.get("key", "")), "level:12")


func test_save_written_by_1_0_0_loads_at_its_real_version() -> void:
	# 1.0.0 wrote envelope "schema_version": 2 around a schema-5 payload.
	_reset()
	var payload := GameState.defaults()
	payload.schema_version = 5
	payload.progress.erase("level_ids")
	payload.streak = {"count": 5, "best": 5, "run": 2, "attempt": 0}
	payload.active_session = {"mode": "level", "key": "level:7", "level_id": 7, "session": {"v": 2}}
	var body := JSON.stringify(payload)
	var old_text := JSON.stringify({"format": SaveService.FORMAT, "schema_version": 2, "sha256": body.sha256_text(), "payload": body})
	var decoded: Dictionary = SaveService.decode(old_text)
	check_eq(int(decoded.schema_version), int(payload.schema_version), "payload version wins over the old envelope")
	var m := GameState.migrate(decoded)
	check_eq(int(m.streak.count), 5, "no v<3 reset")
	check_eq(str(m.active_session.get("key", "")), "level:7", "no v<4 drop")
	# Envelopes now carry the payload's version.
	var env: Dictionary = JSON.parse_string(SaveService.encode(m))
	check_eq(int(env.schema_version), int(m.schema_version))


# --- 1.1.0: 100 levels per world (schema 6) -----------------------------------------------

func _save_from_1_0(done_through: int) -> Dictionary:
	## A schema-5 save as 1.0 wrote it: 1.0 levels 1..done_through completed, with Lights, coins,
	## a win-double grant, a streak, a level in progress and the themes earned on the way.
	var p := GameState.defaults()
	p.schema_version = 5
	p.progress = {"completed": {}, "light_sources": ["daily:2026-10-18"]}
	p.cosmetics = {"equipped_theme": "nocturne" if done_through >= 100 else "classic", "seen_themes": ["classic"], "equipped_back": "jade_bamboo_valley" if done_through >= 200 else ""}
	for id in range(1, done_through + 1):
		p.progress.completed[str(id)] = {"t": 0, "stars": 1 + id % 3, "best_score": id}
		p.progress.light_sources.append("level:%d" % id)
		p.economy.ledger["level:%d" % id] = 1
	p.economy.ledger["ad:win_double:level:75"] = 1
	p.economy.ledger["world:aurora_garden"] = 1
	p.economy.ledger["welcome_existing_v1"] = 1
	p.ads.reward_grants = ["ad:win_double:level:75", "ad:booster:3"]
	p.streak = {"count": 4, "best": 6, "run": 2, "attempt": done_through + 1}
	p.active_session = {"mode": "level", "key": "level:75", "level_id": 75, "session": {"v": 2, "level_key": "level:75"}}
	return p


func test_migration_moves_1_0_level_ids() -> void:
	var m := GameState.migrate(_save_from_1_0(120))
	check_eq(int(m.schema_version), 6)
	check_eq(int(m.progress.level_ids), 2)
	var done: Dictionary = m.progress.completed
	check_eq(done.size(), 120, "every completed level kept")
	for id in [1, 50, 101, 150, 201, 220]:
		check(done.has(str(id)), "level %d completed" % id)
	for id in [51, 75, 100, 151, 200, 221]:
		check(not done.has(str(id)), "level %d is new or not reached" % id)
	check_eq(int(done["125"].stars), 1 + 75 % 3, "stars move with the level")
	check(m.progress.light_sources.has("level:125") and not m.progress.light_sources.has("level:75"), "Lights move")
	check(m.progress.light_sources.has("daily:2026-10-18"), "other Lights untouched")
	check_eq(m.progress.light_sources.size(), 121, "no Light lost or added")
	check(m.economy.ledger.has("level:220") and not m.economy.ledger.has("level:75"), "first-clear coins move")
	check(m.economy.ledger.has("ad:win_double:level:125"), "win-double grant moves")
	check(m.economy.ledger.has("world:aurora_garden") and m.economy.ledger.has("welcome_existing_v1"), "other grants untouched")
	check(m.ads.reward_grants.has("ad:win_double:level:125") and m.ads.reward_grants.has("ad:booster:3"), "ad grants move")
	check_eq(int(m.streak.attempt), 221, "the attempt moves")
	check_eq(int(m.streak.count), 4, "streak kept")
	check_eq(int(m.active_session.level_id), 125)
	check_eq(str(m.active_session.key), "level:125")
	check_eq(str(m.active_session.session.level_key), "level:125")
	check_eq(m.progress.open, [101, 201], "worlds a 1.0 player had reached stay open")
	check(m.cosmetics.granted.has("ocean") and m.cosmetics.granted.has("nocturne"), "themes earned at 1.0 levels 50 and 100 kept")
	check(not m.cosmetics.granted.has("jade_bamboo_valley"), "no back that was not earned")
	check(bool(m.progress.new_levels_notice), "the player hears about the new levels once")
	# Exactly once: a second migration (and a save/load) changes nothing.
	var text := JSON.stringify(m)
	check_eq(JSON.stringify(GameState.migrate(m.duplicate(true))), text, "migrating again changes nothing")
	var reloaded := GameState.migrate(SaveService.decode(SaveService.encode(m)))
	check_eq(int(reloaded.active_session.level_id), 125, "a relaunch keeps the new ids")
	check_eq((reloaded.progress.completed as Dictionary).size(), 120)


func test_migrated_player_continues_where_they_were() -> void:
	_reset()
	GameState.data = GameState.migrate(_save_from_1_0(120))
	GameState.data.active_session = {}
	check_eq(GameState.next_level(ContentService.level_count()), 221, "continues after 1.0 level 120")
	check(GameState.is_level_unlocked(51) and GameState.is_level_unlocked(151), "each world's new levels are open")
	check(not GameState.is_level_unlocked(52), "and played in order")
	check(GameState.is_level_unlocked(101) and GameState.is_level_unlocked(221))
	check(ProgressionService.is_theme_unlocked("nocturne"), "nocturne stays earned (now at level 200)")
	check_eq(ProgressionService.equipped_theme(), "nocturne")
	# A new level that took an old number pays its own Light and coins.
	var lights0 := ProgressionService.lights()
	var r := ProgressionService.complete_level(75, {"moves": 5, "hints": 0})
	check(bool(r.first_time) and bool(r.light_awarded), "level 75 is new: a Light")
	check_eq(ProgressionService.lights(), lights0 + 1)
	check_eq(int(r.get("coins", 0)), EconomyService.level_reward(75), "and its first-clear coins")
	# Finishing world 1 later does not announce world 2 again.
	for id in range(51, 100):
		GameState.data.progress.completed[str(id)] = {"t": 0}
	check_eq(str(ProgressionService.complete_level(100, {}).get("world_unlocked", "")), "", "world 2 was already open")


func test_migrated_player_keeps_world_and_back_from_1_0() -> void:
	_reset()
	# Finished 1.0 world 1 exactly: world 2 stays open although levels 51-100 are new.
	GameState.data = GameState.migrate(_save_from_1_0(50))
	check(GameState.is_level_unlocked(101), "world 2 still open")
	check(GameState.is_level_unlocked(51), "and world 1's new levels")
	check_eq(GameState.next_level(ContentService.level_count()), 51)
	# Finished 1.0 world 4 (level 200): its tile back stays earned (the world now ends at 400).
	GameState.data = GameState.migrate(_save_from_1_0(200))
	check(ProgressionService.is_back_unlocked("jade_bamboo_valley"), "Jade Bamboo Valley back kept")
	check_eq(ProgressionService.equipped_back(), "jade_bamboo_valley")
	check(not ProgressionService.is_back_unlocked("sunset_lotus_palace"))
	check(GameState.is_level_unlocked(301) and GameState.is_level_unlocked(351))
	# A fresh player earns nocturne at level 200 now.
	GameState.data = GameState.defaults()
	for id in range(1, 151):
		GameState.data.progress.completed[str(id)] = {"t": 0}
	check(not ProgressionService.is_theme_unlocked("nocturne"))


func test_board_in_progress_resumes_on_its_new_number() -> void:
	# A real 1.0 snapshot of 1.0 level 75 restores onto level 125 (the same board).
	var legacy := LevelCatalog.load_legacy()
	var old := LevelDefinition.from_dict(legacy[74])
	check_eq(old.key, "level:75")
	var s := GameSession.start(old)
	var free := s.state.free_tiles()
	s.tap(free[0])
	var save := _save_from_1_0(120)
	save.active_session = {"mode": "level", "key": old.key, "level_id": 75, "session": s.to_dict()}
	var m := GameState.migrate(JSON.parse_string(JSON.stringify(save)))
	var L := ContentService.get_level(125)
	check_eq(str(m.active_session.key), L.key)
	var back := GameSession.restore(L, m.active_session.session)
	check(back != null, "the snapshot restores on level 125")
	if back != null:
		check_eq(back.tray.size(), s.tray.size(), "same tray")
		check_eq(back.state.remaining, s.state.remaining, "same tiles left")
