extends Screen
## Interactive first-run tutorial: four tiny real boards played with the real rules engine.
## Each step teaches one rule of tray play; the tiles to pick are gently highlighted. A full
## tray here never ends anything: the tiles simply go back. Skippable any time.

const STEPS := [
	{"key": "tut_step_tray", "rows": ["XX", "XX"], "layers": [],
		"faces": ["bamboo_3", "character_5", "character_5", "bamboo_3"], "hint": [1, 2]},
	{"key": "tut_step_stack", "rows": ["XXXX"], "layers": [[".XX."]],
		"faces": ["bamboo_9", "dragon_green", "dragon_green", "bamboo_9", "circle_7", "circle_7"], "hint": [4, 5]},
	{"key": "tut_step_full", "rows": ["XXX", "XXX"], "layers": [],
		"faces": ["wind_east", "circle_2", "dragon_red", "dragon_red", "circle_2", "wind_east"], "hint": [0, 5]},
	{"key": "tut_step_bonus", "rows": ["XX", "XX"], "layers": [],
		"faces": ["flower_plum", "flower_chrysanthemum", "flower_chrysanthemum", "flower_plum"], "hint": [0, 3]},
]

var _step: int = 0
var _session: GameSession
var _controller: BoardController
var _board: BoardView
var _tray: TrayView
var _instr: Label
var _done: bool = false


func _ready() -> void:
	AnalyticsService.track("tutorial_started")
	_load_step()
	AdsService.set_banner_suppressed(true)  # no banner while playing, as in gameplay
	tree_exiting.connect(AdsService.set_banner_suppressed.bind(false), CONNECT_ONE_SHOT)
	super._ready()
	AudioService.play_world_music("aurora_garden")


func _load_step() -> void:
	var s: Dictionary = STEPS[_step]
	var tiles: Array = []
	var all_layers: Array = [s.rows]
	all_layers.append_array(s.layers)
	for z in all_layers.size():
		for y in all_layers[z].size():
			var line: String = all_layers[z][y]
			for x in line.length():
				if line[x] == "X":
					tiles.append({"x": x, "y": y, "z": z, "face": s.faces[tiles.size()]})
	var L := LevelDefinition.from_dict({"id": 0, "world": "aurora_garden", "tiles": tiles}, "tutorial:%d" % _step)
	_session = GameSession.start(L)
	_controller = BoardController.new(_session, "tutorial", false)
	_controller.won.connect(_on_step_done)
	_controller.blocked_tapped.connect(func(_i: int) -> void: Router.toast(t("tile_blocked_help"), 3.0))
	_controller.tray_failed.connect(func() -> void:
		Router.toast(t("tut_tray_full"), 3.0)
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if is_inside_tree() and _session.failed:
				_controller.send_back(TrayRules.CAPACITY)))


func build_background() -> void:
	UIKit.fullscreen_bg(self, ContentService.world_bg("aurora_garden", "gameplay", AccessibilityService.low_profile), 0.08)


func build() -> void:
	var root := UIKit.vbox(12)
	safe.add_child(root)
	var top := UIKit.hbox(10)
	var step_l := UIKit.label(t("tut_progress", {"step": _step + 1, "total": STEPS.size()}) if not _done else "", UITheme.FONT_BODY, true, Color.WHITE)
	step_l.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.7))
	step_l.add_theme_constant_override("outline_size", 5)
	step_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(step_l)
	top.add_child(UIKit.button(t("skip"), "cream", "small", _finish.bind(true)))
	root.add_child(top)
	var card := UIKit.panel("Card")
	var cv := UIKit.vbox(6)
	card.add_child(cv)
	cv.add_child(UIKit.label(t("tut_title"), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	_instr = UIKit.label(t("tut_ready") if _done else t(STEPS[_step].key), UITheme.FONT_BODY + 1, false, null, HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(_instr)
	root.add_child(card)
	if _done:
		root.add_child(UIKit.spacer(0, true))
		var go := UIKit.button(t("start_playing"), "green", "large", _finish.bind(false))
		root.add_child(go)
		UIKit.focus_initial.call_deferred(go)
		root.add_child(UIKit.spacer(40))
		return
	_tray = TrayView.new()
	_tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_tray)
	_board = BoardView.new()
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_board)
	_board.setup(_session.state, ProgressionService.equipped_theme())
	_controller.attach_view(_board, _tray)
	var h := PackedInt32Array(STEPS[_step].hint)
	(func() -> void:
		if is_instance_valid(_board) and not _session.state.is_removed(h[0]):
			_board.show_hint(h)).call_deferred()
	root.add_child(UIKit.spacer(60))


func _on_step_done() -> void:
	AudioService.play("reward")
	var delay := 0.1 if AccessibilityService.reduced_motion() else 0.5
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		_step += 1
		if _step >= STEPS.size():
			_done = true
		else:
			_load_step()
		_rebuild())


func _finish(skipped: bool) -> void:
	var replay := bool(Router.params.get("replay", false))
	GameState.data.tutorial_done = true
	GameState.save_now()
	AnalyticsService.track("tutorial_completed", {"skipped": skipped})
	if replay:
		Router.back()
	else:
		Router.reset_to("home")


func on_back() -> bool:
	_finish(true)
	return true
