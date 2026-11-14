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
	if EconomyService.welcome_notice_pending():
		_show_welcome.call_deferred()
	elif bool(GameState.data.progress.get("new_levels_notice", false)):
		_show_new_levels.call_deferred()


func _show_new_levels() -> void:
	## One-time note for players from 1.0: every world grew to 100 levels and the numbers moved.
	var m := ModalDialog.open(self, t("new_levels_title"), t("new_levels_body"))
	m.add_action(t("ok"), "ok", "green")
	m.closed.connect(func(_r: String) -> void:
		GameState.data.progress.new_levels_notice = false
		GameState.save_now())


func _show_welcome() -> void:
	## One-time explanation for players from before the booster economy, with their gift.
	var g := EconomyService.welcome_contents()
	var m := ModalDialog.open(self, t("welcome_title"), t("welcome_body", {"coins": int(g.get("coins", 0)),
		"hint": int(g.get("hint", 0)), "shuffle": int(g.get("shuffle", 0)), "undo": int(g.get("undo", 0))}))
	m.add_action(t("ok"), "ok", "green")
	m.closed.connect(func(_r: String) -> void: EconomyService.clear_welcome_notice())
	AudioService.play("reward")


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
	top.add_child(UIKit.coin_pill(func() -> void: Router.go("shop", {"from": "home"})))
	if ProgressionService.streak_count() > 0:
		top.add_child(UIKit.streak_pill(ProgressionService.streak_count()))
	top.add_child(UIKit.spacer(0, true))
	top.add_child(UIKit.icon_button("settings", t("settings"), func() -> void: Router.go("settings"), 60))
	root.add_child(top)
	var logo := UIKit.texrect(ContentService.art("branding/logo_ornate_large.png"), Vector2(270, 130))
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
	if ProgressionService.streak_count() > 0:
		var sr := UIKit.hbox(6)
		sr.alignment = BoxContainer.ALIGNMENT_CENTER
		sr.add_child(StreakFlame.make(24.0))
		var key := "streak_home_bonus" if ProgressionService.streak_bonus_active() else "streak_home"
		sr.add_child(UIKit.label(t(key, {"count": ProgressionService.streak_count()}), UITheme.FONT_SMALL, true, Color("D9731C"), HORIZONTAL_ALIGNMENT_CENTER, false))
		cv.add_child(sr)
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
	# The two ways to play beyond the journey: Play Together and Board Studio.
	var sig := UIKit.hbox(10)
	var duet_sub := t("duet_in_progress") if not GameState.session(FreePlayService.SLOT_DUET).is_empty() else t("play_together_sub")
	sig.add_child(_feature_card("duet", t("play_together"), duet_sub, _together_art(), func() -> void: Router.go("duet")))
	sig.add_child(_feature_card("studio", t("board_studio"), t("board_studio_sub"), _studio_art(), func() -> void: Router.go("studio")))
	root.add_child(sig)
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
		var c := UIKit.chip(t("new_badge"), "BadgeRed")
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


func _feature_card(feature: String, title: String, sub: String, art: Control, on_press: Callable) -> Control:
	## A large card for Play Together / Board Studio, with a "new" chip until first opened.
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 118)
	var p := UIKit.panel("Card")
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var tl := UIKit.label(title, UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER, false)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fit_label(tl, 200.0, UITheme.FONT_BODY, UITheme.FONT_SMALL - 2)
	v.add_child(tl)
	var sl := UIKit.label(sub, UITheme.FONT_SMALL - 2, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER, false)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fit_label(sl, 200.0, UITheme.FONT_SMALL - 2, 12)
	v.add_child(sl)
	p.add_child(v)
	b.add_child(p)
	if not FreePlayService.seen(feature):
		var c := UIKit.chip(t("new_badge"), "BadgeRed")
		b.add_child(c)
		c.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
		c.position.y = -16
		c.z_index = 1
	AccessibilityService.set_access_name(b, "%s. %s" % [title, sub])
	b.pressed.connect(func() -> void:
		AudioService.play("button")
		on_press.call())
	return b


func _tile(parent: Control, face: String, at: Vector2, w: float) -> TextureRect:
	## Attached before it is positioned: a position set first is mirrored in right-to-left.
	var r := UIKit.texrect(ContentService.tile_texture(ProgressionService.equipped_theme(), face, false), Vector2(w, w * BoardFit.ASPECT))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	r.position = at
	r.size = Vector2(w, w * BoardFit.ASPECT)
	return r


func _art_box() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(110, 52)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.layout_direction = Control.LAYOUT_DIRECTION_LTR
	return c


func _together_art() -> Control:
	## A matching pair, one tile from each player (their numbered tokens on top).
	var c := _art_box()
	for k in 2:
		var x := 18.0 + k * 40.0
		_tile(c, "circle_5", Vector2(x, 0), 34.0)
		var tok := TurnBar.token(k + 1, FreePlayService.player_color(k), 20)
		c.add_child(tok)
		tok.position = Vector2(x + 22.0, 30.0)
	return c


func _studio_art() -> Control:
	## A small layered stack: two tiles below, one resting on both.
	var c := _art_box()
	_tile(c, "bamboo_2", Vector2(22, 10), 32.0)
	_tile(c, "character_7", Vector2(54, 10), 32.0)
	_tile(c, "dragon_red", Vector2(38, -2), 32.0)
	return c
