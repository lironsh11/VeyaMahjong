extends SceneTree
## Renders the stacked game logo ("LiShi" / "MAHJONG" under the pink blossom) to PNG.
##   godot --path . --resolution 600x370 -s res://tools/make_logo.gd
## Needs a rendering window (not --headless). Deterministic for a given Godot version + fonts.
##
## Composition mirrors the asset pack's original stacked logo: the blossom is cropped from the
## pack's logo artwork (it contains no text), the wordmark is set in Noto Serif (SIL OFL,
## assets/source_art/NotoSerif-Variable.ttf - used only to render this image, not shipped) and the
## subtitle in Rubik (the game's UI font).
## Outputs: res://assets/veya/branding/lishi_logo_stacked_{dark,light}.png (600x370, transparent)

const NAME := "LiShi"
const SUBTITLE := "MAHJONG"
const SIZE := Vector2i(600, 370)
const PACK_LOGO := "res://VeyaMahjong_AssetPack_v1/branding/veya_logo_stacked_dark.png"
const SERIF := "res://assets/source_art/NotoSerif-Variable.ttf"
const SANS := "res://assets/fonts/Rubik-Variable.ttf"
const OUT_DIR := "res://assets/veya/branding/"


func _initialize() -> void:
	# The project uses low-processor mode (redraw only on change); rendering to file needs frames.
	OS.low_processor_usage_mode = false
	var flower := _blossom()
	var serif := _font(SERIF, 430)
	var sans := _font(SANS, 400)
	for variant in [["dark", Color("153D56")], ["light", Color("FFF8EC")]]:
		var vp := SubViewport.new()
		vp.size = SIZE
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var canvas := Control.new()
		canvas.size = Vector2(SIZE)
		vp.add_child(canvas)
		var tr := TextureRect.new()
		canvas.add_child(tr)
		tr.texture = ImageTexture.create_from_image(flower)
		tr.size = Vector2(flower.get_size())
		tr.position = Vector2((SIZE.x - flower.get_width()) / 2.0, 30)
		_label(canvas, NAME, serif, 150, variant[1], Rect2(0, 98, SIZE.x, 200))
		_label(canvas, SUBTITLE, sans, 40, variant[1], Rect2(0, 278, SIZE.x, 60), 6)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path := OUT_DIR + "lishi_logo_stacked_%s.png" % variant[0]
		img.save_png(ProjectSettings.globalize_path(path))
		print("wrote ", path, " ", img.get_size())
		vp.queue_free()
	quit()


func _blossom() -> Image:
	## Crops the flower (opaque pixels above the wordmark) from the pack logo.
	var src := Image.load_from_file(ProjectSettings.globalize_path(PACK_LOGO))
	src.convert(Image.FORMAT_RGBA8)
	var r := Rect2i()
	var found := false
	for y in 135:
		for x in src.get_width():
			if src.get_pixel(x, y).a > 0.02:
				if not found:
					r = Rect2i(x, y, 1, 1)
					found = true
				else:
					r = r.expand(Vector2i(x, y))
	r.size += Vector2i(1, 1)
	return src.get_region(r)


func _font(path: String, weight: int) -> Font:
	var base: FontFile = load(path) if ResourceLoader.exists(path) else null
	if base == null:
		base = FontFile.new()
		base.load_dynamic_font(ProjectSettings.globalize_path(path))
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return v


func _label(parent: Control, text: String, font: Font, size: int, color: Color, rect: Rect2, spacing: int = 0) -> void:
	var l := Label.new()
	parent.add_child(l)
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = font
		fv.spacing_glyph = spacing
		l.add_theme_font_override("font", fv)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = rect.position
	l.size = rect.size
