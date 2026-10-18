extends Screen
## Settings. Every row does something real or is visibly disabled with the reason shown.
## Language changes apply instantly (screens rebuild) without a restart.

var _list: VBoxContainer


func build_background() -> void:
	var c := ColorRect.new()
	c.color = UITheme.IVORY
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)


func build() -> void:
	var root := UIKit.vbox(10)
	safe.add_child(root)
	root.add_child(UIKit.header(t("settings"), func() -> void: Router.back()))
	_list = UIKit.vbox(10)
	root.add_child(UIKit.scroll(_list))

	_section(t("section_general"))
	_language_row()

	_section(t("section_sound"))
	_toggle_row(t("music"), "music_on")
	_slider_row(t("music_volume"), "music_volume")
	_toggle_row(t("sound_effects"), "sfx_on")
	_slider_row(t("sfx_volume"), "sfx_volume")
	_toggle_row(t("vibration"), "haptics", t("vibration_note") if not OS.has_feature("mobile") else "")

	_section(t("section_display"))
	_graphics_row()
	_toggle_row(t("reduce_motion"), "reduced_motion", t("reduce_motion_note"))
	_toggle_row(t("high_contrast"), "high_contrast")
	_toggle_row(t("large_tiles"), "large_tiles", t("large_tiles_note"))
	_toggle_row(t("highlight_free"), "highlight_free", t("highlight_free_note"))
	_toggle_row(t("soften_background"), "soften_background")
	if FeatureFlags.enabled("show_session_timer_option"):
		_toggle_row(t("show_timer"), "show_timer", t("show_timer_note"))

	_section(t("section_privacy"))
	_link_row(t("privacy_policy"), "privacy_policy")
	_link_row(t("terms_of_service"), "terms")
	_link_row(t("support"), "support")
	_analytics_row()

	_section(t("section_purchases"))
	var restore := UIKit.button(t("restore_purchases"), "cream", "small", func() -> void:
		Router.toast(t("restore_started") if IAPService.restore() else t("restore_unavailable")))
	restore.disabled = IAPService.provider == null
	_list.add_child(restore)
	if restore.disabled:
		_note(t("restore_unavailable"))

	_section(t("section_data"))
	_list.add_child(UIKit.button(t("replay_tutorial"), "cream", "small", func() -> void: Router.go("tutorial", {"replay": true})))
	_list.add_child(UIKit.button(t("reset_progress"), "rose", "small", _confirm_reset))
	_note(t("reset_progress_note"))

	_section(t("section_about"))
	_note("%s %s · %s" % [t("app_name"), ProjectSettings.get_setting("application/config/version", "dev"), FeatureFlags.get_str("content_version")])
	_list.add_child(UIKit.button(t("licenses"), "cream", "small", _show_licenses))
	_list.add_child(UIKit.spacer(24))


func _section(title: String) -> void:
	var l := UIKit.label(title, UITheme.FONT_BODY + 1, true, UITheme.VIOLET.darkened(0.15))
	_list.add_child(UIKit.spacer(4))
	_list.add_child(l)


func _note(text: String) -> void:
	_list.add_child(UIKit.label(text, UITheme.FONT_SMALL, false, UITheme.text_soft()))


func _row(label_text: String, control: Control, note: String = "") -> void:
	var p := UIKit.panel("CardFlat")
	var v := UIKit.vbox(2)
	p.add_child(v)
	var h := UIKit.hbox(10)
	h.custom_minimum_size.y = 52
	var l := UIKit.label(label_text, UITheme.FONT_BODY, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	h.add_child(control)
	v.add_child(h)
	if note != "":
		v.add_child(UIKit.label(note, UITheme.FONT_SMALL, false, UITheme.text_soft()))
	_list.add_child(p)


func _toggle_row(label_text: String, key: String, note: String = "") -> void:
	var cb := CheckButton.new()
	cb.button_pressed = bool(GameState.setting(key))
	cb.custom_minimum_size = Vector2(80, 52)
	cb.focus_mode = Control.FOCUS_ALL
	AccessibilityService.set_access_name(cb, label_text)
	cb.toggled.connect(func(on: bool) -> void:
		AudioService.play("tap")
		GameState.set_setting(key, on))
	_row(label_text, cb, note)


func _slider_row(label_text: String, key: String) -> void:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(GameState.setting(key))
	s.custom_minimum_size = Vector2(200, 48)
	s.focus_mode = Control.FOCUS_ALL
	AccessibilityService.set_access_name(s, label_text)
	s.value_changed.connect(func(v: float) -> void: GameState.set_setting(key, v))
	s.drag_ended.connect(func(_changed: bool) -> void: AudioService.play("tap"))
	_row(label_text, s)


func _language_row() -> void:
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(220, 52)
	ob.focus_mode = Control.FOCUS_ALL
	ob.add_item(t("language_auto"))
	ob.set_item_metadata(0, "auto")
	var cur := str(GameState.setting("locale"))
	var sel := 0
	for code in LocalizationService.ORDER:
		ob.add_item(LocalizationService.native_name(code))
		ob.set_item_metadata(ob.item_count - 1, code)
		if code == cur:
			sel = ob.item_count - 1
	ob.select(sel)
	AccessibilityService.set_access_name(ob, t("language"))
	ob.item_selected.connect(func(idx: int) -> void:
		var code := str(ob.get_item_metadata(idx))
		GameState.set_setting("locale", code)
		GameState.save_now()
		LocalizationService.apply_setting(code))
	_row(t("language"), ob)


func _graphics_row() -> void:
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(200, 52)
	ob.focus_mode = Control.FOCUS_ALL
	var modes := ["auto", "low", "standard"]
	var names := [t("graphics_auto"), t("low"), t("graphics_standard")]
	for k in modes.size():
		ob.add_item(names[k])
	ob.select(maxi(0, modes.find(str(GameState.setting("graphics")))))
	ob.item_selected.connect(func(idx: int) -> void: GameState.set_setting("graphics", modes[idx]))
	var note := t("graphics_note")
	if str(GameState.setting("graphics")) == "auto":
		note += " " + (t("graphics_auto_low") if AccessibilityService.low_profile else t("graphics_auto_standard"))
	_row(t("graphics_quality"), ob, note)


func _link_row(label_text: String, kind: String) -> void:
	var available := PrivacyService.url(kind) != ""
	var b := UIKit.button(t("open") if available else t("not_configured"), "cream", "small", func() -> void: PrivacyService.open(kind))
	b.disabled = not available
	b.custom_minimum_size.x = 150
	_row(label_text, b, "" if available else t("link_not_configured_note"))


func _analytics_row() -> void:
	var cb := CheckButton.new()
	var available := FeatureFlags.enabled("analytics_enabled")
	cb.button_pressed = available and PrivacyService.analytics_allowed()
	cb.disabled = not available
	cb.custom_minimum_size = Vector2(80, 52)
	cb.toggled.connect(func(on: bool) -> void: PrivacyService.set_analytics_consent(on))
	_row(t("analytics_optional"), cb, t("analytics_note_on") if available else t("analytics_note_off"))


func _confirm_reset() -> void:
	var m := ModalDialog.open(self, t("reset_confirm_title"), t("reset_confirm_body"))
	m.add_action(t("reset_progress"), "reset", "rose")
	m.add_action(t("cancel"), "cancel", "cream", "small")
	m.closed.connect(func(r: String) -> void:
		if r == "reset":
			GameState.reset_local_data()
			Router.toast(t("reset_done"))
			Router.reset_to("home"))


func _show_licenses() -> void:
	var m := ModalDialog.open(self, t("licenses"), t("licenses_body"))
	m.add_action(t("ok"), "ok", "green")
