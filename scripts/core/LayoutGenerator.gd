class_name LayoutGenerator
extends RefCounted
## Procedural, mirror-symmetric layered layouts for daily puzzles and generated levels.
##
## Output positions are in HALF-tile units. Upper layers only sit on cells supported by the
## layer below. Optionally a centred "cap" tile is placed at a half-tile offset to exercise
## partial-overlap geometry. All randomness comes from SeededRng so a seed always reproduces
## the same layout.
##
## generate() / generate_ex() are kept for reproducing older content. Content since 2026-10-19
## (levels 4-150, "daily-4") uses generate_dense(): boards sized to FILL the phone's play area
## in both directions, stacked 1-5 layers deep, with whole layers optionally shifted by half a
## tile (the brick look of popular tile-match games).

const VERSION := "layout-1"
const DENSE_VERSION := "dense-1"

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


# --- dense, screen-filling layouts ------------------------------------------------------

static func rows_to_fill(cols: int, layers: int, area: Vector2 = BoardFit.REFERENCE_AREA) -> int:
	## How many rows make a `cols`-wide board as tall as the area allows at the tile size its
	## width gives: the board then fills BOTH the width and the height of the screen.
	var w_units := (cols - 1) * BoardFit.STEP_X + 1.0 + (layers - 1) * absf(BoardFit.LAYER_DX)
	var tw := minf(area.x / w_units, BoardFit.MAX_TILE_W)
	var h_units := area.y / tw / BoardFit.ASPECT
	return maxi(3, int(floor((h_units - 1.0 - (layers - 1) * absf(BoardFit.LAYER_DY)) / BoardFit.STEP_Y)) + 1)


static func generate_dense(rng: SeededRng, target_tiles: int, cols: int, layers: int, params: Dictionary = {}) -> Array:
	## Positions (half-tile units) for a mirror-symmetric board of `cols` columns and the rows
	## that fill the play area. The base layer always reaches the first and last row and column,
	## so the board's extent is the full grid however few tiles it has. Upper layers sit only
	## where they are fully supported; each one may be shifted by half a tile.
	## params: base_share (0..1, share of tiles on the ground), offset_prob (chance a layer is
	## half-shifted), area (Vector2).
	var area: Vector2 = params.get("area", BoardFit.REFERENCE_AREA)
	var rows := rows_to_fill(cols, layers, area)
	var cells := cols * rows
	var base_target := clampi(int(round(target_tiles * float(params.get("base_share", 0.55 if layers > 1 else 1.0)))), mini(cells, 8), cells)
	var p0 := clampf(float(base_target) / float(cells), 0.2, 1.0)
	var half_cols := int(ceil(cols / 2.0))
	var base := {}
	for y in rows:
		for x in half_cols:
			if rng.rand_float() < p0:
				_put_mirror(base, Vector2i(x * 2, y * 2), cols)
	# Anchor the extent: a tile on the outer columns, and on the first and last rows.
	_put_mirror(base, Vector2i(0, rng.rand_int(1, rows - 2) * 2), cols)
	_put_mirror(base, Vector2i(rng.rand_int(0, half_cols - 1) * 2, 0), cols)
	_put_mirror(base, Vector2i(rng.rand_int(0, half_cols - 1) * 2, (rows - 1) * 2), cols)
	var layer_sets: Array = [base]
	var total := base.size()
	var offset_prob := float(params.get("offset_prob", 0.45))
	for z in range(1, layers):
		if total >= target_tiles:
			break
		var below: Dictionary = layer_sets[z - 1]
		var ox := 1 if rng.rand_float() < offset_prob else 0
		var oy := 1 if rng.rand_float() < offset_prob * 0.6 else 0
		var cand: Array[Vector2i] = []
		for hy in range(oy, (rows - 1) * 2 + 1, 2):
			for hx in range(ox, cols - 1 + 1, 2):  # left half incl. the axis; mirrored below
				var c := Vector2i(hx, hy)
				if _fully_supported(c, below) and _fully_supported(Vector2i(2 * (cols - 1) - hx, hy), below):
					cand.append(c)
		if cand.is_empty():
			break
		var need := target_tiles - total
		var q := clampf(float(need) / float(maxi(1, cand.size() * 2)), 0.25, 0.95)
		var layer := {}
		for c in cand:
			if rng.rand_float() < q:
				_put_mirror(layer, c, cols)
		if layer.is_empty():
			_put_mirror(layer, cand[rng.rand_int(0, cand.size() - 1)], cols)
		layer_sets.append(layer)
		total += layer.size()
	var positions: Array = []
	for z in layer_sets.size():
		for c in layer_sets[z]:
			positions.append(Vector3i(c.x, c.y, z))
	positions.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z > b.z
		return a.y * 1000 + a.x < b.y * 1000 + b.x)
	if positions.size() % 2 != 0:
		positions.remove_at(0)  # a top-layer tile: never leaves anything unsupported
	return positions


static func _put_mirror(layer: Dictionary, c: Vector2i, cols: int) -> void:
	layer[c] = true
	layer[Vector2i(2 * (cols - 1) - c.x, c.y)] = true


static func _fully_supported(c: Vector2i, below: Dictionary) -> bool:
	## Every quarter of the tile's footprint rests on a tile of the layer below.
	for q in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var covered := false
		for bx in [c.x + q.x - 1, c.x + q.x]:
			for by in [c.y + q.y - 1, c.y + q.y]:
				if below.has(Vector2i(bx, by)):
					covered = true
		if not covered:
			return false
	return true


static func fill_ratio(positions: Array, area: Vector2 = BoardFit.REFERENCE_AREA) -> Vector2:
	## Share of the area's width and height the board covers at its fitted tile size.
	var geo := BoardGeometry.from_positions(positions)
	var u := BoardFit.board_units(geo)
	var tw := BoardFit.fit_tile_width(geo, area)
	return Vector2(u.x * tw / area.x, u.y * tw / area.y)
