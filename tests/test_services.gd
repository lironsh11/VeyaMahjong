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
	check_eq(int(m.schema_version), 1)
	check(typeof(m.progress.completed) == TYPE_DICTIONARY and m.progress.completed.has("2"), "list migrated to dict")
	check_eq(m.settings.music_on, false, "existing settings kept")
	check(m.settings.has("reduced_motion"), "missing defaults filled")
	check(m.has("daily") and m.daily.has("completed"), "new sections added")


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
	for id in range(1, 50):
		GameState.data.progress.completed[str(id)] = {"t": 0}
	var r := ProgressionService.complete_level(50, {})
	check_eq(r.world_unlocked, "pearl_coast")
	check(GameState.is_level_unlocked(51))
	check_eq(ProgressionService.complete_level(50, {}).world_unlocked, "", "not reported again")


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
	# Daily boards must never change silently. Fingerprints recorded 2026-10-18 for "daily-2"
	# (identical-tiles-only rule). A mismatch means an algorithm change that requires bumping
	# DailyGenerator.VERSION and re-pinning; completions are keyed by date and survive.
	check_eq(DailyGenerator.VERSION.get_slice(" ", 0), "daily-2")
	var pinned := {
		"2026-10-18": "f2c7feb014f9bc43", "2026-10-19": "447aca24610a4145",
		"2026-11-03": "6bdadd667d37669e", "2027-02-28": "721abd54174f9915",
		"2028-02-29": "b1d270fb4b93aa60",
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

func test_ads_disabled_by_default() -> void:
	_reset()
	check_eq(AdsService.state, AdsService.State.DISABLED)
	check(not AdsService.is_rewarded_ready("bonus_light"), "never a fake ready ad")
	check(not AdsService.can_show_interstitial_now("level_complete_continue"))


func _ads_mock(mode: int) -> void:
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


func test_rewarded_duplicate_callback_grants_once() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.DUPLICATE_CALLBACK)
	AdsService.load_rewarded("bonus_light")
	check(AdsService.is_rewarded_ready("bonus_light"))
	var grants := [0]
	AdsService.show_rewarded("bonus_light", "ad:level:1", func() -> void: grants[0] += 1)
	check_eq(grants[0], 1, "duplicate SDK callback granted once")
	AdsService.load_rewarded("bonus_light")
	AdsService.show_rewarded("bonus_light", "ad:level:1", func() -> void: grants[0] += 1)
	check_eq(grants[0], 1, "same grant id never granted twice")
	_reset()


func test_rewarded_no_fill_and_not_completed() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.NO_FILL)
	AdsService.load_rewarded("bonus_light")
	check(not AdsService.is_rewarded_ready("bonus_light"), "no-fill -> no button")
	_ads_mock(MockAdProvider.Mode.NOT_COMPLETED)
	AdsService.load_rewarded("bonus_light")
	var grants := [0]
	AdsService.show_rewarded("bonus_light", "ad:x", func() -> void: grants[0] += 1)
	check_eq(grants[0], 0, "closing early grants nothing")
	_reset()


func test_rewarded_daily_cap() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.FILL)
	FeatureFlags.set_override("rewarded_daily_cap", 2)
	var grants := [0]
	for k in 3:
		AdsService.load_rewarded("p")
		AdsService.show_rewarded("p", "g%d" % k, func() -> void: grants[0] += 1)
	check_eq(grants[0], 2, "capped per day")
	_reset()


func test_interstitial_policy() -> void:
	_reset()
	_ads_mock(MockAdProvider.Mode.FILL)
	FeatureFlags.set_override("interstitials_enabled", true)
	GameState.data.tutorial_done = true
	AdsService._session_started_unix -= 600
	GameState.data.ads.levels_since_interstitial = 10
	AdsService.load_interstitial()
	check(not AdsService.can_show_interstitial_now("board"), "never mid-board")
	check(AdsService.can_show_interstitial_now("level_complete_continue"), "allowed at natural break")
	GameState.data.entitlements["remove_ads"] = {"state": "active"}
	check(not AdsService.can_show_interstitial_now("level_complete_continue"), "Remove Ads respected")
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
	check(AdsService.banner_allowed(), "banner on before a CMP result, non-personalized")
	PrivacyService.record_ads_consent("denied")
	check(not AdsService.banner_allowed(), "declined consent hides the banner")
	PrivacyService.record_ads_consent("not_required")
	check(AdsService.banner_allowed())
	GameState.data.entitlements["remove_ads"] = {"state": "active"}
	check(not AdsService.banner_allowed(), "Remove Ads hides the banner")
