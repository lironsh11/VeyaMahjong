extends Screen
## Daily Puzzle: today's deterministic board, a month calendar of the playable archive
## (last 30 days; missed days stay playable, no streaks), optional daily tasks with a single
## once-per-day Light, and a privacy-safe share card (date + solved, nothing personal).

var _selected: String = ""
var _month: Vector2i = Vector2i.ZERO   # (year, month)
var _play_btn: Button
var _status: Label


func _ready() -> void:
	_selected = str(Router.params.get("date", DailyService.today()))
	var parts := _selected.split("-")
	_month = Vector2i(int(parts[0]), int(parts[1]))
	super._ready()
	DailyService.tasks_changed.connect(_on_relayout)


func build_background() -> void:
	UIKit.fullscreen_bg(self, ContentService.screen_bg("daily", AccessibilityService.low_profile), 0.05, Color.WHITE)


func build() -> void:
	var root := UIKit.vbox(10)
	safe.add_child(root)
	root.add_child(UIKit.header(t("daily_puzzle"), func() -> void: Router.back(), true))
	var content := UIKit.vbox(12)
	root.add_child(UIKit.scroll(content))
	content.add_child(_today_card())
	content.add_child(_calendar())
	if FeatureFlags.enabled("daily_tasks_enabled"):
		content.add_child(_tasks_card())
	content.add_child(UIKit.label(t("daily_archive_note", {"count": DailyService.ARCHIVE_DAYS}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(UIKit.bottom_nav("daily"))


func _today_card() -> Control:
	var p := UIKit.panel("Card")
	var v := UIKit.vbox(8)
	p.add_child(v)
	var is_today := _selected == DailyService.today()
	v.add_child(UIKit.label(t("daily_today") if is_today else t("daily_from_archive"), UITheme.FONT_SMALL, true, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label(LocalizationService.format_date(_selected), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	var done := DailyService.is_completed(_selected)
	_status = UIKit.label(t("daily_solved_status") if done else t("daily_unsolved_status"), UITheme.FONT_BODY, false, UITheme.GREEN.darkened(0.2) if done else UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_status)
	var active := GameState.active_session()
	var resuming := str(active.get("key", "")) == "daily:" + _selected
	var label := t("continue") if resuming else (t("play_again") if done else t("play"))
	_play_btn = UIKit.button(label, "green", "large", _play)
	v.add_child(_play_btn)
	if done:
		v.add_child(UIKit.button(t("share"), "cream", "small", _share))
	return p


func _play() -> void:
	if not DailyService.is_playable(_selected):
		Router.toast(t("daily_not_available"))
		return
	_play_btn.disabled = true
	_status.text = t("daily_preparing")
	var date := _selected
	DailyService.request_board(date, func(L: Variant) -> void:
		if not is_inside_tree():
			return
		if L == null:
			_play_btn.disabled = false
			_status.text = t("error_generic")
			AnalyticsService.track("error_nonfatal", {"code": "daily_gen"})
			return
		Router.go("gameplay", {"mode": "daily", "date": date}))


func _share() -> void:
	# Native share sheets need a platform plugin; copying a text card works everywhere.
	var text := t("share_text", {"date": LocalizationService.format_date(_selected), "app": t("app_name")})
	DisplayServer.clipboard_set(text)
	Router.toast(t("share_copied"))


func _calendar() -> Control:
	var p := UIKit.panel("CardFlat")
	var v := UIKit.vbox(8)
	p.add_child(v)
	var nav := UIKit.hbox(8)
	var today := DailyService.today()
	var earliest := DailyService.add_days(today, -DailyService.ARCHIVE_DAYS)
	var e_parts := earliest.split("-")
	var t_parts := today.split("-")
	var can_prev := _month > Vector2i(int(e_parts[0]), int(e_parts[1]))
	var can_next := _month < Vector2i(int(t_parts[0]), int(t_parts[1]))
	var prev := UIKit.icon_button("back", t("a11y_prev_month"), func() -> void: _shift_month(-1), 52, true)
	prev.disabled = not can_prev
	prev.modulate.a = 1.0 if can_prev else 0.35
	nav.add_child(prev)
	var title := UIKit.label(LocalizationService.month_title(_month.x, _month.y), UITheme.FONT_BODY + 2, true, null, HORIZONTAL_ALIGNMENT_CENTER, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(title)
	var nxt := UIKit.icon_button("next", t("a11y_next_month"), func() -> void: _shift_month(1), 52, true)
	nxt.disabled = not can_next
	nxt.modulate.a = 1.0 if can_next else 0.35
	nav.add_child(nxt)
	v.add_child(nav)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var ws := LocalizationService.week_start()
	for k in 7:
		var l := UIKit.label(LocalizationService.weekday_short((ws + k) % 7), UITheme.FONT_SMALL, true, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER, false)
		l.custom_minimum_size = Vector2(62, 26)
		grid.add_child(l)
	var first := "%04d-%02d-01" % [_month.x, _month.y]
	var first_wd := int(Time.get_datetime_dict_from_datetime_string(first + "T12:00:00", true).weekday)
	var lead := (first_wd - ws + 7) % 7
	for k in lead:
		grid.add_child(UIKit.spacer(0))
	for day in range(1, DailyGenerator.days_in_month(_month.x, _month.y) + 1):
		grid.add_child(_day_cell("%04d-%02d-%02d" % [_month.x, _month.y, day], day, today))
	var cc := CenterContainer.new()
	cc.add_child(grid)
	v.add_child(cc)
	return p


func _day_cell(date: String, day: int, today: String) -> Control:
	var playable := DailyService.is_playable(date)
	var done := DailyService.is_completed(date)
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.custom_minimum_size = Vector2(62, 58)
	b.focus_mode = Control.FOCUS_ALL if playable else Control.FOCUS_NONE
	var bgc := Color(UITheme.GREEN, 0.85) if done else (Color(UITheme.IVORY, 0.95) if playable else Color(1, 1, 1, 0.25))
	var border := UITheme.GOLD if date == _selected else (UITheme.VIOLET if date == today else Color.TRANSPARENT)
	var sb := UITheme.flat(bgc, 14, border, 3 if border != Color.TRANSPARENT else 0, 0)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("disabled", sb)
	b.text = LocalizationService.format_number(day)
	b.add_theme_color_override("font_color", Color.WHITE if done else UITheme.text_color())
	b.add_theme_color_override("font_disabled_color", Color(UITheme.text_color(), 0.35))
	b.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	b.disabled = not playable
	var state := t("daily_state_done") if done else (t("daily_state_open") if playable else t("daily_state_unavailable"))
	AccessibilityService.set_access_name(b, LocalizationService.format_date(date) + ", " + state)
	b.pressed.connect(func() -> void:
		AudioService.play("tap")
		_selected = date
		_rebuild())
	return b


func _shift_month(delta: int) -> void:
	var m := _month.y + delta
	var y := _month.x
	if m < 1:
		m = 12
		y -= 1
	elif m > 12:
		m = 1
		y += 1
	_month = Vector2i(y, m)
	_rebuild()


func _tasks_card() -> Control:
	var p := UIKit.panel("CardFlat")
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label(t("daily_challenges"), UITheme.FONT_BODY + 2, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	for task in DailyService.tasks_today():
		var prog := DailyService.task_progress(task)
		var target := int(task.target)
		var row := UIKit.hbox(10)
		var ic := UIKit.texrect(ContentService.icon("check" if prog >= target else "sparkle"), Vector2(30, 30))
		row.add_child(ic)
		var col := UIKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UIKit.label(t(str(task.label_key), {"count": target}), UITheme.FONT_BODY, false))
		var bar := UIKit.progress_bar(prog, target, 12)
		bar.theme_type_variation = "ProgressGreen"
		col.add_child(bar)
		row.add_child(col)
		row.add_child(UIKit.label("%s/%s" % [LocalizationService.format_number(prog), LocalizationService.format_number(target)], UITheme.FONT_SMALL, true, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER, false))
		v.add_child(row)
	if DailyService.tasks_claimed():
		v.add_child(UIKit.label(t("tasks_claimed"), UITheme.FONT_SMALL, true, UITheme.GREEN.darkened(0.2), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var claim := UIKit.button(t("tasks_claim"), "gold", "small", func() -> void:
			if DailyService.claim_tasks_reward():
				AudioService.play("reward")
				Router.toast(t("tasks_reward", {"count": EconomyService.reward("daily_tasks_claim")})))
		claim.disabled = not DailyService.all_tasks_done()
		if claim.disabled:
			claim.tooltip_text = t("tasks_claim_locked")
		v.add_child(claim)
		if claim.disabled:
			v.add_child(UIKit.label(t("tasks_claim_locked"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label(t("tasks_no_pressure"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	return p
