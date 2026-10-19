class_name StreakFlame
extends Control
## Small drawn flame for the win streak (the icon pack has none). Warm gold-orange while a
## streak runs, grey at zero. Flickers gently unless Reduced Motion is on.

var lit: bool = true:
	set(v):
		lit = v
		queue_redraw()
var _t: float = 0.0


static func make(px: float, p_lit: bool = true) -> StreakFlame:
	var f := StreakFlame.new()
	f.custom_minimum_size = Vector2(px, px)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.lit = p_lit
	return f


func _process(delta: float) -> void:
	if not lit or AccessibilityService.reduced_motion():
		return
	_t += delta
	queue_redraw()


func _flame(center_x: float, base_y: float, w: float, h: float, sway: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 14
	for k in steps + 1:
		# Right side from the base up to the tip, then the left side back down.
		var u := float(k) / steps
		var y := base_y - h * u
		var half := w * 0.5 * sin(PI * minf(1.0, 0.15 + u * 0.95)) * (1.0 - u * 0.65)
		pts.append(Vector2(center_x + half + sway * u * u, y))
	for k in range(steps, -1, -1):
		var u := float(k) / steps
		var y := base_y - h * u
		var half := w * 0.5 * sin(PI * minf(1.0, 0.15 + u * 0.95)) * (1.0 - u * 0.65)
		pts.append(Vector2(center_x - half + sway * u * u, y))
	return pts


func _draw() -> void:
	var s := size
	var cx := s.x * 0.5
	var base := s.y * 0.95
	var sway := sin(_t * 7.0) * s.x * 0.06
	var outer := Color("F08A24") if lit else Color(0.55, 0.55, 0.55)
	var inner := Color("F4C568") if lit else Color(0.75, 0.75, 0.75)
	draw_colored_polygon(_flame(cx, base, s.x * 0.8, s.y * 0.9, sway), outer)
	draw_colored_polygon(_flame(cx, base, s.x * 0.45, s.y * 0.55, sway * 0.6), inner)
