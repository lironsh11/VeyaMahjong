extends SceneTree
## Builds the 4-, 5- and 6-slot tray frames from ONE owner design: the premium 5-slot tray
## (jade, gold, sakura; 2026-10-19), so every tray size looks exactly alike.
##   godot --headless --path . -s res://tools/make_tray_art.gd [-- <preview dir>]
## Source: res://assets/source_art/tray_premium_5_source.png (excluded from import, .gdignore).
## Output: res://art/lishi_v2/ui/tray/tray_{4,5,6}.png, OUT_H px high (TrayView draws them at
## half size). Then run tools/measure_tray_art.gd to record the slot positions.
##
## How the source is cut (everything is measured on the image, nothing is hard-coded):
## - The four pink divider gems between the wells give the cut lines (their centres) and the
##   slot pitch. Left cap = up to gem 1 (flowers + well 1), one segment = gem 1 to gem 2 (one
##   well), right cap = from gem 4 (well 5 + flowers). N slots = left + (N-2) segments + right.
## - Halves of identical gems meet at every cut, so the joins are invisible.
## - The frame bands above and below the wells are horizontally uniform except for the centre
##   ornaments, so between the caps they are rebuilt from one clean column, and the top and
##   bottom ornaments are pasted back at the new centre with feathered edges.

const SRC := "res://assets/source_art/tray_premium_5_source.png"
const OUT := "res://art/lishi_v2/ui/tray/tray_%d.png"
const OUT_H := 256
const CAPS := [4, 5, 6]
const FEATHER := 28
const CAP_BLEND := 60   ## source px inside each cap where its band fades into the clean band


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var preview_dir: String = args[0] if args.size() > 0 else ""
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	src.convert(Image.FORMAT_RGBA8)
	src = _crop_opaque(src)
	var w := src.get_width()
	var h := src.get_height()
	var gems := _gem_centres(src)
	if gems.size() != 4:
		push_error("expected 4 divider gems, found %d" % gems.size())
		quit(1)
		return
	var pitch := int(round((gems[3] - gems[0]) / 3.0))
	var c1 := int(round(gems[0]))
	var c4 := int(round(gems[3]))
	# Well 2 (the template segment's well) gives the rows the wells occupy; the wells' own gold
	# rings (with their rounded corners into the gaps) are kept, only the outer bands are rebuilt.
	var wx := int((gems[0] + gems[1]) * 0.5)
	var well := _well_rows(src, wx)
	var top_cut: int = _gold_run(src, wx, well.x - 1, -1).x       # first row of the ring's top line
	var bottom_cut: int = _gold_run(src, wx, well.y + 1, 1).y + 1  # row after the ring's bottom line
	var orn := _ornament_span(src, c1, c4, top_cut, bottom_cut)
	var clean_x := int((c1 + orn.x) * 0.5)
	print("source %dx%d gems %s pitch %d wells y %d-%d ornament x %d-%d clean column %d" % [w, h, str(gems), pitch, well.x, well.y, orn.x, orn.y, clean_x])
	for n in CAPS:
		var out_w: int = c1 + (int(n) - 2) * pitch + (w - c4)
		var out := Image.create(out_w, h, false, Image.FORMAT_RGBA8)
		out.blit_rect(src, Rect2i(0, 0, c1, h), Vector2i(0, 0))
		for k in int(n) - 2:
			out.blit_rect(src, Rect2i(c1, 0, pitch, h), Vector2i(c1 + k * pitch, 0))
		out.blit_rect(src, Rect2i(c4, 0, w - c4, h), Vector2i(c1 + (n - 2) * pitch, 0))
		# Clean bands between the caps, fading in over CAP_BLEND columns inside each cap so the
		# caps' own band shading meets the clean band without a seam.
		var right_start := c1 + (int(n) - 2) * pitch
		for x in range(c1 - CAP_BLEND, right_start + CAP_BLEND):
			var wgt := 1.0
			if x < c1:
				wgt = float(x - (c1 - CAP_BLEND)) / CAP_BLEND
			elif x >= right_start:
				wgt = float(right_start + CAP_BLEND - x) / CAP_BLEND
			for y in range(0, h):
				if y >= top_cut and y < bottom_cut:
					continue
				var clean := src.get_pixel(clean_x, y)
				out.set_pixel(x, y, clean if wgt >= 1.0 else out.get_pixel(x, y).lerp(clean, wgt))
		# Ornaments back at the centre.
		var dx := int(round(out_w * 0.5 - (orn.x + orn.y) * 0.5))
		for sx in range(orn.x - FEATHER, orn.y + FEATHER + 1):
			var tx := sx + dx
			if sx < 0 or sx >= w or tx < 0 or tx >= out_w:
				continue
			var wgt := 1.0
			if sx < orn.x:
				wgt = float(sx - (orn.x - FEATHER)) / FEATHER
			elif sx > orn.y:
				wgt = float(orn.y + FEATHER - sx) / FEATHER
			wgt = clampf(wgt, 0.0, 1.0)
			for y in range(0, h):
				if y >= top_cut and y < bottom_cut:
					continue
				out.set_pixel(tx, y, out.get_pixel(tx, y).lerp(src.get_pixel(sx, y), wgt))
		var scaled := out.duplicate() as Image
		scaled.resize(int(round(out_w * float(OUT_H) / h)), OUT_H, Image.INTERPOLATE_LANCZOS)
		var path := ProjectSettings.globalize_path(OUT % n)
		scaled.save_png(path)
		if preview_dir != "":
			scaled.save_png(preview_dir.path_join("tray_%d.png" % n))
		print("tray_%d %dx%d" % [n, scaled.get_width(), scaled.get_height()])
	quit(0)


static func _crop_opaque(img: Image) -> Image:
	## Crop to the visibly opaque area (the source has faint near-transparent fringes, so
	## get_used_rect() would keep empty margins that waste the tray's height).
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.2:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	return img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))


static func _pink(c: Color) -> bool:
	return c.a > 0.9 and c.r > 0.85 and c.g < 0.8 and c.b > 0.55 and c.r - c.g > 0.15


static func _gem_centres(img: Image) -> Array:
	## Centres (x) of the pink gems at mid-height between the wells, left to right.
	var my := img.get_height() / 2
	var margin := int(img.get_width() * 0.18)  # skip the flowers on the caps
	var cols: Array = []
	for x in range(margin, img.get_width() - margin):
		for y in range(my - 60, my + 60):
			if _pink(img.get_pixel(x, y)):
				cols.append(x)
				break
	var groups: Array = []
	for x in cols:
		if groups.is_empty() or x - int(groups[-1][-1]) > 5:
			groups.append([x])
		else:
			groups[-1].append(x)
	var out: Array = []
	for g in groups:
		if g.size() >= 8:
			out.append((float(g[0]) + float(g[-1])) * 0.5)
	return out


static func _is_well(c: Color) -> bool:
	return c.a > 0.9 and c.r < 0.12 and c.g < 0.47 and c.b < 0.38


static func _well_rows(img: Image, x: int) -> Vector2i:
	## First and last row of the well interior in column x (from the middle outwards).
	var y0 := img.get_height() / 2
	var y1 := y0
	while y0 > 0 and _is_well(img.get_pixel(x, y0 - 1)):
		y0 -= 1
	while y1 < img.get_height() - 1 and _is_well(img.get_pixel(x, y1 + 1)):
		y1 += 1
	return Vector2i(y0, y1)


static func _gold_run(img: Image, x: int, from_y: int, step: int) -> Vector2i:
	## Walking from from_y in direction step (past the dark well edge), the first run of gold
	## pixels: the ring line. Returns (first row, last row) in increasing order.
	var y := from_y
	while y > 0 and y < img.get_height() - 1 and not _gold(img.get_pixel(x, y)):
		y += step
	var a := y
	while y > 0 and y < img.get_height() - 1 and _gold(img.get_pixel(x, y + step)):
		y += step
	return Vector2i(mini(a, y), maxi(a, y))


static func _gold(c: Color) -> bool:
	return c.a > 0.5 and c.r > 0.55 and c.r > c.b + 0.2


static func _ornament_span(img: Image, c1: int, c4: int, top_cut: int, bottom_cut: int) -> Vector2i:
	## Columns (between the caps) where the bands differ from a plain band: the centre ornaments.
	## A plain band column is the same as its neighbours; the ornament is the widest run of
	## columns that stick out above or below the frame.
	var frame_top := top_cut
	var frame_bottom := bottom_cut
	var ref_x := c1 + 40
	for y in top_cut:
		if img.get_pixel(ref_x, y).a > 0.5:
			frame_top = y
			break
	for y in range(img.get_height() - 1, bottom_cut, -1):
		if img.get_pixel(ref_x, y).a > 0.5:
			frame_bottom = y
			break
	var lo := c4
	var hi := c1
	for x in range(c1, c4):
		var sticks_out := false
		for y in range(0, frame_top - 2):
			if img.get_pixel(x, y).a > 0.5:
				sticks_out = true
				break
		if not sticks_out:
			for y in range(frame_bottom + 3, img.get_height()):
				if img.get_pixel(x, y).a > 0.5:
					sticks_out = true
					break
		if sticks_out:
			lo = mini(lo, x)
			hi = maxi(hi, x)
	return Vector2i(lo, hi)
