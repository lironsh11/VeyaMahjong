extends Node
## DEBUG-ONLY visual QA driver. Started by Router only in debug builds when the game is
## launched with:  godot --path . -- --tour=<out_dir> [--locale=he] [--save-dir=user://tour]
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
				await _shot("level_%03d" % int(id))
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
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0})
	await _go("home")
	await _shot("03_home")
	await _go("worlds")
	await _shot("04_worlds")
	await _go("gameplay", {"mode": "level", "level": 13, "restart": true})
	await _shot("05_gameplay_l13")
	var scr: Node = Router.current_screen()
	var free: PackedInt32Array = scr.session.state.free_tiles()
	scr.controller._on_tap(free[0])
	scr.controller.request_hint()
	await _wait(1.0)
	await _shot("06_gameplay_selected_hint")
	scr._open_pause()
	await _wait(0.4)
	await _shot("07_pause")
	await _go("gameplay", {"mode": "level", "level": 150, "restart": true})
	await _shot("08_gameplay_l150")
	scr = Router.current_screen()
	scr._open_rescue(true)
	await _wait(0.4)
	await _shot("09_no_moves")
	await _go("gameplay", {"mode": "level", "level": 14, "restart": true})
	scr = Router.current_screen()
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
