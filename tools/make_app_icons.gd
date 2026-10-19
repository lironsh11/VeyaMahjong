extends SceneTree
## Generates every app/store icon from one source image.
##   godot --headless --path . -s res://tools/make_app_icons.gd [-- <source image> [<preview dir>]]
## Default source: assets/source_art/app_icon_v4_source.webp — the owner's 2026-10-19 icon (blossom
## tile in a gold ring, "LiShi MAHJONG", pagoda garden; excluded from import/export via .gdignore).
## 1254 px: painted art on a rounded square with a thin white margin. Measured in source pixels:
##   ART         square inside the white margin (margin is 2-7 px; the art starts at 70 px along
##               each diagonal, i.e. a corner radius of ~0.171 of ART)
## The art is larger than every output, so all sizes are downscaled (Lanczos), never upscaled.
##
## Outputs (under res://assets/veya/; the export presets and project.godot point here):
##   app_icons/ios/AppIcon_1024.png                 opaque full-bleed art (Apple applies the mask)
##   app_icons/android/play_store_icon_512.png      opaque full-bleed art (Play applies the mask)
##   app_icons/android/adaptive_foreground_432.png  art filling the 72dp viewport (also the Android 12+ splash icon)
##   app_icons/android/adaptive_background_432.png  blurred bleed behind it
##   app_icons/android/adaptive_monochrome_432.png  tile face silhouette (blossom cut out) for Android 13 themed icons
##   app_icons/android/mipmap-*/ic_launcher.png     legacy icons: the art with transparent rounded corners
##   app_icons/web/favicon_64.png
##   branding/app_icon_master_{180,192,512,1024}.png (192 is the Godot project/window icon)
## With a preview dir, also writes masked previews (iOS, circle, squircle, themed) there.

const DEFAULT_SRC := "res://assets/source_art/app_icon_v4_source.webp"
const OUT := "res://assets/veya/"
const ART := Rect2i(8, 8, 1238, 1238)
const ART_RADIUS_FRAC := 0.171
const WORK := 1024
## Tile face in WORK pixels: the tile is drawn in perspective, so its top face is a rounded
## quadrilateral (corners TL, TR, BR, BL, measured on the art). The themed-icon layer is the ivory
## face inside it, so the blossom, leaves and buds become the cut-out.
const FACE_QUAD: Array[Vector2] = [Vector2(222, 180), Vector2(634, 84), Vector2(794, 560), Vector2(322, 635)]
const FACE_RADIUS := 45.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src_path: String = ProjectSettings.globalize_path(DEFAULT_SRC) if args.is_empty() else args[0]
	var preview_dir: String = args[1] if args.size() > 1 else ""
	var src := Image.load_from_file(src_path)
	if src == null or src.is_empty():
		push_error("cannot load " + src_path)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var art := src.get_region(ART)
	art.resize(WORK, WORK, Image.INTERPOLATE_LANCZOS)

	# Full-bleed square: the art's rounded corners (and their white fringe) painted in from the
	# neighbouring art. They sit under every store/launcher mask, but must not show white on
	# square launchers.
	var bleed := art.duplicate() as Image
	_fill_corners(bleed, Rect2(0, 0, WORK, WORK), WORK * ART_RADIUS_FRAC + 6.0)
	_save(_resized(bleed, 1024, false), "app_icons/ios/AppIcon_1024.png")
	_save(_resized(bleed, 1024, false), "branding/app_icon_master_1024.png")
	_save(_resized(bleed, 512, false), "app_icons/android/play_store_icon_512.png")

	# The art with a clean rounded alpha edge (legacy launcher / window / favicon).
	var framed := _rounded(art, ART_RADIUS_FRAC + 0.01)
	for d in [["mdpi", 48], ["hdpi", 72], ["xhdpi", 96], ["xxhdpi", 144], ["xxxhdpi", 192]]:
		_save(_resized(framed, d[1], true), "app_icons/android/mipmap-%s/ic_launcher.png" % d[0])
	for s in [180, 192, 512]:
		_save(_resized(framed, s, true), "branding/app_icon_master_%d.png" % s)
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
	var bg := _resized(_resized(bleed, 18, false), 432, false)
	_save(bg, "app_icons/android/adaptive_background_432.png")
	var mono := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	var face := _resized(_face_silhouette(bleed), art_px, true)
	mono.blit_rect(face, Rect2i(Vector2i.ZERO, face.get_size()), at)
	_save(mono, "app_icons/android/adaptive_monochrome_432.png")
	if not preview_dir.is_empty():
		_previews(preview_dir, bleed, framed, fg, bg, mono)
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
	## Anti-aliased rounded-square alpha mask (drops the source's white margin and corners).
	var out := img.duplicate() as Image
	var n := out.get_width()
	var r := n * radius_frac
	for y in n:
		for x in n:
			var cover := clampf(r - _corner_dist(Vector2(x + 0.5, y + 0.5), Rect2(0, 0, n, n), r) + 0.5, 0.0, 1.0)
			if cover < 1.0:
				var c := out.get_pixel(x, y)
				out.set_pixel(x, y, Color(c, minf(c.a, cover)))
	return out


func _corner_dist(p: Vector2, rect: Rect2, r: float) -> float:
	## Distance from the corner-circle centre for points in a corner zone (else 0).
	var dx := maxf(0.0, maxf(rect.position.x + r - p.x, p.x - (rect.end.x - r)))
	var dy := maxf(0.0, maxf(rect.position.y + r - p.y, p.y - (rect.end.y - r)))
	return Vector2(dx, dy).length()


func _fill_corners(img: Image, inner: Rect2, r: float) -> void:
	## Harmonic fill of everything outside the inner rounded rect (white corners, fringe).
	var n := img.get_width()
	var buf: Array[Color] = []
	buf.resize(n * n)
	var hole := PackedByteArray()
	hole.resize(n * n)
	var holes: PackedInt32Array = []
	for y in n:
		for x in n:
			buf[y * n + x] = img.get_pixel(x, y)
			if _corner_dist(Vector2(x + 0.5, y + 0.5), inner, r) > r - 1.0:
				hole[y * n + x] = 1
				holes.append(y * n + x)
	# Seed by nearest known neighbours (onion peel), then relax.
	var known := PackedByteArray()
	known.resize(n * n)
	for i in n * n:
		known[i] = 1 - hole[i]
	var todo := holes.duplicate()
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
		for i in holes:
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
	for i in holes:
		var c := buf[i]
		img.set_pixel(i % n, i / n, Color(c.r, c.g, c.b, 1.0))


func _face_silhouette(bleed: Image) -> Image:
	## Themed-icon layer: the tile face (the rounded quad measured on the art) where it is ivory
	## and connected to the face's edge. The blossom, leaves and buds are cut out, including the
	## pale petal highlights they enclose.
	var n := bleed.get_width()
	var core := _inset_quad(FACE_QUAD, FACE_RADIUS)
	var cover := PackedFloat32Array()
	cover.resize(n * n)
	var ivory := PackedByteArray()
	ivory.resize(n * n)
	var reached := PackedByteArray()
	reached.resize(n * n)
	var queue: PackedInt32Array = []
	for y in n:
		for x in n:
			var sd := _quad_sd(Vector2(x + 0.5, y + 0.5), core) - FACE_RADIUS
			if sd >= 0.5:
				continue
			var i := y * n + x
			cover[i] = clampf(0.5 - sd, 0.0, 1.0)
			var c := bleed.get_pixel(x, y)
			# Ivory: bright, low saturation, warm (petal highlights are pale but pink-hued).
			if c.v > 0.6 and c.s < 0.22 and (c.s < 0.05 or (c.h > 0.04 and c.h < 0.2)):
				ivory[i] = 1
				if sd > -14.0:
					reached[i] = 1
					queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for j in [i + 1, i - 1, i + n, i - n]:
			if j >= 0 and j < n * n and ivory[j] == 1 and reached[j] == 0 and absi((j % n) - (i % n)) <= 1:
				reached[j] = 1
				queue.append(j)
	# Non-ivory areas that touch the edge band are the face's bevel shading, not the blossom.
	var shade: PackedInt32Array = []
	for i in n * n:
		if cover[i] > 0.0 and reached[i] == 0 and _quad_sd(Vector2(i % n + 0.5, i / n + 0.5), core) - FACE_RADIUS > -14.0:
			reached[i] = 1
			shade.append(i)
	head = 0
	while head < shade.size():
		var i := shade[head]
		head += 1
		for j in [i + 1, i - 1, i + n, i - n]:
			if j >= 0 and j < n * n and cover[j] > 0.0 and ivory[j] == 0 and reached[j] == 0 and absi((j % n) - (i % n)) <= 1:
				reached[j] = 1
				shade.append(j)
	# Specks (tiny enclosed non-ivory spots) are filled; only the blossom-sized cut-outs remain.
	var seen := reached.duplicate()
	for s in n * n:
		if cover[s] <= 0.0 or seen[s] == 1:
			continue
		var blob: PackedInt32Array = [s]
		seen[s] = 1
		head = 0
		while head < blob.size():
			var i := blob[head]
			head += 1
			for j in [i + 1, i - 1, i + n, i - n]:
				if j >= 0 and j < n * n and cover[j] > 0.0 and seen[j] == 0 and absi((j % n) - (i % n)) <= 1:
					seen[j] = 1
					blob.append(j)
		if blob.size() < 600:
			for i in blob:
				reached[i] = 1
	var out := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for i in n * n:
		if reached[i] == 1:
			out.set_pixel(i % n, i / n, Color(1, 1, 1, cover[i]))
	return out


func _inward(a: Vector2, b: Vector2) -> Vector2:
	## Inward normal of edge a->b for a quad listed clockwise on screen (y down).
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)


func _inset_quad(q: Array[Vector2], r: float) -> Array[Vector2]:
	## The quad with every edge moved inward by r. Growing it back by r (a disc) gives the quad
	## with corners rounded to radius r.
	var out: Array[Vector2] = []
	for i in q.size():
		var p0 := q[(i + q.size() - 1) % q.size()]
		var p1 := q[i]
		var p2 := q[(i + 1) % q.size()]
		var n0 := _inward(p0, p1)
		var n1 := _inward(p1, p2)
		var hit: Variant = Geometry2D.line_intersects_line(p0 + n0 * r, p1 - p0, p1 + n1 * r, p2 - p1)
		out.append(hit if hit != null else p1)
	return out


func _quad_sd(p: Vector2, q: Array[Vector2]) -> float:
	## Signed distance to a convex quad (negative inside).
	var inside := true
	var nearest := INF
	var depth := INF
	for i in q.size():
		var a := q[i]
		var b := q[(i + 1) % q.size()]
		var s := (p - a).dot(_inward(a, b))
		if s < 0.0:
			inside = false
		depth = minf(depth, s)
		nearest = minf(nearest, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return -depth if inside else nearest


func _previews(dir: String, bleed: Image, framed: Image, fg: Image, bg: Image, mono: Image) -> void:
	## Masked previews for review only (not shipped): iOS-like rounded square, Pixel circle,
	## Samsung-like squircle (adaptive layers through the 72dp viewport), legacy and themed icons.
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 288
	var adaptive := bg.duplicate() as Image
	adaptive.blend_rect(fg, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	var view := adaptive.get_region(Rect2i(72, 72, 288, 288))
	var themed := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	themed.fill(Color(0.16, 0.24, 0.20))
	var tint := mono.duplicate() as Image
	for y in 432:
		for x in 432:
			var c := tint.get_pixel(x, y)
			tint.set_pixel(x, y, Color(0.80, 0.93, 0.85, c.a))
	themed.blend_rect(tint, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	var sheet := Image.create(n * 5 + 60, n + 20, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.93, 0.93, 0.93))
	var tiles := [
		_masked(_resized(bleed, n, false), 0.2237, false),
		_masked(view, 0.5, false),
		_masked(view, 0.32, true),
		_resized(framed, n, true),
		_masked(themed.get_region(Rect2i(72, 72, 288, 288)), 0.5, false),
	]
	for k in tiles.size():
		var t: Image = tiles[k]
		sheet.blend_rect(t, Rect2i(0, 0, n, n), Vector2i(10 + k * (n + 10), 10))
	sheet.save_png(dir.path_join("icon_masks.png"))
	print("preview ", dir.path_join("icon_masks.png"))


func _masked(img: Image, radius_frac: float, squircle: bool) -> Image:
	var out := img.duplicate() as Image
	out.convert(Image.FORMAT_RGBA8)
	var n := out.get_width()
	for y in n:
		for x in n:
			var p := (Vector2(x + 0.5, y + 0.5) / n - Vector2(0.5, 0.5)) * 2.0
			var inside: float
			if squircle:
				inside = clampf((1.0 - pow(pow(absf(p.x), 4.0) + pow(absf(p.y), 4.0), 0.25)) * n * 0.5 + 0.5, 0.0, 1.0)
			else:
				var r := radius_frac * n
				inside = clampf(r - _corner_dist(Vector2(x + 0.5, y + 0.5), Rect2(0, 0, n, n), r) + 0.5, 0.0, 1.0)
			var c := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(c, c.a * inside))
	return out


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
