extends Node
## DEBUG-ONLY visual QA driver. Started by Router only in debug builds when the game is
## launched with:  godot --path . -- --tour=<out_dir> [--locale=he] [--save-dir=user://tour]
## Extra modes: --levels=1,7,50 (boards only), --bloom-all (every discovery unlocked),
## --consent (ads consent dialog, first run and Settings).
## Visits every screen and dialog, saving viewport captures as PNG. It uses an isolated save
## directory (see SaveService) so real player data is never touched.

var out_dir: String = ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			out_dir = a.trim_prefix("--tour=")
		if a.begins_with("--set="):
			var kv := a.trim_prefix("--set=").split("=")
			var v: Variant = kv[1]
			if kv[1] in ["true", "false"]:
				v = kv[1] == "true"
			GameState.set_setting(kv[0], v)
		if a.begins_with("--locale="):
			GameState.set_setting("locale", a.trim_prefix("--locale="))
			LocalizationService.apply_setting(a.trim_prefix("--locale="))
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Low-processor mode only redraws on change; captures need continuous frames.
	OS.low_processor_usage_mode = false
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("TOUR shot ", name, " ", img.get_size())


func _close_modals(scr: Node, result: String) -> void:
	## Closes the level-start (or any) dialog the screen opened, as if `result` was tapped.
	for m in scr.find_children("*", "ModalDialog", true, false):
		m.close(result)
	await _wait(0.4)


func _unmatched_free(scr: Node) -> int:
	## A free tile whose twin is not in the tray (fills a slot), else any free tile.
	var st: BoardState = scr.session.state
	var free := st.free_tiles()
	for i in free:
		if TrayRules.partner_slot(scr.session.tray, st.keys, i) < 0:
			return i
	return free[0]


func _go(screen: String, params: Dictionary = {}) -> void:
	Router.go(screen, params, false)
	await _wait(0.9)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--levels="):
			# Board-only mode: capture specific levels and quit.
			await _wait(1.5)
			GameState.data.tutorial_done = true
			for id in a.trim_prefix("--levels=").split(","):
				await _go("gameplay", {"mode": "level", "level": int(id), "restart": true})
				await _close_modals(Router.current_screen(), "play")  # the board, not the start dialog
				await _shot("level_%03d" % int(id))
				var bv: BoardView = Router.current_screen().board
				print("BOARD level=%d area=%s tile_w=%.1f" % [int(id), bv.size, bv.tile_w])
			get_tree().quit()
			return
		if a == "--bloom-all":
			# Bloom placement check: every level completed, so every discovery is unlocked.
			await _wait(1.5)
			GameState.data.tutorial_done = true
			for id in range(1, ContentService.level_count() + 1):
				ProgressionService.complete_level(id, {"moves": 10, "hints": 0})
			for w in ContentService.worlds:
				await _go("bloom", {"world": str(w.id)})
				await _wait(1.2)
				await _shot("bloom_all_" + str(w.id))
			get_tree().quit()
			return
		if a == "--economy":
			await _economy_tour()
			get_tree().quit()
			return
		if a == "--consent":
			# Ads consent dialog as a Europe/UK device sees it at first launch, then from Settings.
			await _wait(1.0)
			var first := ConsentDialog.open(Router.current_screen())
			await _wait(0.6)
			await _shot("consent_first_run")
			first.close("denied")
			GameState.data.tutorial_done = true
			await _go("settings")
			var label := LocalizationService.t("privacy_choices")
			var found := Router.current_screen().find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == label)
			print("TOUR privacy_choices button: ", found.size(), " consent=", PrivacyService.ads_consent())
			ConsentDialog.open(Router.current_screen(), true)
			await _wait(0.6)
			await _shot("consent_settings")
			get_tree().quit()
			return
	await _wait(0.35)
	await _shot("01_boot")
	await _wait(1.0)
	await _shot("02_tutorial")
	print("TOUR seeding")
	GameState.data.tutorial_done = true
	# Seed some progress so the screens show realistic states.
	for id in range(1, 13):
		print("TOUR complete ", id)
		ProgressionService.start_attempt(id)
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0, "score": 300, "stars": 1 + (id % 3)})
	GameState.data.streak.count = 4
	await _go("home")
	await _shot("03_home")
	await _go("worlds")
	await _shot("04_worlds")
	await _go("gameplay", {"mode": "level", "level": 13, "restart": true})
	await _shot("05a_level_start")
	var scr: Node = Router.current_screen()
	await _close_modals(scr, "slot")
	await _shot("05_gameplay_l13")
	# Two quick pairs (combo praise mid-burst), then one tile caught mid-flight.
	for n in 2:
		var pick := BoardController.best_guess(scr.session.state, scr.session.tray)
		for i in pick:
			scr.controller._on_tap(i)
		if pick.size() == 1:
			scr.controller._on_tap(BoardController.best_guess(scr.session.state, scr.session.tray)[0])
		await _wait(0.12)
	await _wait(0.3)
	await _shot("05b_gameplay_combo")
	await _wait(0.8)
	var single := _unmatched_free(scr)
	scr.controller._on_tap(single)
	await _wait(0.14)
	await _shot("05c_gameplay_flight")
	await _wait(0.5)
	await _shot("05d_gameplay_tray")
	scr.controller.request_hint()
	await _wait(1.0)
	await _shot("06_gameplay_tray_hint")
	scr._open_pause()
	await _wait(0.4)
	await _shot("07_pause")
	await _go("gameplay", {"mode": "level", "level": 150, "restart": true})
	scr = Router.current_screen()
	await _close_modals(scr, "play")
	await _shot("08_gameplay_l150")
	scr._open_rescue(false)
	await _wait(0.4)
	await _shot("09_stuck")
	await _go("gameplay", {"mode": "level", "level": 20, "restart": true})
	scr = Router.current_screen()
	await _close_modals(scr, "play")
	while not scr.session.failed and not scr.session.completed:
		scr.controller._on_tap(_unmatched_free(scr))
		await _wait(0.08)
		if scr.session.tray.size() == scr.session.capacity - 1 and not has_meta("danger_shot"):
			set_meta("danger_shot", true)
			await _wait(0.4)
			await _shot("09b_tray_danger")
	await _wait(1.2)
	await _shot("09c_tray_full")
	await _go("gameplay", {"mode": "level", "level": 14, "restart": true})
	scr = Router.current_screen()
	await _close_modals(scr, "play")
	var L: LevelDefinition = scr.level
	for k in L.solution.size():
		scr.controller._on_tap(L.solution[k].x)
		scr.controller._on_tap(L.solution[k].y)
	await _wait(1.6)
	await _shot("10_win")
	await _go("bloom", {"world": "aurora_garden"})
	await _wait(0.8)
	await _shot("11_bloom")
	await _go("daily")
	await _shot("12_daily")
	await _go("collection")
	await _shot("13_collection")
	await _go("shop")
	await _shot("14_shop")
	await _go("settings")
	await _shot("15_settings")
	print("TOUR done")
	get_tree().quit()


func _economy_tour() -> void:
	## Booster economy states with QA-mock ads and store (debug only).
	await _wait(1.5)
	FeatureFlags.set_override("qa_mock_services", true)
	FeatureFlags.set_override("ads_enabled", true)
	FeatureFlags.set_override("rewarded_ads_enabled", true)
	FeatureFlags.set_override("interstitials_enabled", true)
	PrivacyService.record_ads_consent("not_required")
	AdsService.dispose()
	AdsService.initialize()
	IAPService.provider = null
	IAPService.initialize()
	GameState.data.tutorial_done = true
	for id in range(1, 13):
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0})
	GameState.data.economy.welcome_notice_pending = true
	await _go("home")
	await _wait(0.6)
	await _shot("econ_01_home_welcome")
	GameState.data.economy.welcome_notice_pending = false
	await _go("gameplay", {"mode": "level", "level": 13, "restart": true})
	await _shot("econ_02_gameplay_badges")
	var scr: Node = Router.current_screen()
	GameState.data.economy.inv.hint = 0
	scr._refresh_badges()
	scr._open_get_more("hint")
	await _wait(0.5)
	await _shot("econ_03_out_of_hints")
	await _go("gameplay", {"mode": "level", "level": 13, "restart": true})
	scr = Router.current_screen()
	scr._open_rescue(true)
	await _wait(0.5)
	await _shot("econ_04_rescue")
	await _go("gameplay", {"mode": "level", "level": 14, "restart": true})
	scr = Router.current_screen()
	await _close_modals(scr, "play")
	var L: LevelDefinition = scr.level
	for k in L.solution.size():
		scr.controller._on_tap(L.solution[k].x)
		scr.controller._on_tap(L.solution[k].y)
	await _wait(1.6)
	await _shot("econ_05_win_coins")
	await _go("shop")
	await _wait(0.4)
	await _shot("econ_06_shop")
	await _go("bloom", {"world": "aurora_garden"})
	await _wait(0.8)
	await _shot("econ_07_bloom")
	print("TOUR economy done")
