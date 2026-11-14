extends SceneTree
## Draws the Settings gear icon (emerald + ivory, 96 px) so it reads as a gear at small sizes
## (the pack's scalloped ring read as a plain circle). The colour of each variant is sampled from
## the pack's own settings icon, so it matches the rest of the set.
##   godot --headless --path . -s res://tools/make_gear_icon.gd

const SIZE := 96
const SS := 4             ## supersampling for smooth edges
const TEETH := 8
const R_TIP := 0.46       ## of SIZE
const R_BODY := 0.34
const R_HOLE := 0.15
const TOOTH := 0.42       ## angular width of a tooth, as a share of its slot


func _initialize() -> void:
	for variant in ["emerald", "ivory"]:
		var path := "res://art/lishi_v2/ui/icons/%s/settings.png" % variant
		var src := Image.load_from_file(ProjectSettings.globalize_path(path))
		var col := _ink(src)
		var big := Image.create(SIZE * SS, SIZE * SS, false, Image.FORMAT_RGBA8)
		var c := SIZE * SS * 0.5
		for y in SIZE * SS:
			for x in SIZE * SS:
				var dx := (x + 0.5 - c) / (SIZE * SS)
				var dy := (y + 0.5 - c) / (SIZE * SS)
				var r := sqrt(dx * dx + dy * dy)
				var a := fposmod(atan2(dy, dx) + PI / TEETH, TAU / TEETH) / (TAU / TEETH)
				var tooth := absf(a - 0.5) < TOOTH * 0.5
				var inside := (r < R_BODY or (tooth and r < R_TIP)) and r > R_HOLE
				big.set_pixel(x, y, col if inside else Color(col, 0.0))
		big.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		big.save_png(ProjectSettings.globalize_path(path))
		print("gear -> ", path, " ", col)
	quit()


static func _ink(img: Image) -> Color:
	## The most opaque, most common colour of the old icon.
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.95:
				var key := Color(snappedf(p.r, 0.05), snappedf(p.g, 0.05), snappedf(p.b, 0.05))
				counts[key] = int(counts.get(key, 0)) + 1
	var best := Color.BLACK
	var n := -1
	for k in counts:
		if counts[k] > n:
			n = counts[k]
			best = k
	return best
