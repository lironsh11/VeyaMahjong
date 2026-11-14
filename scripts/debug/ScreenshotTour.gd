extends Node
## DEBUG-ONLY visual QA driver. Started by Router only in debug builds when the game is
## launched with:  godot --path . -- --tour=<out_dir> [--locale=he] [--save-dir=user://tour]
## Extra modes: --levels=1,7,50 (boards only), --bloom-all (every discovery unlocked),
## --consent (ads consent dialog, first run and Settings).
## Visits every screen and dialog, saving viewport captures as PNG. It uses an isolated save
## directory (see SaveService) so real player data is never touched.

var out_dir: String = ""
var _recording: bool = false   ## --preview: every rendered frame is saved (with --fixed-fps 30)
var _frame_n: int = 0


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
	img.convert(Image.FORMAT_RGB8)  # App Store Connect rejects screenshots with an alpha channel
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--expect="):
			var want := a.trim_prefix("--expect=").split("x")
			if img.get_width() != int(want[0]) or img.get_height() != int(want[1]):
				push_error("TOUR %s is %s, expected %s" % [name, img.get_size(), a])
				get_tree().quit(2)
				return
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


func _layout_shot(spec: String) -> void:
	var f := spec.split(":")
	var rng := SeededRng.new(int(f[5]) if f.size() > 5 else 1)
	var pos := LayoutTemplates.generate(rng, f[0], int(f[3]), int(f[1]), int(f[2]), f[4] if f.size() > 4 else "top")
	if pos.is_empty():
		print("TOUR layout %s: cannot build" % spec)
		return
	var L := BoardGenerator.new().generate_level(pos, "tour|" + spec)
	var top := CanvasLayer.new()
	top.layer = 200
	get_tree().root.add_child(top)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.33, 0.27)
	top.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var board := BoardView.new()
	bg.add_child(board)
	board.size = BoardFit.PLAY_AREA
	board.position = (get_viewport().get_visible_rect().size - board.size) * 0.5
	board.setup(L.build_state(), ProgressionService.equipped_theme())
	await _wait(0.4)
	await _shot("layout_" + spec.replace(":", "_"))
	print("TOUR layout %s: %d tiles, %d layers, tile_w %.1f" % [spec, pos.size(), LayoutTemplates.layer_count(pos), board.tile_w])
	top.queue_free()
	await _wait(0.1)


func _go(screen: String, params: Dictionary = {}) -> void:
	Router.go(screen, params, false)
	await _wait(0.9)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layouts="):
			# Template check: --layouts=family:cols:layers:tiles[:mode[:seed]],... renders each
			# LayoutTemplates board alone in the play area (add --board-debug for layer/state tags).
			await _wait(1.0)
			for m in get_tree().root.find_children("*", "ModalDialog", true, false):
				m.close("denied")  # first-run consent
			for spec in a.trim_prefix("--layouts=").split(","):
				await _layout_shot(spec)
			get_tree().quit()
			return
		if a.begins_with("--levels="):
			# Board-only mode: capture specific levels and quit.
			await _wait(1.5)
			GameState.data.tutorial_done = true
			var picks := 0
			for b in OS.get_cmdline_user_args():
				if b.begins_with("--picks="):
					picks = int(b.trim_prefix("--picks="))  # then play this many picks and shoot again
			for id in a.trim_prefix("--levels=").split(","):
				await _go("gameplay", {"mode": "level", "level": int(id), "restart": true})
				await _close_modals(Router.current_screen(), "play")  # the board, not the start dialog
				await _shot("level_%03d" % int(id))
				var bv: BoardView = Router.current_screen().board
				print("BOARD level=%d area=%s tile_w=%.1f" % [int(id), bv.size, bv.tile_w])
				if picks > 0:
					var scr: Node = Router.current_screen()
					var top: int = scr.session.state.geo.max_z
					for n in picks:
						# Highest free tile first, so the shot shows lower tiles uncovered.
						var st: BoardState = scr.session.state
						var best := -1
						for i in st.free_tiles():
							if best < 0 or st.geo.gz[i] > st.geo.gz[best]:
								best = i
						if best < 0 or scr.session.failed:
							break
						scr.controller._on_tap(best)
						await _wait(0.5)
					await _wait(0.8)
					await _shot("level_%03d_after_%d_picks" % [int(id), picks])
					print("BOARD level=%d after %d picks: top layer %d, %d tiles left" % [int(id), picks, top, scr.session.state.remaining])
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
		if a == "--iap-review":
			await _iap_review_shots()
			get_tree().quit()
			return
		if a == "--preview":
			await _preview_tour()
			get_tree().quit()
			return
		if a == "--store":
			await _store_tour()
			get_tree().quit()
			return
		if a == "--together":
			await _together_tour()
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
	await _go("gameplay", {"mode": "level", "level": 250, "restart": true})
	scr = Router.current_screen()
	await _close_modals(scr, "play")
	await _shot("08_gameplay_l250")
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
	await _new_worlds_tour()
	print("TOUR done")
	get_tree().quit()


func _new_worlds_tour() -> void:
	## The "Three New Worlds" (levels 301-600): maps, boards, Bloom and the tile back.
	for id in range(13, 401):
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0, "score": 300, "stars": 1 + (id % 3)})
	ProgressionService.equip_back("jade_bamboo_valley")
	await _go("worlds", {"world": "jade_bamboo_valley"})
	await _shot("16_worlds_jade")
	await _go("worlds", {"world": "sunset_lotus_palace"})
	await _shot("16b_worlds_sunset")
	await _go("worlds", {"world": "frostlight_village"})
	await _shot("16c_worlds_frost_locked")
	await _go("gameplay", {"mode": "level", "level": 401, "restart": true})
	var scr: Node = Router.current_screen()
	for m in scr.find_children("*", "ModalDialog", true, false):
		m.close("play")
	await _wait(0.12)
	await _shot("17a_deal_flip")
	await _wait(0.8)
	await _shot("17_gameplay_l401")
	await _go("gameplay", {"mode": "level", "level": 600, "restart": true})
	scr = Router.current_screen()
	await _close_modals(scr, "play")
	await _shot("18_gameplay_l600")
	await _go("bloom", {"world": "jade_bamboo_valley"})
	await _wait(0.8)
	await _shot("19_bloom_jade")
	await _go("collection")
	for sc in Router.current_screen().find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 100000
	await _wait(0.3)
	await _shot("20_collection_backs")


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


func _modal_open() -> bool:
	return not get_tree().root.find_children("*", "ModalDialog", true, false).is_empty()


func _wait_for_modal(max_s: float) -> void:
	var t := 0.0
	while not _modal_open() and t < max_s:
		await _wait(0.1)
		t += 0.1
	await _wait(0.5)


func _together_tour() -> void:
	## Play Together and Board Studio (store screenshots and visual QA): Home with the two new
	## cards, the Duet setup, a live shared board (Team-up and the pass cue), the team results,
	## and the Studio's Create / ready / My boards / Enter code screens.
	await _wait(1.0)
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("denied")  # first-run consent
	GameState.data.tutorial_done = true
	for id in range(1, 13):
		ProgressionService.start_attempt(id)
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0, "score": 300, "stars": 1 + (id % 3)})
	var he := LocalizationService.current == "he"
	FreePlayService.set_player_name(0, "מאיה" if he else "Maya")
	FreePlayService.set_player_name(1, "נועם" if he else "Noam")
	FreePlayService.set_player_color(0, 0)
	FreePlayService.set_player_color(1, 1)
	GameState.data.duet.first = 0
	await _ensure_home()
	await _shot("21_home_cards")
	await _go("duet")
	await _shot("22_duet_setup")
	await _go("freeplay", {"kind": "duet", "code": StudioBoard.SAMPLE_CODE, "difficulty": "medium", "restart": true})
	await _wait(1.6)  # deal flip
	var scr: Node = Router.current_screen()
	# A real tray-play order from the solver (pairs get finished by both players), else the witness.
	var sol: Dictionary = TraySolver.new(400000, 8000, scr.session.capacity).solve(scr.session.state.clone(), scr.session.tray.duplicate())
	var picks: PackedInt32Array = sol.solution if sol.result == BoardSolver.Result.SOLVED else TraySolver.flatten(scr.level.solution)
	print("TOUR duet picks from ", "solver" if sol.result == BoardSolver.Result.SOLVED else "witness")
	scr.controller._on_tap(picks[0])
	await _wait(1.0)
	await _shot("23_duet_pass")
	scr.controller._on_tap(picks[1])  # the partner finishes the pair: a Team-up
	await _wait(0.3)
	await _shot("24_duet_teamup")
	for k in range(2, 9):
		await _wait(0.45)
		scr.controller._on_tap(picks[k])
	await _wait(1.0)
	await _shot("25_duet_midgame")
	for k in range(9, picks.size()):
		scr.board.input_enabled = true
		scr.controller._on_tap(picks[k])
		await _wait(0.02)
	await _wait_for_modal(4.0)
	await _wait(1.2)
	await _shot("26_duet_results")
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("home")
	await _wait(1.2)
	var studio := load("res://scripts/screens/StudioScreen.gd")
	studio._params = {"family": "turtle", "cols": 6, "layers": 4, "mode": "top", "tiles": 76, "seed": 1}
	await _go("studio", {"tab": "create"})
	await _wait(0.4)
	await _shot("27_studio_create")
	Router.current_screen()._check_and_play()
	await _wait_for_modal(10.0)
	await _shot("28_studio_ready")
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("close")
	FreePlayService.save_board(StudioBoard.SAMPLE_CODE, true)
	FreePlayService.record_studio_win(StudioBoard.SAMPLE_CODE, 1460)
	await _go("studio", {"tab": "mine"})
	await _shot("29_studio_mine")
	await _go("studio", {"tab": "code"})
	var sc: Node = Router.current_screen()
	sc._code_text = StudioBoard.SAMPLE_CODE.replace("V", "W")
	sc._code_field.text = sc._code_text
	sc._play_code()
	await _wait(0.4)
	await _shot("30_studio_code_error")
	sc._code_text = StudioBoard.SAMPLE_CODE.to_lower()
	sc._code_field.text = sc._code_text
	sc._play_code()
	await _wait_for_modal(3.0)
	await _shot("31_studio_code_ok")


# --- store screenshots ------------------------------------------------------------------

const STORE_BG := Color("0D4F40")
const STORE_EDGE := Color("F4C568")


func _store_shot(n: int, slug: String, caption: String) -> void:
	## Saves the real screen as NN_slug_raw.png, then the store version NN_slug.png: the same
	## capture, scaled into the frame under a caption band (no device frame, no invented UI).
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var raw := get_viewport().get_texture().get_image()
	raw.convert(Image.FORMAT_RGB8)
	var name := "%02d_%s" % [n, slug]
	raw.save_png(out_dir.path_join(name + "_raw.png"))
	var vp := get_viewport().get_visible_rect().size
	var layer := CanvasLayer.new()
	layer.layer = 300
	get_tree().root.add_child(layer)
	# A left-to-right root, attached before anything is positioned: in a right-to-left language
	# Godot would otherwise mirror these positions off-screen (caption text stays RTL).
	var box := Control.new()
	box.layout_direction = Control.LAYOUT_DIRECTION_LTR
	layer.add_child(box)
	box.size = vp
	var bg := ColorRect.new()
	box.add_child(bg)
	bg.color = STORE_BG
	bg.size = vp
	var band_h := roundf(vp.y * 0.15)
	# One line whose font shrinks until it fits: a wrapping label measures its height at zero
	# width in its first frame (and grows far taller than the band), and anything positioned
	# before it is attached is mirrored in a right-to-left locale.
	var l := Label.new()
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_AUTO
	l.add_theme_color_override("font_color", UITheme.IVORY)
	if UITheme.font_bold:
		l.add_theme_font_override("font", UITheme.font_bold)
	box.add_child(l)
	var font: Font = l.get_theme_font("font")
	var fsz := 42
	while fsz > 22 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > vp.x - 56:
		fsz -= 1
	l.add_theme_font_size_override("font_size", fsz)
	l.size = Vector2(vp.x - 48, band_h - 10)
	l.position = Vector2(24, 10)
	var margin := 26.0
	var avail := Vector2(vp.x - margin * 2.0, vp.y - band_h - margin)
	var k := minf(avail.x / vp.x, avail.y / vp.y)
	var shown := vp * k
	var at := Vector2((vp.x - shown.x) * 0.5, band_h)
	var edge := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = STORE_EDGE
	sb.set_corner_radius_all(22)
	edge.add_theme_stylebox_override("panel", sb)
	box.add_child(edge)
	edge.position = at - Vector2(4, 4)
	edge.size = shown + Vector2(8, 8)
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(raw)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	box.add_child(tr)
	tr.position = at
	tr.size = shown
	await _wait(0.1)
	await _shot(name)
	layer.queue_free()
	await _wait(0.05)


func _store_tour() -> void:
	## The App Store / Google Play screenshots, in the order of docs/STORE_LISTINGS/captions.json.
	## Run once per locale and device size, e.g.
	##   godot --path . --resolution 1320x2868 -- --tour=build/store/en/iphone --store --locale=en --expect=1320x2868 --save-dir=user://store
	var caps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/STORE_LISTINGS/captions.json"))
	var loc := LocalizationService.current
	var lines: Array = caps.get(loc, caps.en)
	await _wait(1.0)
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("denied")  # first-run consent
	GameState.data.tutorial_done = true
	for id in range(1, 311):  # worlds 1-3 done, Jade Bamboo Valley under way (store shot 5)
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0, "score": 300, "stars": 2 + (id % 2)})
	var he := loc == "he"
	FreePlayService.set_player_name(0, "מאיה" if he else "Maya")
	FreePlayService.set_player_name(1, "נועם" if he else "Noam")
	FreePlayService.set_player_color(0, 0)
	FreePlayService.set_player_color(1, 1)
	GameState.data.duet.first = 0
	await _ensure_home()
	# 1. Play Together: a shared board mid-game, the hand-off cue showing.
	await _go("freeplay", {"kind": "duet", "code": StudioBoard.SAMPLE_CODE, "difficulty": "medium", "restart": true})
	await _wait(1.6)
	var scr: Node = Router.current_screen()
	var sol: Dictionary = TraySolver.new(400000, 8000, scr.session.capacity).solve(scr.session.state.clone(), scr.session.tray.duplicate())
	var picks: PackedInt32Array = sol.solution if sol.result == BoardSolver.Result.SOLVED else TraySolver.flatten(scr.level.solution)
	for k in 7:
		scr.board.input_enabled = true
		scr.controller._on_tap(picks[k])
		await _wait(0.5)
	scr.board.input_enabled = true
	scr.controller._on_tap(picks[7])
	await _wait(0.45)
	await _store_shot(1, "play_together", lines[0])
	# 2-3. Board Studio: the editor, then the solver-checked board with its code.
	var studio := load("res://scripts/screens/StudioScreen.gd")
	studio._params = {"family": "turtle", "cols": 6, "layers": 4, "mode": "top", "tiles": 72, "seed": 1}
	await _go("studio", {"tab": "create"})
	await _wait(0.4)
	await _store_shot(2, "board_studio", lines[1])
	Router.current_screen()._check_and_play()
	await _wait_for_modal(10.0)
	await _store_shot(3, "board_code", lines[2])
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("close")
	await _wait(0.6)
	# 4. Tray play on a layered level.
	await _go("gameplay", {"mode": "level", "level": 220, "restart": true})  # 1.0 level 120's board
	scr = Router.current_screen()
	await _close_modals(scr, "play")
	await _wait(1.0)
	# Play the solver's moves (never a dead end) until two tiles wait in the tray.
	var lsol: Dictionary = TraySolver.new(400000, 8000, scr.session.capacity).solve(scr.session.state.clone(), scr.session.tray.duplicate())
	var lpicks: PackedInt32Array = lsol.solution if lsol.result == BoardSolver.Result.SOLVED else TraySolver.flatten(scr.level.solution)
	for k in mini(40, lpicks.size()):
		scr.controller._on_tap(lpicks[k])
		await _wait(0.3)
		if k >= 9 and scr.session.tray.size() >= 1:
			break
	await _wait(1.3)  # let the combo praise fade
	await _store_shot(4, "tray", lines[3])
	# 5. Worlds (a newer world's map).
	await _go("worlds", {"world": "jade_bamboo_valley"})
	await _wait(0.4)
	await _store_shot(5, "worlds", lines[4])
	# 6. Bloom.
	await _go("bloom", {"world": "aurora_garden"})
	await _wait(1.0)
	await _store_shot(6, "bloom", lines[5])
	# 7. Daily.
	await _go("daily")
	await _wait(0.4)
	await _store_shot(7, "daily", lines[6])
	# 8. Accessibility settings.
	await _go("settings")
	await _wait(0.3)
	for sc in Router.current_screen().find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 520
	await _wait(0.4)
	await _store_shot(8, "accessibility", lines[7])
	print("TOUR store done")


func _preview_tour() -> void:
	## App Preview video (record with Movie Maker at a fixed 30 fps, then trim the first
	## PREVIEW_TRIM_S seconds of boot in ffmpeg; see docs/STORE_LISTINGS/README.md):
	##   godot --path . --resolution 886x1920 --fixed-fps 30 --write-movie build/preview/en/iphone/f.png -- --tour=build/preview/en --preview --locale=en --save-dir=user://preview
	## Home -> Play Together (a few shared turns with Team-ups) -> Board Studio (shapes, Check &
	## Play, the code) -> a friend's code -> Home. About 26 s after the trim.
	await _wait(1.0)
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("denied")
	GameState.data.tutorial_done = true
	for id in range(1, 41):
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0, "score": 300, "stars": 3})
	var he := LocalizationService.current == "he"
	FreePlayService.set_player_name(0, "מאיה" if he else "Maya")
	FreePlayService.set_player_name(1, "נועם" if he else "Noam")
	FreePlayService.set_player_color(0, 0)
	FreePlayService.set_player_color(1, 1)
	GameState.data.duet.first = 0
	await _ensure_home()
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
	RenderingServer.frame_post_draw.connect(_save_frame)
	_recording = true
	print("TOUR preview start")
	await _wait(1.6)
	await _go("duet")
	await _wait(1.2)
	await _go("freeplay", {"kind": "duet", "code": StudioBoard.SAMPLE_CODE, "difficulty": "medium", "restart": true})
	await _wait(1.5)
	var scr: Node = Router.current_screen()
	var sol: Dictionary = TraySolver.new(400000, 8000, scr.session.capacity).solve(scr.session.state.clone(), scr.session.tray.duplicate())
	var picks: PackedInt32Array = sol.solution if sol.result == BoardSolver.Result.SOLVED else TraySolver.flatten(scr.level.solution)
	for k in 10:
		scr.board.input_enabled = true
		scr.controller._on_tap(picks[k])
		await _wait(0.7)
	await _wait(0.6)
	var studio := load("res://scripts/screens/StudioScreen.gd")
	studio._params = {"family": "pyramid", "cols": 6, "layers": 3, "mode": "top", "tiles": 72, "seed": 2026}
	await _go("studio", {"tab": "create"})
	await _wait(1.0)
	for fam in ["turtle", "bridge", "ziggurat"]:
		Router.current_screen()._change("family", fam)
		await _wait(0.8)
	Router.current_screen()._check_and_play()
	await _wait_for_modal(8.0)
	await _wait(1.6)
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("close")
	await _wait(0.4)
	await _go("studio", {"tab": "code"})
	await _wait(0.5)
	var sc: Node = Router.current_screen()
	for n in range(1, StudioBoard.SAMPLE_CODE.length() + 1):
		sc._code_text = StudioBoard.SAMPLE_CODE.left(n)
		sc._code_field.text = sc._code_text
		await _wait(0.07)
	await _wait(0.4)
	sc._play_code()
	await _wait_for_modal(3.0)
	await _wait(1.3)
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("close")
	await _go("home")
	await _wait(1.0)
	_recording = false
	print("TOUR preview end: %d frames" % _frame_n)


func _save_frame() -> void:
	## One video frame at the viewport's full size (Movie Maker records the window, which the OS
	## keeps smaller than the 886x1920 an App Preview needs).
	if not _recording:
		return
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_dir.path_join("frames/%05d.png" % _frame_n))
	_frame_n += 1


func _ensure_home() -> void:
	## Home for sure (a go() while the boot/tutorial transition runs is ignored by Router).
	for i in 20:
		if Router.current_name == "home":
			break
		Router.reset_to("home")
		await _wait(0.5)
	await _wait(0.6)


const IAP_REVIEW_PRICES := {"coins_s": "$1.99", "coins_m": "$4.99", "coins_l": "$9.99", "remove_ads": "$3.99", "theme_bundle": "$2.99", "starter_bundle": "$4.99"}


func _iap_review_shots() -> void:
	## The in-app purchase review screenshots for App Store Connect: the real shop with every
	## product, at the App Store prices (US), from the QA store (debug only; its label hidden).
	await _wait(1.0)
	for m in get_tree().root.find_children("*", "ModalDialog", true, false):
		m.close("denied")
	GameState.data.tutorial_done = true
	for id in range(1, 21):
		ProgressionService.complete_level(id, {"moves": 10, "hints": 0, "score": 300, "stars": 3})
	FeatureFlags.set_override("qa_mock_services", true)
	FeatureFlags.set_override("shop_enabled", true)
	IAPService.provider = null
	IAPService.initialize()
	await _wait(0.5)
	for pid in IAP_REVIEW_PRICES:
		var d: Dictionary = IAPService._details.get(pid, {})
		d["price"] = IAP_REVIEW_PRICES[pid]
		IAPService._details[pid] = d
	await _ensure_home()
	await _go("shop")
	await _wait(0.6)
	var scr: Node = Router.current_screen()
	for l in scr.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("QA MOCK"):
			l.visible = false
	var scrolls := scr.find_children("*", "ScrollContainer", true, false)
	for k in 3:
		await _shot("iap_review_%d" % (k + 1))
		for sc in scrolls:
			(sc as ScrollContainer).scroll_vertical += 700
		await _wait(0.4)
	print("TOUR iap review done")
