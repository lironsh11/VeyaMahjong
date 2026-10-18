extends Screen
## Home: active world art, prominent Play/Continue, next Bloom discovery and today's puzzle.

var _world: Dictionary


func _ready() -> void:
	var next := GameState.next_level(ContentService.level_count())
	var active := GameState.active_session()
	if not active.is_empty() and str(active.get("mode")) == "level":
		next = int(active.get("level_id", next))
	_world = ContentService.world_for_level(next)
	set_meta("next_level", next)
	super._ready()
	AudioService.play_world_music(str(_world.get("id", "aurora_garden")))
	ContentService.active_world = str(_world.get("id", "aurora_garden"))


func build_background() -> void:
	UIKit.fullscreen_bg(self, ContentService.world_bg(str(_world.get("id", "aurora_garden")), "world", AccessibilityService.low_profile), 0.0)


func build() -> void:
	var next: int = get_meta("next_level")
	var active := GameState.active_session()
	var root := UIKit.vbox(10)
	safe.add_child(root)
	# Top row: Bloom shortcut and Settings
	var top := UIKit.hbox(10)
	var bloom_btn := UIKit.icon_button("flower", t("veya_bloom"), func() -> void: Router.go("bloom"), 60)
	top.add_child(bloom_btn)
	top.add_child(UIKit.spacer(0, true))
	top.add_child(UIKit.icon_button("settings", t("settings"), func() -> void: Router.go("settings"), 60))
	root.add_child(top)
	var logo := UIKit.texrect(ContentService.tex("branding/veya_logo_stacked_dark.png"), Vector2(300, 170))
	root.add_child(logo)
	root.add_child(UIKit.spacer(0, true))
	# Continue card
	var card := UIKit.panel("Card")
	var cv := UIKit.vbox(4)
	card.add_child(cv)
	cv.add_child(UIKit.label(t(ContentService.world_name_key(str(_world.get("id", "")))), UITheme.FONT_H2 + 2, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	var resuming := not active.is_empty()
	var line := ""
	if resuming and str(active.get("mode")) == "daily":
		line = t("continue_daily")
	elif resuming:
		line = t("continue_level_n", {"level": next})
	elif GameState.is_level_completed(ContentService.level_count()):
		line = t("all_levels_done")
	else:
		line = t("level_n", {"level": next})
	cv.add_child(UIKit.label(line, UITheme.FONT_BODY + 1, false, UITheme.TEAL.darkened(0.35), HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(card)
	var play := UIKit.button(t("continue") if resuming else t("play"), "green", "large", func() -> void:
		if resuming:
			Router.go("gameplay", {"resume": true})
		else:
			Router.go("gameplay", {"mode": "level", "level": next}))
	play.custom_minimum_size.y = 84
	play.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	root.add_child(play)
	UIKit.focus_initial.call_deferred(play)
	# Bloom progress + Daily, side by side
	var row := UIKit.hbox(10)
	row.add_child(_bloom_card())
	row.add_child(_daily_card())
	root.add_child(row)
	root.add_child(UIKit.bottom_nav("home"))


func _bloom_card() -> Control:
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 104)
	var p := UIKit.panel("CardFlat")
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(UIKit.label(t("next_discovery"), UITheme.FONT_SMALL, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	var np := ProgressionService.lights_progress()
	if np.x < 0:
		v.add_child(UIKit.label(t("all_discoveries_found"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		v.add_child(UIKit.progress_bar(np.x, np.y, 14))
		v.add_child(UIKit.label(t("lights_progress", {"have": np.x, "need": np.y}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	b.add_child(p)
	var unseen := ProgressionService.unseen_discoveries()
	if unseen > 0:
		var c := UIKit.chip(t("new_badge"), UITheme.ROSE.darkened(0.2))
		# Badge floats on the card's top-end corner; Godot mirrors the anchor in RTL.
		b.add_child(c)
		c.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
		c.position.y = -16
		c.z_index = 1
	AccessibilityService.set_access_name(b, t("veya_bloom"))
	b.pressed.connect(func() -> void:
		AudioService.play("button")
		Router.go("bloom"))
	return b


func _daily_card() -> Control:
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 104)
	var p := UIKit.panel("CardFlat")
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(UIKit.label(t("daily_puzzle"), UITheme.FONT_SMALL, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	var done := DailyService.is_completed(DailyService.today())
	var h := UIKit.hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UIKit.texrect(ContentService.icon("calendar_check" if done else "daily"), Vector2(30, 30)))
	h.add_child(UIKit.label(t("daily_done_today") if done else t("daily_ready_today"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER, false))
	v.add_child(h)
	b.add_child(p)
	AccessibilityService.set_access_name(b, t("daily_puzzle"))
	b.pressed.connect(func() -> void:
		AudioService.play("button")
		Router.go("daily"))
	return b
