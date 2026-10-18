extends Node
## Screen navigation, Android back handling, modal stack, toasts and app lifecycle.
##
## Lifecycle: on pause/focus-loss/close the current screen gets save_state() and GameState is
## flushed synchronously, so a crash or OS kill after backgrounding never loses a finished
## pair. On OS memory warnings inactive textures are released.

signal screen_changed(name: String)
signal app_paused
signal app_resumed

const SCREENS := {
	"boot": "res://scenes/boot/Boot.tscn",
	"tutorial": "res://scenes/tutorial/Tutorial.tscn",
	"home": "res://scenes/home/Home.tscn",
	"worlds": "res://scenes/worlds/WorldMap.tscn",
	"gameplay": "res://scenes/gameplay/Gameplay.tscn",
	"bloom": "res://scenes/bloom/Bloom.tscn",
	"daily": "res://scenes/daily/DailyPuzzle.tscn",
	"collection": "res://scenes/collection/Collection.tscn",
	"shop": "res://scenes/store/Shop.tscn",
	"settings": "res://scenes/settings/Settings.tscn",
}

var current_name: String = ""
var params: Dictionary = {}
var _stack: Array = []
var _modals: Array = []
var _layer: CanvasLayer
var _fade: ColorRect
var _toast_box: VBoxContainer
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_quit_on_go_back(false)
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(UITheme.IVORY, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)
	_toast_box = VBoxContainer.new()
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_box.offset_bottom = -170
	_toast_box.alignment = BoxContainer.ALIGNMENT_END
	_layer.add_child(_toast_box)
	# Debug-only visual QA tour (never available in release builds).
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--tour="):
				var tour: Node = load("res://scripts/debug/ScreenshotTour.gd").new()
				add_child.call_deferred(tour)
		if OS.get_cmdline_user_args().has("--perf-log") or FileAccess.file_exists("user://perf_log.flag"):
			add_child.call_deferred(load("res://scripts/debug/PerfLogger.gd").new())


func current_screen() -> Node:
	return get_tree().current_scene


func go(name: String, p: Dictionary = {}, push: bool = true) -> void:
	if not SCREENS.has(name) or _busy:
		return
	if push and current_name != "" and current_name != "boot" and current_name != name:
		_stack.append([current_name, params])
		if _stack.size() > 12:
			_stack.pop_front()
	_switch(name, p)


func replace(name: String, p: Dictionary = {}) -> void:
	go(name, p, false)


func reset_to(name: String, p: Dictionary = {}) -> void:
	_stack.clear()
	go(name, p, false)


func back() -> void:
	if _stack.is_empty():
		if current_name != "home":
			_switch("home", {})
		else:
			# Root of the app: let the OS background us (Android convention).
			_save_everything()
			get_tree().quit()
		return
	var prev: Array = _stack.pop_back()
	_switch(prev[0], prev[1])


func _switch(name: String, p: Dictionary) -> void:
	_busy = true
	var scr := current_screen()
	if scr and scr.has_method("save_state"):
		scr.save_state()
	_modals.clear()
	var animate := not AccessibilityService.reduced_motion() and current_name != ""
	if animate:
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 1.0, 0.12)
		await tw.finished
	params = p
	current_name = name
	get_tree().change_scene_to_file(SCREENS[name])
	await get_tree().process_frame
	if animate:
		var tw2 := create_tween()
		tw2.tween_property(_fade, "color:a", 0.0, 0.16)
	_busy = false
	screen_changed.emit(name)


# --- modals -------------------------------------------------------------------------

func push_modal(m: Node) -> void:
	_modals.append(m)


func pop_modal(m: Node) -> void:
	_modals.erase(m)


func has_modal() -> bool:
	_modals = _modals.filter(func(m: Node) -> bool: return is_instance_valid(m))
	return not _modals.is_empty()


func handle_back() -> void:
	if has_modal():
		var top: Node = _modals.back()
		if top.has_method("try_dismiss"):
			top.try_dismiss()
		return
	var scr := current_screen()
	if scr and scr.has_method("on_back") and scr.on_back():
		return
	back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		handle_back()


# --- toasts -------------------------------------------------------------------------

func toast(text: String, seconds: float = 2.4) -> void:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "HudPill"
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	pc.add_child(l)
	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pc)
	_toast_box.add_child(row)
	while _toast_box.get_child_count() > 2:
		_toast_box.get_child(0).queue_free()
		_toast_box.remove_child(_toast_box.get_child(0))
	if not AccessibilityService.reduced_motion():
		row.modulate.a = 0.0
		create_tween().tween_property(row, "modulate:a", 1.0, 0.15)
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(row):
			row.queue_free())


# --- lifecycle ----------------------------------------------------------------------

func _save_everything() -> void:
	var scr := current_screen()
	if scr and scr.has_method("save_state"):
		scr.save_state()
	GameState.save_now()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			_save_everything()
			app_paused.emit()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			app_resumed.emit()
		NOTIFICATION_OS_MEMORY_WARNING:
			ContentService.release_inactive()
