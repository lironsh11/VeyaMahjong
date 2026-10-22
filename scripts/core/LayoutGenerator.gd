class_name LayoutGenerator
extends RefCounted
## Procedural, mirror-symmetric layered layouts for daily puzzles and generated levels.
##
## Output positions are in HALF-tile units. Upper layers only sit on cells supported by the
## layer below. Optionally a centred "cap" tile is placed at a half-tile offset to exercise
## partial-overlap geometry. All randomness comes from SeededRng so a seed always reproduces
## the same layout.
##
## generate() / generate_ex() are kept for reproducing older content and the content sample in
## tools/validate_content.gd. Shipped levels 4-300 and daily boards since 2026-10-22 ("tpl-1",
## "daily-5") are layered structures from LayoutTemplates (pyramid, turtle, bridge...); the
## "dense" grids of 2026-10-19 are gone with them.

const VERSION := "layout-1"

const DEFAULTS := {
	"min_cols": 5, "max_cols": 8, "min_rows": 5, "max_rows": 8,
	"fill_base": 0.95, "fill_falloff": 0.55,
	"upper_prob": 0.75, "max_layers": 4, "support": "cross", "cap_prob": 0.5,
}


static func generate(rng: SeededRng, target_tiles: int, max_cols: int = 8, max_rows: int = 8) -> Array:
	var p := DEFAULTS.duplicate()
	p.max_cols = max_cols
	p.max_rows = max_rows
	return generate_ex(rng, target_tiles, p)


static func generate_ex(rng: SeededRng, target_tiles: int, params: Dictionary) -> Array:
	## params (see DEFAULTS): support "cross" = an upper tile needs neighbours on all four sides
	## below it (pyramids); "row" = only left and right (taller ridges, more stacking).
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var max_cols: int = p.max_cols
	var max_rows: int = p.max_rows
	var cols := clampi(rng.rand_int(int(p.min_cols), max_cols), 4, max_cols)
	var rows := clampi(rng.rand_int(int(p.min_rows), max_rows), 4, max_rows)
	var half_cols := int(ceil(cols / 2.0))
	# Layer 0: random symmetric mask, biased to a filled centre.
	var base := {}
	for y in rows:
		for x in half_cols:
			var cx := absf(x - (cols - 1) / 2.0) / maxf(1.0, cols / 2.0)
			var cy := absf(y - (rows - 1) / 2.0) / maxf(1.0, rows / 2.0)
			var prob: float = float(p.fill_base) - float(p.fill_falloff) * maxf(cx, cy)
			if rng.rand_float() < prob:
				base[Vector2i(x, y)] = true
				base[Vector2i(cols - 1 - x, y)] = true
	var layers: Array = [base]
	# Upper layers: subsets of supported cells of the layer below.
	var total := base.size()
	var z := 1
	var cross: bool = str(p.support) == "cross"
	while total < target_tiles and z < int(p.max_layers):
		var below: Dictionary = layers[z - 1]
		var layer := {}
		for c in below:
			var cell: Vector2i = c
			if cell.x > (cols - 1) / 2.0:
				continue
			var interior := below.has(cell + Vector2i(1, 0)) and below.has(cell + Vector2i(-1, 0))
			if cross:
				interior = interior and below.has(cell + Vector2i(0, 1)) and below.has(cell + Vector2i(0, -1))
			if interior and rng.rand_float() < float(p.upper_prob):
				layer[cell] = true
				layer[Vector2i(cols - 1 - cell.x, cell.y)] = true
		if layer.is_empty():
			break
		layers.append(layer)
		total += layer.size()
		z += 1
	var positions: Array = []
	for lz in layers.size():
		for c in layers[lz]:
			positions.append(Vector3i(c.x * 2, c.y * 2, lz))
	positions.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z > b.z
		return a.y * 100 + a.x < b.y * 100 + b.x)
	var top_z: int = layers.size() - 1
	var cap_ok := rng.rand_float() < float(p.cap_prob) and top_z >= 1
	if cap_ok:
		# Half-offset cap centred over a 2x2 block on the top layer, if one exists.
		var top: Dictionary = layers[top_z]
		for c in top:
			var cell: Vector2i = c
			if top.has(cell + Vector2i(1, 0)) and top.has(cell + Vector2i(0, 1)) and top.has(cell + Vector2i(1, 1)):
				positions.append(Vector3i(cell.x * 2 + 1, cell.y * 2 + 1, top_z + 1))
				break
	if positions.size() % 2 != 0:
		var idx := _removable_ground_index(positions)
		if idx >= 0:
			positions.remove_at(idx)
		else:
			positions.remove_at(0)  # topmost tile (sorted first); never unsupported
	return positions


static func _removable_ground_index(positions: Array) -> int:
	## Last ground tile that supports nothing above it (prefers the symmetry axis).
	for k in range(positions.size() - 1, -1, -1):
		var g: Vector3i = positions[k]
		if g.z != 0:
			continue
		var supports := false
		for q in positions:
			if q.z == 1 and absi(q.x - g.x) < TileModel.W and absi(q.y - g.y) < TileModel.H:
				supports = true
				break
		if not supports:
			return k
	return -1


# --- screen fill ---------------------------------------------------------------------------

static func fill_ratio(positions: Array, area: Vector2 = BoardFit.REFERENCE_AREA) -> Vector2:
	## Share of the area's width and height the board covers at its fitted tile size.
	var geo := BoardGeometry.from_positions(positions)
	var u := BoardFit.board_units(geo)
	var tw := BoardFit.fit_tile_width(geo, area)
	return Vector2(u.x * tw / area.x, u.y * tw / area.y)
