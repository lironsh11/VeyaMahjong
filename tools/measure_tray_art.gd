extends SceneTree
## Measures the slot wells of the tray frames so tiles sit exactly inside the painted slots.
##   godot --headless --path . -s res://tools/measure_tray_art.gd
## Input: res://art/lishi_v2/ui/tray/tray_{4,5,6}.png (built by tools/make_tray_art.gd from the owner's
## premium 5-slot tray, 256 px high, transparent). Output: res://data/config/tray_slots.json (data/ JSON ships in exports) with,
## per capacity, the image size and each slot's rect in image pixels (left to right).
##
## Method: along the middle row, runs of dark-green well pixels mark the slots; each run is
## flood-filled (same colour test) and its bounding box is the well, including its dark outline.
## The frame band between wells is a lighter green and the separators are gold, so fills never
## leak from one well into the next.

const DIR := "res://art/lishi_v2/ui/tray/"
const CAPS := [4, 5, 6]
const SLOTS_JSON := "res://data/config/tray_slots.json"


func _is_well(c: Color) -> bool:
	return c.a > 0.9 and c.r < 0.12 and c.g < 0.47 and c.b < 0.38


func _init() -> void:
	var meta := {}
	for cap in CAPS:
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + "tray_%d.png" % cap))
		var w := img.get_width()
		var h := img.get_height()
		var my := h / 2
		var seeds: Array[int] = []
		var run_start := -1
		for x in w + 1:
			var inside := x < w and _is_well(img.get_pixel(x, my))
			if inside and run_start < 0:
				run_start = x
			elif not inside and run_start >= 0:
				if x - run_start > 40:
					seeds.append((run_start + x - 1) / 2)
				run_start = -1
		var slots: Array = []
		for sx in seeds:
			slots.append(_fill_bounds(img, Vector2i(sx, my)))
		if slots.size() != cap:
			push_error("tray_%d: found %d slots, expected %d" % [cap, slots.size(), cap])
		meta[str(cap)] = {"size": [w, h], "slots": slots}
		print("tray_%d %dx%d slots %s" % [cap, w, h, str(slots)])
	var f := FileAccess.open(SLOTS_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "", false) + "\n")
	quit()


func _fill_bounds(img: Image, seed: Vector2i) -> Array:
	## 4-connected flood fill over well pixels; returns [x, y, w, h].
	var seen := {}
	var stack: Array[Vector2i] = [seed]
	var lo := seed
	var hi := seed
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if seen.has(p) or p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
			continue
		if not _is_well(img.get_pixelv(p)):
			continue
		seen[p] = true
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
		hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
		stack.append(p + Vector2i.RIGHT)
		stack.append(p + Vector2i.LEFT)
		stack.append(p + Vector2i.DOWN)
		stack.append(p + Vector2i.UP)
	return [lo.x, lo.y, hi.x - lo.x + 1, hi.y - lo.y + 1]
