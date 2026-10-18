extends Screen
## LiShi Bloom: a mostly static illustrated world that fills with discoveries as Lights are
## earned. Decorations are separate sprites placed from data/config/bloom.json; tapping one
## plays a tiny bounce and shows its short story line. New discoveries get a brief,
## skippable sparkle the first time they are seen. No timers, no currency, no pressure.

var _world_id: String = "aurora_garden"
var _stage: Control
var _caption: Label


func _ready() -> void:
	_world_id = str(Router.params.get("world", ""))
	if _world_id == "":
		# Default to the world of the most recent discovery, else the current journey world.
		var n := ProgressionService.discoveries_unlocked_count()
		var all := ContentService.all_discoveries()
		_world_id = str(all[n - 1].world) if n > 0 else str(ContentService.world_for_level(GameState.next_level(ContentService.level_count())).get("id", "aurora_garden"))
	super._ready()
	AudioService.play_world_music(_world_id)


func build_background() -> void:
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.layout_direction = Control.LAYOUT_DIRECTION_LTR  # artwork never mirrors
	add_child(_stage)
	UIKit.fullscreen_bg(_stage, ContentService.world_bg(_world_id, "world", AccessibilityService.low_profile))
	_stage.resized.connect(_place_decorations)
	_place_decorations.call_deferred()


func build() -> void:
	var root := UIKit.vbox(8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)
	root.add_child(UIKit.header(t("veya_bloom"), func() -> void: Router.back(), true))
	var tabs := UIKit.hbox(6)
	for w in ContentService.worlds:
		var wid := str(w.id)
		var b := UIKit.tab_button(t(ContentService.world_name_key(wid)), wid == _world_id, func() -> void:
			_world_id = wid
			AudioService.play_world_music(wid)
			_rebuild())
		tabs.add_child(b)
	root.add_child(tabs)
	var info := UIKit.panel("CardFlat")
	var iv := UIKit.vbox(4)
	info.add_child(iv)
	iv.add_child(UIKit.label(t("bloom_subtitle"), UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	var found := 0
	var total := 0
	for d in ContentService.all_discoveries():
		if d.world == _world_id:
			total += 1
			if ProgressionService.is_discovery_unlocked(d.index):
				found += 1
	iv.add_child(UIKit.label(t("discoveries_found", {"found": found, "total": total}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	var np := ProgressionService.lights_progress()
	if np.x >= 0:
		iv.add_child(UIKit.progress_bar(np.x, np.y, 12))
		iv.add_child(UIKit.label(t("lights_to_next", {"count": np.y - np.x, "have": np.x, "need": np.y}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		iv.add_child(UIKit.label(t("all_discoveries_found"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(info)
	root.add_child(UIKit.spacer(0, true))
	var cap_panel := UIKit.panel("HudPill")
	_caption = UIKit.label(t("bloom_tap_hint"), UITheme.FONT_BODY, false, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	cap_panel.add_child(_caption)
	root.add_child(cap_panel)
	root.add_child(UIKit.bottom_nav(""))


func _place_decorations() -> void:
	if _stage == null or _stage.size.x <= 0:
		return
	for c in _stage.get_children():
		if c.has_meta("deco"):
			c.queue_free()
	# Map the 1080x1920 art (drawn "covered") to the stage rect.
	var art := Vector2(1080, 1920)
	var s := maxf(_stage.size.x / art.x, _stage.size.y / art.y)
	var off := (_stage.size - art * s) * 0.5
	var hi := not AccessibilityService.low_profile
	for d in ContentService.all_discoveries():
		if d.world != _world_id:
			continue
		var unlocked := ProgressionService.is_discovery_unlocked(d.index)
		var px := float(d.size) * art.x * s
		var anchor := off + Vector2(float(d.pos[0]), float(d.pos[1])) * art * s
		var b := Button.new()
		_stage.add_child(b)  # attach before positioning (RTL would mirror the offset)
		b.set_meta("deco", true)
		b.theme_type_variation = "FlatTool"
		b.focus_mode = Control.FOCUS_ALL
		b.size = Vector2(px, px)
		b.position = anchor - Vector2(px * 0.5, px)
		b.pivot_offset = Vector2(px * 0.5, px)
		var img := UIKit.texrect(ContentService.tex("decorations/%s_%d.png" % [d.sprite, 512 if hi else 256]))
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(img)
		if not unlocked:
			# Locked: a faint silhouette marker so players see where something will bloom.
			img.modulate = Color(0.1, 0.15, 0.25, 0.22)
		AccessibilityService.set_access_name(b, t("disc_" + str(d.sprite)) if unlocked else t("locked"))
		var idx: int = d.index
		var did: String = d.id
		var sprite: String = d.sprite
		b.pressed.connect(func() -> void: _on_deco(b, idx, did, sprite))
		if unlocked and not GameState.data.bloom.seen.has(did):
			_reveal(b, did)


func _reveal(b: Control, did: String) -> void:
	ProgressionService.mark_discovery_seen(did)
	AudioService.play("soft_pop")
	if AccessibilityService.reduced_motion():
		return
	b.scale = Vector2(0.6, 0.6)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(1.08, 1.08), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE, 0.15)
	if AccessibilityService.effects_on():
		var frames := ContentService.effect_frames("gold_twinkle")
		if not frames.is_empty():
			var fx := UIKit.texrect(frames[0])
			_stage.add_child(fx)
			fx.size = b.size
			fx.position = b.position
			var ft := fx.create_tween()
			ft.tween_method(func(f: float) -> void: fx.texture = frames[clampi(int(f), 0, frames.size() - 1)], 0.0, float(frames.size()), 0.6)
			ft.tween_callback(fx.queue_free)


func _on_deco(b: Control, idx: int, _did: String, sprite: String) -> void:
	if ProgressionService.is_discovery_unlocked(idx):
		AudioService.play("soft_pop")
		_caption.text = t("story_" + sprite)
		if not AccessibilityService.reduced_motion():
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(1.1, 0.92), 0.08)
			tw.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		AudioService.play("tap")
		var per := ContentService.lights_per_discovery()
		_caption.text = t("deco_locked_hint", {"count": (idx + 1) * per})
