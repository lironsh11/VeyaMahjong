extends SceneTree
## Generates every app/store icon from one source image.
##   godot --headless --path . -s res://tools/make_app_icons.gd [-- <source image>]
## Default source: assets/source_art/app_icon_v3_source.png — the 發-tile icon from the LiShi v2
## pack (00_sources/branding_master.png, top-left icon, cropped at 36,40; excluded from
## import/export via .gdignore). It is the largest copy of this art in the pack (~331 px; the
## pack's 01_branding/isolated/app_icon_illustrated_a.png is the same pixels with the right edge
## cut off). Measured in source pixels:
##   OUTER  gold frame bounds, outer corner radius ~72 px (0.217 of the width)
##   INNER  painted art inside the frame
##
## Outputs (under res://assets/veya/; the export presets and project.godot point here):
##   app_icons/ios/AppIcon_1024.png                 opaque full-bleed art (Apple applies the mask)
##   app_icons/android/play_store_icon_512.png      opaque full-bleed art (Play applies the mask)
##   app_icons/android/adaptive_foreground_432.png  art filling the 72dp viewport (also the Android 12+ splash icon)
##   app_icons/android/adaptive_background_432.png  blurred bleed behind it
##   app_icons/android/adaptive_monochrome_432.png  tile silhouette (with its glyph cut out) for Android 13 themed icons
##   app_icons/android/mipmap-*/ic_launcher.png     legacy icons: the framed art, transparent corners
##   app_icons/web/favicon_64.png
##   branding/app_icon_master_{180,192,512,1024}.png (192 is the Godot project/window icon)
##
## The full-bleed art is 309 px, so the 512/1024 store sizes are upscaled (Lanczos + a light
## unsharp mask). Launcher icons (<= 192 px) and the adaptive layers are at or below native size.

const DEFAULT_SRC := "res://assets/source_art/app_icon_v3_source.png"
const OUT := "res://assets/veya/"
const OUTER := Rect2i(8, 8, 331, 334)
const INNER := Rect2i(20, 17, 309, 315)
const OUTER_RADIUS_FRAC := 0.217
const INNER_RADIUS := 61.0
## Tile in full-bleed pixels, for the themed (monochrome) layer.
const TILE_CENTRE := Vector2(151.5, 177.5)
const TILE_HALF := Vector2(88.0, 106.0)
const TILE_ANGLE_DEG := -11.0
const TILE_RADIUS := 16.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src_path: String = ProjectSettings.globalize_path(DEFAULT_SRC) if args.is_empty() else args[0]
	var src := Image.load_from_file(src_path)
	if src == null or src.is_empty():
		push_error("cannot load " + src_path)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)

	# Full-bleed square: the art inside the frame, its rounded corners painted in (they sit under
	# every store/launcher mask, but must not show gold or transparency on square launchers).
	var side := INNER.size.x
	var sq := Rect2i(INNER.position.x, INNER.position.y + (INNER.size.y - side) / 2, side, side)
	var bleed := src.get_region(sq)
	_fill_corners(bleed, Rect2(INNER.position - sq.position, INNER.size), INNER_RADIUS + 3.0)
	var big := _sharpen(_resized(bleed, 1024, false), 0.55)
	_save(big, "app_icons/ios/AppIcon_1024.png")
	_save(big, "branding/app_icon_master_1024.png")
	_save(_sharpen(_resized(bleed, 512, false), 0.35), "app_icons/android/play_store_icon_512.png")

	# Framed art with a clean rounded alpha edge (legacy launcher / window / favicon).
	var framed := src.get_region(OUTER)
	framed.resize(OUTER.size.x, OUTER.size.x, Image.INTERPOLATE_LANCZOS)  # 331x334 -> square (<1%)
	framed = _rounded(framed, OUTER_RADIUS_FRAC)
	for d in [["mdpi", 48], ["hdpi", 72], ["xhdpi", 96], ["xxhdpi", 144], ["xxxhdpi", 192]]:
		_save(_resized(framed, d[1], true), "app_icons/android/mipmap-%s/ic_launcher.png" % d[0])
	for s in [180, 192]:
		_save(_resized(framed, s, true), "branding/app_icon_master_%d.png" % s)
	_save(_sharpen(_resized(framed, 512, true), 0.35), "branding/app_icon_master_512.png")
	_save(_resized(framed, 64, true), "app_icons/web/favicon_64.png")

	# Adaptive icon (108dp canvas = 432 px; the launcher shows the central 72dp = 288 px through its
	# mask). FOREGROUND: the full-bleed art filling that viewport (+6 px so no seam shows) on a
	# transparent canvas. Godot also derives the Android 12+ system splash icon from this layer, so
	# it must carry the art. BACKGROUND: a blurred, enlarged copy so parallax never reveals an edge.
	var art_px := 300
	var at := Vector2i((432 - art_px) / 2, (432 - art_px) / 2)
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	var art_img := _resized(bleed, art_px, false)
	fg.blit_rect(art_img, Rect2i(Vector2i.ZERO, art_img.get_size()), at)
	_save(fg, "app_icons/android/adaptive_foreground_432.png")
	_save(_resized(_resized(bleed, 18, false), 432, false), "app_icons/android/adaptive_background_432.png")
	var mono := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	var tile := _resized(_tile_silhouette(bleed), art_px, true)
	mono.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), at)
	_save(mono, "app_icons/android/adaptive_monochrome_432.png")
	print("ICONS DONE")
	quit(0)


func _resized(img: Image, size: int, keep_alpha: bool) -> Image:
	var out := img.duplicate() as Image
	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if not keep_alpha:
		out.convert(Image.FORMAT_RGB8)  # store icons must be opaque
		out.convert(Image.FORMAT_RGBA8)
	return out


func _rounded(img: Image, radius_frac: float) -> Image:
	## Anti-aliased rounded-square alpha mask (drops the sheet's glow fringe outside the frame).
	var out := img.duplicate() as Image
	var n := out.get_width()
	var r := n * radius_frac
	for y in n:
		for x in n:
			var cover := clampf(r - _corner_dist(Vector2(x + 0.5, y + 0.5), Rect2(0, 0, n, n), r) + 0.5, 0.0, 1.0)
			var c := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(c, minf(c.a, cover)))
	return out


func _corner_dist(p: Vector2, rect: Rect2, r: float) -> float:
	## Distance from the corner-circle centre for points in a corner zone (else 0).
	var dx := maxf(0.0, maxf(rect.position.x + r - p.x, p.x - (rect.end.x - r)))
	var dy := maxf(0.0, maxf(rect.position.y + r - p.y, p.y - (rect.end.y - r)))
	return Vector2(dx, dy).length()


func _fill_corners(img: Image, inner: Rect2, r: float) -> void:
	## Harmonic fill of everything outside the inner rounded rect (frame arcs, transparency).
	var n := img.get_width()
	var buf: Array[Color] = []
	buf.resize(n * n)
	var hole := PackedByteArray()
	hole.resize(n * n)
	for y in n:
		for x in n:
			buf[y * n + x] = img.get_pixel(x, y)
			if _corner_dist(Vector2(x + 0.5, y + 0.5), inner, r) > r - 1.0:
				hole[y * n + x] = 1
	# Seed by nearest known neighbours (onion peel), then relax.
	var known := PackedByteArray()
	known.resize(n * n)
	var todo: PackedInt32Array = []
	for i in n * n:
		known[i] = 1 - hole[i]
		if hole[i] == 1:
			todo.append(i)
	while not todo.is_empty():
		var next: PackedInt32Array = []
		var filled: PackedInt32Array = []
		for i in todo:
			var acc := Color(0, 0, 0, 0)
			var k := 0
			for d in [1, -1, n, -n]:
				var j: int = i + d
				if j >= 0 and j < n * n and absi((j % n) - (i % n)) <= 1 and known[j] == 1:
					acc += buf[j]
					k += 1
			if k > 0:
				buf[i] = acc / k
				filled.append(i)
			else:
				next.append(i)
		if filled.is_empty():
			break
		for i in filled:
			known[i] = 1
		todo = next
	for _it in 80:
		for i in n * n:
			if hole[i] == 1:
				var x := i % n
				var y := i / n
				var acc := Color(0, 0, 0, 0)
				var k := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
						acc += buf[q.y * n + q.x]
						k += 1
				buf[i] = acc / k
	for i in n * n:
		if hole[i] == 1:
			var c := buf[i]
			img.set_pixel(i % n, i / n, Color(c.r, c.g, c.b, 1.0))


func _sharpen(img: Image, amount: float) -> Image:
	## Unsharp mask (Gaussian sigma ~1.2 px) to restore edge contrast after upscaling.
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	var k := [0.0702, 0.1311, 0.1907, 0.2160, 0.1907, 0.1311, 0.0702]
	var tmp := PackedFloat32Array()
	tmp.resize(w * h * 3)
	for y in h:
		for x in w:
			for c in 3:
				var acc := 0.0
				for t in 7:
					var xx := clampi(x + t - 3, 0, w - 1)
					acc += src[(y * w + xx) * 4 + c] * k[t]
				tmp[(y * w + x) * 3 + c] = acc
	var out := src.duplicate()
	for y in h:
		for x in w:
			for c in 3:
				var blur := 0.0
				for t in 7:
					var yy := clampi(y + t - 3, 0, h - 1)
					blur += tmp[(yy * w + x) * 3 + c] * k[t]
				var v: float = src[(y * w + x) * 4 + c]
				out[(y * w + x) * 4 + c] = clampi(roundi(v + (v - blur) * amount), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


func _tile_silhouette(bleed: Image) -> Image:
	## Themed-icon layer: the tile as a rounded rectangle (measured on the art, in full-bleed
	## pixels: corners ~(40,88) (213,60) (263,267)) with the glyph's teal strokes cut out.
	var n := bleed.get_width()
	var ang := deg_to_rad(TILE_ANGLE_DEG)
	var out := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var a := _rrect_cover(Vector2(x + 0.5, y + 0.5), TILE_CENTRE, TILE_HALF, ang, TILE_RADIUS)
			if a <= 0.0:
				continue
			var c := bleed.get_pixel(x, y)
			var ink := 0.0
			# Only inside the face: the lotus leaves at the tile's foot share the glyph's teal.
			var face := _rrect_cover(Vector2(x + 0.5, y + 0.5), TILE_CENTRE, TILE_HALF - Vector2(16, 16), ang, TILE_RADIUS)
			if face > 0.0 and c.h > 0.36 and c.h < 0.52:
				ink = clampf((c.s - 0.35) * 5.0, 0.0, 1.0) * clampf((0.8 - c.v) * 5.0, 0.0, 1.0)
			out.set_pixel(x, y, Color(1, 1, 1, a * (1.0 - ink)))
	return out


func _rrect_cover(p: Vector2, c: Vector2, half: Vector2, ang: float, radius: float) -> float:
	var q := (p - c).rotated(-ang)
	var d := (q.abs() - half + Vector2(radius, radius))
	var outside := Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - radius
	return clampf(0.5 - outside, 0.0, 1.0)


func _save(img: Image, rel: String) -> void:
	var path := OUT + rel
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	# Windows indexing/antivirus can briefly lock a file that was just rewritten; retry.
	var err := FAILED
	for _try in 10:
		err = img.save_png(ProjectSettings.globalize_path(path))
		if err == OK:
			break
		OS.delay_msec(150)
	print("%s %s %s" % ["wrote" if err == OK else "FAILED", rel, img.get_size()])
