class_name ModalDialog
extends Control
## Accessible modal: dims and blocks everything beneath (no accidental board taps), moves
## keyboard focus to the first action, closes on Android back/Escape when dismissible, and
## pops in briefly unless Reduced Motion is on.

signal closed(result: String)

var dismissible: bool = true
var body_box: VBoxContainer
var buttons_box: VBoxContainer
var _closing: bool = false


static func open(parent: Node, title_text: String, body_text: String = "", p_dismissible: bool = true) -> ModalDialog:
	var m := ModalDialog.new()
	m.dismissible = p_dismissible
	m._build(title_text, body_text)
	parent.add_child(m)
	Router.push_modal(m)
	return m


func _build(title_text: String, body_text: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.1, 0.16, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and dismissible:
			try_dismiss())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var v := UIKit.vbox(14)
	panel.add_child(v)
	if title_text != "":
		var tl := UIKit.label(title_text, UITheme.FONT_H2 + 2, true, null, HORIZONTAL_ALIGNMENT_CENTER)
		tl.custom_minimum_size.x = 380
		v.add_child(tl)
	body_box = UIKit.vbox(10)
	v.add_child(body_box)
	if body_text != "":
		var bl := UIKit.label(body_text, UITheme.FONT_BODY, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER)
		bl.custom_minimum_size.x = 380
		body_box.add_child(bl)
	buttons_box = UIKit.vbox(10)
	v.add_child(buttons_box)
	panel.pivot_offset = Vector2(220, 200)
	if not AccessibilityService.reduced_motion():
		panel.scale = Vector2(0.94, 0.94)
		panel.modulate.a = 0.0
		var tw := panel.create_tween().set_parallel(true)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.12)


func add_action(text: String, id: String, color: String = "green", size: String = "large") -> Button:
	var b := UIKit.button(text, color, size, func() -> void: close(id))
	buttons_box.add_child(b)
	if buttons_box.get_child_count() == 1:
		UIKit.focus_initial.call_deferred(b)
	return b


func add_content(c: Control) -> void:
	body_box.add_child(c)


func try_dismiss() -> void:
	if dismissible:
		close("dismiss")


func close(result: String) -> void:
	if _closing:
		return
	_closing = true
	Router.pop_modal(self)
	closed.emit(result)
	queue_free()
