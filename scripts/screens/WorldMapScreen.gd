extends Screen
## Journey / chapter map: three worlds, 50 real levels each, with completed / current /
## locked states. Locked levels explain why instead of doing nothing.

const COLS := 5
const NODE_DISC_LIFT := 6.0

var _world_id: String = ""


func _ready() -> void:
	var p := Router.params
	if p.has("world"):
		_world_id = str(p.world)
	else:
		_world_id = str(ContentService.world_for_level(GameState.next_level(ContentService.level_count())).get("id", "aurora_garden"))
	super._ready()
	AudioService.play_world_music(_world_id)


func build_background() -> void:
	UIKit.fullscreen_bg(self, ContentService.world_bg(_world_id, "map", AccessibilityService.low_profile), 0.12, Color.WHITE)


func build() -> void:
	var root := UIKit.vbox(10)
	safe.add_child(root)
	root.add_child(UIKit.header(t("worlds"), func() -> void: Router.back(), true))
	# World tabs
	var tabs := UIKit.hbox(6)
	for w in ContentService.worlds:
		var wid := str(w.id)
		var range_v := ContentService.world_range(wid)
		var unlocked := GameState.is_level_unlocked(range_v.x)
		var b := UIKit.tab_button(t(ContentService.world_name_key(wid)), wid == _world_id, func() -> void:
			_world_id = wid
			AudioService.play_world_music(wid)
			_rebuild())
		if not unlocked:
			b.icon = UITheme.scaled_tex("ui/icons/emerald/lock.png", 0.27)
		tabs.add_child(b)
	root.add_child(tabs)
	var r := ContentService.world_range(_world_id)
	var done := 0
	for id in range(r.x, r.y + 1):
		if GameState.is_level_completed(id):
			done += 1
	var summary := UIKit.panel("CardFlat")
	var sv := UIKit.vbox(4)
	summary.add_child(sv)
	sv.add_child(UIKit.label(t("world_progress", {"done": done, "total": r.y - r.x + 1}), UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	sv.add_child(UIKit.progress_bar(done, r.y - r.x + 1, 12))
	if not GameState.is_level_unlocked(r.x):
		sv.add_child(UIKit.label(t("world_locked_hint", {"level": r.x - 1}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	root.add_child(summary)
	# Level grid
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	var current_btn: Control = null
	var next := GameState.next_level(ContentService.level_count())
	for id in range(r.x, r.y + 1):
		var node := _level_node(id, next)
		grid.add_child(node)
		if id == next:
			current_btn = node
	var center := CenterContainer.new()
	center.add_child(grid)
	var sc := UIKit.scroll(center)
	root.add_child(sc)
	root.add_child(UIKit.bottom_nav("worlds"))
	if current_btn:
		_scroll_to.call_deferred(sc, current_btn)


func _scroll_to(sc: ScrollContainer, target: Control) -> void:
	# Wait for the grid to be laid out, then centre the current level.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(target) or not is_instance_valid(sc):
		return
	var y := target.get_global_rect().position.y - sc.get_global_rect().position.y + sc.scroll_vertical
	sc.scroll_vertical = int(maxf(0.0, y - sc.size.y * 0.4))
	UIKit.focus_initial(target)


func _level_node(id: int, next: int) -> Control:
	var completed := GameState.is_level_completed(id)
	var unlocked := GameState.is_level_unlocked(id)
	var b := Button.new()
	b.theme_type_variation = "FlatTool"
	b.custom_minimum_size = Vector2(84, 84)
	b.focus_mode = Control.FOCUS_ALL
	var sprite := "complete" if completed else ("current" if id == next else ("available" if unlocked else "locked"))
	var bg := UIKit.texrect(UITheme.scaled_tex("ui/level_nodes/%s.png" % sprite, 0.6), Vector2(80, 80))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(bg)
	var l := UIKit.label(LocalizationService.format_number(id), UITheme.FONT_H2, true, Color.WHITE if unlocked else Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, false)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_bottom = -NODE_DISC_LIFT  # the node disc sits above its drop shadow
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.55))
	l.add_theme_constant_override("outline_size", 5)
	b.add_child(l)
	if completed:
		var chk := UIKit.texrect(ContentService.icon("check", false), Vector2(26, 26))
		b.add_child(chk)  # attach before positioning (RTL mirrors the corner automatically)
		chk.position = Vector2(58, 0)
		chk.size = Vector2(26, 26)
	var state_key := "level_state_done" if completed else ("level_state_open" if unlocked else "level_state_locked")
	AccessibilityService.set_access_name(b, t("level_n", {"level": id}) + ", " + t(state_key))
	b.pressed.connect(func() -> void:
		if unlocked:
			AudioService.play("button")
			Router.go("gameplay", {"mode": "level", "level": id})
		else:
			AudioService.play("invalid")
			Router.toast(t("level_locked_hint", {"level": id - 1})))
	return b
