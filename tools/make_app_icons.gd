extends SceneTree
## Generates every app/store icon from one source image.
##   godot --headless --path . -s res://tools/make_app_icons.gd [-- <source image>]
## Default source: assets/source_art/app_icon_v2_source.webp (1254x1254, rounded-square art on a
## white background; excluded from import/export via .gdignore).
##
## Outputs (overwrites the pack-derived icons under res://assets/veya/):
##   app_icons/ios/AppIcon_1024.png                 opaque full-bleed square (Apple applies the mask)
##   app_icons/android/play_store_icon_512.png      opaque full-bleed square (Play applies the mask)
##   app_icons/android/adaptive_foreground_432.png  art filling the 72dp viewport (also the Android 12+ splash icon)
##   app_icons/android/adaptive_background_432.png  blurred bleed behind it
##   app_icons/android/adaptive_monochrome_432.png  two-tile silhouette for Android 13 themed icons
##   app_icons/android/mipmap-*/ic_launcher.png     legacy icons: rounded art, transparent corners
##   app_icons/web/favicon_64.png (favicon.ico wraps it: see docs/BRANDING.md)
##   branding/app_icon_master_{180,192,512,1024}.png (192 is the Godot project/window icon)

const DEFAULT_SRC := "res://assets/source_art/app_icon_v2_source.webp"
const OUT := "res://assets/veya/"
const WHITE_LUMA := 0.97

## Measured on the source: artwork bounds 17..1235, corner radius ~260 px. Full-bleed crops
## must stay inside the rounded corners: inset >= r * (1 - 1/sqrt(2)) ~= 77 px, plus a margin.
const CORNER_RADIUS_FRAC := 0.213   ## radius / art width
const FULL_BLEED_INSET_FRAC := 0.075


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src_path: String = ProjectSettings.globalize_path(DEFAULT_SRC) if args.is_empty() else args[0]
	var src := Image.load_from_file(src_path)
	if src == null or src.is_empty():
		push_error("cannot load " + src_path)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var art := _art_rect(src)
	print("source %s, art %s" % [src.get_size(), art])

	# Full-bleed square (no white, no rounded corners).
	var inset := int(art.size.x * FULL_BLEED_INSET_FRAC)
	var bleed := src.get_region(art.grow(-inset))
	_save(_resized(bleed, 1024, false), "app_icons/ios/AppIcon_1024.png")
	_save(_resized(bleed, 512, false), "app_icons/android/play_store_icon_512.png")
	_save(_resized(bleed, 1024, false), "branding/app_icon_master_1024.png")

	# Rounded art with transparent corners (legacy launcher / window / favicon).
	var rounded := _rounded(src.get_region(art), CORNER_RADIUS_FRAC)
	for d in [["mdpi", 48], ["hdpi", 72], ["xhdpi", 96], ["xxhdpi", 144], ["xxxhdpi", 192]]:
		_save(_resized(rounded, d[1], true), "app_icons/android/mipmap-%s/ic_launcher.png" % d[0])
	for s in [180, 192, 512]:
		_save(_resized(rounded, s, true), "branding/app_icon_master_%d.png" % s)
	_save(_resized(rounded, 64, true), "app_icons/web/favicon_64.png")

	# Adaptive icon (108dp canvas = 432 px; the launcher shows the central 72dp = 288 px through its
	# mask). FOREGROUND: the full-bleed art filling that viewport (+6 px so no seam shows) on a
	# transparent canvas. Godot also derives the Android 12+ system splash icon from this layer, so
	# it must carry the art. BACKGROUND: a blurred, enlarged copy so parallax never reveals an edge.
	var art_px := 300
	var art_img := _resized(bleed, art_px, false)
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	fg.blit_rect(art_img, Rect2i(Vector2i.ZERO, art_img.get_size()), Vector2i((432 - art_px) / 2, (432 - art_px) / 2))
	_save(fg, "app_icons/android/adaptive_foreground_432.png")
	_save(_resized(_resized(bleed, 18, false), 432, false), "app_icons/android/adaptive_background_432.png")
	_save(_monochrome(432), "app_icons/android/adaptive_monochrome_432.png")
	print("ICONS DONE")
	quit(0)


func _art_rect(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var l := 0
	while l < w and img.get_pixel(l, h / 2).get_luminance() > WHITE_LUMA:
		l += 1
	var r := w - 1
	while r > 0 and img.get_pixel(r, h / 2).get_luminance() > WHITE_LUMA:
		r -= 1
	var t := 0
	while t < h and img.get_pixel(w / 2, t).get_luminance() > WHITE_LUMA:
		t += 1
	var b := h - 1
	while b > 0 and img.get_pixel(w / 2, b).get_luminance() > WHITE_LUMA:
		b -= 1
	# Square it around the centre (the art is square).
	var side := mini(r - l + 1, b - t + 1)
	return Rect2i((l + r + 1 - side) / 2, (t + b + 1 - side) / 2, side, side)


func _resized(img: Image, size: int, keep_alpha: bool) -> Image:
	var out := img.duplicate() as Image
	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if not keep_alpha:
		out.convert(Image.FORMAT_RGB8)  # store icons must be opaque
		out.convert(Image.FORMAT_RGBA8)
	return out


func _rounded(img: Image, radius_frac: float) -> Image:
	## Applies an anti-aliased rounded-square alpha mask (removes the white surround).
	var out := img.duplicate() as Image
	var n := out.get_width()
	var r := n * radius_frac
	for y in n:
		for x in n:
			var dx := maxf(0.0, maxf(r - (x + 0.5), (x + 0.5) - (n - r)))
			var dy := maxf(0.0, maxf(r - (y + 0.5), (y + 0.5) - (n - r)))
			var dist := Vector2(dx, dy).length()
			var a := clampf(r - dist + 0.5, 0.0, 1.0)
			if a < 1.0:
				var c := out.get_pixel(x, y)
				out.set_pixel(x, y, Color(c, c.a * a))
	return out


func _monochrome(n: int) -> Image:
	## Two tilted tile silhouettes matching the icon's composition, inside the 66dp safe zone.
	## White on transparent; Android tints it for themed icons.
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var s := n / 432.0
	# (centre, half-size, angle) in 432-px canvas units, measured from the artwork.
	var left := [Vector2(186, 203), Vector2(56, 74), deg_to_rad(-6.0)]
	var right := [Vector2(248, 233), Vector2(57, 76), deg_to_rad(9.0)]
	var gap := 7.0
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / s
			var a_right := _rrect_cover(p, right[0], right[1], right[2], 14.0)
			var a_left := _rrect_cover(p, left[0], left[1], left[2], 14.0)
			# Cut a thin gap around the front tile so the two shapes read as separate tiles.
			var a_halo := _rrect_cover(p, right[0], right[1] + Vector2(gap, gap), right[2], 14.0 + gap)
			var a := maxf(a_right, a_left * (1.0 - a_halo))
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


func _rrect_cover(p: Vector2, c: Vector2, half: Vector2, ang: float, radius: float) -> float:
	var q := (p - c).rotated(-ang)
	var d := (q.abs() - half + Vector2(radius, radius))
	var outside := Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - radius
	return clampf(0.5 - outside, 0.0, 1.0)


func _save(img: Image, rel: String) -> void:
	var path := OUT + rel
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("%s %s %s" % ["wrote" if err == OK else "FAILED", rel, img.get_size()])
