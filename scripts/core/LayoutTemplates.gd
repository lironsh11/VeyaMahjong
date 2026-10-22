class_name LayoutTemplates
extends RefCounted
## Layered Mahjong Solitaire structures for generated levels and daily boards (since 2026-10-22).
##
## A board is built in three deterministic steps (SeededRng: a seed always gives the same board):
##   1. GROUND: the family's base shape on a cols x rows grid that fills the play area:
##        pyramid, ziggurat, twin, brick, terraces, ridge - the full grid
##        turtle - a body with a head, a tail and flippers set half a tile off the body rows
##        bridge - two piers and a centre channel, crossed by decks one layer up
##        cross  - two crossing bars
##        frame  - a ring (one or two tiles thick) around an open courtyard
##   2. LAYERS: each upper layer is derived from the one below by an explicit rule:
##        stagger   - shifted half a tile across and down: each tile sits on the corner of four
##        stagger_x - shifted half a tile sideways: each tile straddles two lower tiles
##        stagger_y - shifted half a tile down: each tile straddles two lower tiles
##        chain     - stagger where four tiles meet, else stagger_x / stagger_y (thin runs)
##        shrink    - aligned, only over tiles with neighbours all round (a smaller tier)
##        same      - aligned, one tile straight on each tile (towers, walls)
##      A tile is only placed where it rests on the layer below (all four quarters of it; two for
##      a bridge deck spanning a gap) and where it overlaps no tile of its own layer. Shifts
##      alternate direction from layer to layer, so tiers stay centred, and every rule keeps the
##      board mirror-symmetric left to right.
##   3. CARVE down to the wanted tile count by removing mirror pairs of uncovered tiles (never a
##      tile another rests on, never the last tile on an edge of the board), from the top ("top":
##      lower, flatter boards) or from the outside in ("edge": eroded terraces).
## Positions are half-tile units (TileModel: a tile is 2x2), so every shift above is real
## geometry: the rules engine (BoardGeometry) blocks exactly what the player sees covering.

const VERSION := "tpl-1"
const FAMILIES: PackedStringArray = ["pyramid", "ziggurat", "turtle", "bridge", "cross", "twin", "frame", "brick", "terraces", "ridge"]
const MODES: PackedStringArray = ["top", "edge"]
const QUARTERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]


class Build:
	## A structure being built: tiles and occupied half-unit cells, per layer.
	var cols: int
	var rows: int
	var layers: Array[Dictionary] = []  ## Vector2i -> true (tile positions)
	var cells: Array[Dictionary] = []   ## Vector2i -> true (half-unit cells covered)
	var shift := Vector2i.ZERO          ## accumulated half-tile offset of the last layer

	func _init(p_cols: int, p_rows: int) -> void:
		cols = p_cols
		rows = p_rows

	func layer(z: int) -> Dictionary:
		while layers.size() <= z:
			layers.append({})
			cells.append({})
		return layers[z]

	func mirror(p: Vector2i) -> Vector2i:
		return Vector2i(2 * cols - 2 - p.x, p.y)

	func support(p: Vector2i, z: int) -> int:
		## How many quarters of a tile at p on layer z rest on layer z - 1 (4 on the ground).
		if z == 0:
			return 4
		layer(z - 1)
		var n := 0
		for q in QUARTERS:
			if cells[z - 1].has(p + q):
				n += 1
		return n

	func fits(p: Vector2i, z: int, min_support: int) -> bool:
		if p.x < 0 or p.y < 0 or p.x > 2 * cols - 2 or p.y > 2 * rows - 2:
			return false
		layer(z)
		for q in QUARTERS:
			if cells[z].has(p + q):
				return false
		return support(p, z) >= min_support

	func put_pair(p: Vector2i, z: int, min_support: int = 4) -> bool:
		## Places p and its mirror image together (mirror x positions differ by an even number of
		## half units, so the two never overlap each other).
		var m := mirror(p)
		if not fits(p, z, min_support) or (m != p and not fits(m, z, min_support)):
			return false
		for t in ([p] if m == p else [p, m]):
			layers[z][t] = true
			for q in QUARTERS:
				cells[z][t + q] = true
		return true

	func rect(z: int, x0: int, y0: int, c: int, r: int) -> void:
		for j in r:
			for i in c:
				put_pair(Vector2i(x0 + 2 * i, y0 + 2 * j), z)

	func positions() -> Array:
		var out: Array = []
		for z in layers.size():
			var ks: Array = layers[z].keys()
			ks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
			for p in ks:
				out.append(Vector3i(p.x, p.y, z))
		return out

	func count() -> int:
		var n := 0
		for l in layers:
			n += l.size()
		return n


static func _step(b: Build, axis_x: bool, axis_y: bool) -> Vector2i:
	## Next half-tile shift: back towards the centre if the last layer was already shifted.
	var s := Vector2i.ZERO
	if axis_x:
		s.x = 1 if b.shift.x == 0 else -1
	if axis_y:
		s.y = 1 if b.shift.y == 0 else -1
	b.shift += s
	return s


static func _in(c: Vector2i, regions: Array) -> bool:
	if regions.is_empty():
		return true
	for r in regions:
		var box: Rect2i = r
		if box.has_point(c) and box.has_point(c + Vector2i(1, 1)):
			return true
	return false


static func apply_rule(b: Build, rule: String, z: int, regions: Array = [], min_support: int = 4) -> int:
	## Derives layer z from layer z - 1 with `rule` (see the class doc). Returns tiles placed.
	var below: Dictionary = b.layer(z - 1)
	var keys: Array = below.keys()
	keys.sort_custom(func(u: Vector2i, v: Vector2i) -> bool: return u.x < v.x or (u.x == v.x and u.y < v.y))
	var before := b.layer(z).size()
	var s := Vector2i.ZERO
	match rule:
		"stagger", "chain":
			s = _step(b, true, true)
		"stagger_x":
			s = _step(b, true, false)
		"stagger_y":
			s = _step(b, false, true)
	for p in keys:
		var cands: Array[Vector2i] = []
		match rule:
			"stagger", "stagger_x", "stagger_y":
				cands.append(p + s)
			"chain":
				cands.append_array([p + s, p + Vector2i(s.x, 0), p + Vector2i(0, s.y)])
			"same":
				cands.append(p)
			"shrink":
				if below.has(p + Vector2i(2, 0)) and below.has(p - Vector2i(2, 0)) and below.has(p + Vector2i(0, 2)) and below.has(p - Vector2i(0, 2)):
					cands.append(p)
		for c in cands:
			if _in(c, regions) and b.put_pair(c, z, min_support):
				break
	return b.layer(z).size() - before


static func structure(family: String, cols: int, rows: int, layers: int, rng: SeededRng) -> Build:
	## The full (uncarved) structure of a family on a cols x rows ground grid, `layers` high.
	var b := Build.new(cols, rows)
	var w := 2 * cols  # board width in half units
	var h := 2 * rows
	match family:
		"pyramid":
			b.rect(0, 0, 0, cols, rows)
			for z in range(1, layers):
				apply_rule(b, "stagger", z)
		"ziggurat":
			# Aligned tiers, each a ring smaller, crowned by a staggered cap.
			b.rect(0, 0, 0, cols, rows)
			for z in range(1, layers):
				apply_rule(b, "stagger" if z == layers - 1 else "shrink", z)
		"brick":
			# Bricks: every layer straddles pairs, alternately sideways and lengthways.
			b.rect(0, 0, 0, cols, rows)
			for z in range(1, layers):
				apply_rule(b, "stagger_x" if z % 2 == 1 else "stagger_y", z)
		"terraces":
			# A stepped pyramid whose every staggered tier is two tiles high.
			b.rect(0, 0, 0, cols, rows)
			for z in range(1, layers):
				apply_rule(b, "stagger" if z % 2 == 1 else "same", z)
		"ridge":
			# Long roofs: every layer straddles pairs sideways, rising to a ridge down the middle.
			b.rect(0, 0, 0, cols, rows)
			for z in range(1, layers):
				apply_rule(b, "stagger_x", z)
		"twin":
			# Two staggered pyramids, upper and lower half, on one floor.
			b.rect(0, 0, 0, cols, rows)
			var top_rows := int(rows / 2.0)
			var regions := [Rect2i(0, 0, w, 2 * top_rows), Rect2i(0, h - 2 * top_rows, w, 2 * top_rows)]
			for z in range(1, layers):
				apply_rule(b, "stagger", z, regions)
		"turtle":
			b.rect(0, 2, 2, cols - 2, rows - 2)                    # body
			b.put_pair(Vector2i(cols - 1, 0), 0)                   # head (half off the columns when cols is even)
			b.put_pair(Vector2i(cols - 1, h - 2), 0)               # tail
			var flips := [3, h - 5] if rows < 9 or rng.rand_float() < 0.5 else [3, 5, h - 7, h - 5]
			for fy in flips:
				b.put_pair(Vector2i(0, fy), 0)                     # flippers, half off the body rows
			if layers > 1:
				apply_rule(b, "same", 1, [Rect2i(2, 4, w - 4, h - 8)])  # the shell
			for z in range(2, layers):
				apply_rule(b, "stagger", z)
		"bridge":
			_bridge(b, layers, rng)
		"cross":
			var bw := 2 if cols % 2 == 0 else (1 if rng.rand_float() < 0.5 else 3)
			var bh := 2 if rows % 2 == 0 else (1 if rng.rand_float() < 0.5 else 3)
			b.rect(0, cols - bw, 0, bw, rows)
			b.rect(0, 0, rows - bh, cols, bh)
			for z in range(1, layers):
				apply_rule(b, "chain", z)
		"frame":
			var t := 2 if cols >= 6 and rng.rand_float() < 0.6 else 1
			b.rect(0, 0, 0, cols, t)
			b.rect(0, 0, h - 2 * t, cols, t)
			b.rect(0, 0, 2 * t, t, rows - 2 * t)
			for z in range(1, layers):
				apply_rule(b, "chain" if z < 3 else "same", z)
		_:
			push_error("unknown layout family %s" % family)
	return b


static func _bridge(b: Build, layers: int, rng: SeededRng) -> void:
	## Two piers (left and right) and a channel down the middle; decks one layer up span the gaps
	## resting half on a pier and half on the channel, and the piers rise in staggered tops.
	var cols := b.cols
	var pw := 2 if cols >= 6 else 1
	var w := 2 * cols
	var h := 2 * b.rows
	b.rect(0, 0, 0, pw, b.rows)
	for y in range(0, h - 1, 2):
		b.put_pair(Vector2i(cols - 1, y), 0)  # channel, centred
	var n_decks := 2 if b.rows < 9 or rng.rand_float() < 0.5 else 3
	var deck_rows: Array[int] = []
	var q := int(round(b.rows / 4.0))
	deck_rows.append(2 * q)
	deck_rows.append(h - 2 - 2 * q)
	if n_decks == 3:
		deck_rows.append(2 * int((b.rows - 1) / 2.0))
	var piers := [Rect2i(0, 0, 2 * pw, h), Rect2i(w - 2 * pw, 0, 2 * pw, h)]
	var decks: Array = []
	for dy in deck_rows:
		decks.append(Rect2i(0, dy, w, 2))
	if layers < 2:
		return
	# Layer 1: decks first (left half; put_pair mirrors them), then the pier tops.
	for dy in deck_rows:
		for x in range(2 * pw - 1, cols, 2):
			b.put_pair(Vector2i(x, dy), 1, 2)
	apply_rule(b, "stagger" if pw == 2 else "stagger_y", 1, piers)
	for z in range(2, layers):
		var shift := b.shift
		apply_rule(b, "stagger_x", z, decks)
		b.shift = shift
		apply_rule(b, "stagger_y" if pw == 1 or z % 2 == 0 else "stagger", z, piers)


static func carve(positions: Array, target: int, cols: int, mode: String, rng: SeededRng) -> Array:
	## Removes uncovered tiles, in mirror pairs, until `target` remain (see the class doc).
	## Returns [] when the structure has fewer tiles or cannot be carved that far.
	if positions.size() < target or target <= 0:
		return []
	var geo := BoardGeometry.from_positions(positions)
	var n := geo.count
	var cover := PackedInt32Array()
	var mate := PackedInt32Array()
	var jitter := PackedFloat32Array()
	cover.resize(n)
	mate.resize(n)
	jitter.resize(n)
	for i in n:
		cover[i] = geo.above[i].size()
		mate[i] = int(geo.index_by_pos.get(BoardGeometry.pos_key(2 * cols - 2 - geo.gx[i], geo.gy[i], geo.gz[i]), -1))
		jitter[i] = rng.rand_float() * 0.15
	var gone := PackedByteArray()
	gone.resize(n)
	gone.fill(0)
	# Extent anchors: the board keeps tiles on all four edges of its ground grid.
	var edge := [0, 0, 0, 0]  # left, right, top, bottom
	for i in n:
		_edge_add(geo, i, edge, 1)
	var cx := (geo.min_gx + geo.max_gx) * 0.5
	var cy := (geo.min_gy + geo.max_gy) * 0.5
	var hw := maxf(1.0, (geo.max_gx - geo.min_gx) * 0.5)
	var hh := maxf(1.0, (geo.max_gy - geo.min_gy) * 0.5)
	var remaining := n
	var singles := false
	while remaining > target:
		var best := -1
		var best_p := -INF
		for i in n:
			if gone[i] != 0 or cover[i] > 0:
				continue
			var group: Array[int] = [i]
			var m := mate[i]
			if not singles and m >= 0 and m != i:
				if gone[m] != 0 or cover[m] > 0:
					continue
				group.append(m)
			if remaining - group.size() < target or not _keeps_edges(geo, group, edge):
				continue
			var dx := absf(geo.gx[i] - cx) / hw
			var dy := absf(geo.gy[i] - cy) / hh
			var d := 0.5 * maxf(dx, dy) + 0.5 * sqrt((dx * dx + dy * dy) * 0.5)
			var p := geo.gz[i] * 2.0 + d if mode == "top" else d * 2.0 + geo.gz[i] * 0.25
			p += jitter[i]
			if p > best_p:
				best_p = p
				best = i
		if best < 0:
			if singles:
				return []
			singles = true  # odd structure or no symmetric pair left: allow one lone tile
			continue
		var picked: Array[int] = [best]
		if not singles and mate[best] >= 0 and mate[best] != best:
			picked.append(mate[best])
		for t in picked:
			gone[t] = 1
			remaining -= 1
			_edge_add(geo, t, edge, -1)
			for u in geo.below[t]:
				cover[u] -= 1
		singles = false
	var out: Array = []
	for i in n:
		if gone[i] == 0:
			out.append(Vector3i(geo.gx[i], geo.gy[i], geo.gz[i]))
	return out


static func _edge_add(geo: BoardGeometry, i: int, edge: Array, d: int) -> void:
	if geo.gx[i] == geo.min_gx:
		edge[0] += d
	if geo.gx[i] == geo.max_gx:
		edge[1] += d
	if geo.gy[i] == geo.min_gy:
		edge[2] += d
	if geo.gy[i] == geo.max_gy:
		edge[3] += d


static func _keeps_edges(geo: BoardGeometry, group: Array[int], edge: Array) -> bool:
	var e := edge.duplicate()
	for t in group:
		_edge_add(geo, t, e, -1)
	return e[0] > 0 and e[1] > 0 and e[2] > 0 and e[3] > 0


static func generate(rng: SeededRng, family: String, target: int, cols: int, layers: int, mode: String = "top", area: Vector2 = BoardFit.REFERENCE_AREA) -> Array:
	## Positions (half units) of a `family` board with exactly `target` tiles on a `cols`-wide
	## grid with the rows that fill `area`, at most `layers` high. [] if the family cannot reach
	## `target` tiles at that size.
	var b := structure(family, cols, BoardFit.rows_to_fill(cols, area), layers, rng)
	return carve(b.positions(), target, cols, mode, rng)


static func capacity(family: String, cols: int, layers: int, area: Vector2 = BoardFit.REFERENCE_AREA) -> int:
	## Tiles in the uncarved structure (a fixed rng: only bridge/turtle/cross/frame details vary).
	return structure(family, cols, BoardFit.rows_to_fill(cols, area), layers, SeededRng.new(1)).count()


static func pick(rng: SeededRng, target: int, cols: int, min_layers: int, max_layers: int, caps: Dictionary, families: PackedStringArray = FAMILIES) -> Dictionary:
	## A random family and height whose full structure holds `target` tiles without carving away
	## more than about half of it, built and carved: {"positions", "family", "layers", "mode"},
	## or {} if none fits or the carved board ended up lower than `min_layers`. `caps` is the
	## caller's capacity cache (tools build thousands of candidates).
	var opts: Array = []
	for f in families:
		for l in range(min_layers, max_layers + 1):
			var key := "%s|%d|%d" % [f, cols, l]
			if not caps.has(key):
				caps[key] = capacity(f, cols, l)
			if int(caps[key]) >= target and int(caps[key]) <= target * 2.2:
				opts.append([f, l])
	if opts.is_empty():
		return {}
	var o: Array = opts[rng.rand_int(0, opts.size() - 1)]
	var mode: String = MODES[rng.rand_int(0, MODES.size() - 1)]
	var pos := generate(rng, o[0], target, cols, o[1], mode)
	if pos.is_empty() or layer_count(pos) < min_layers:
		return {}
	return {"positions": pos, "family": o[0], "layers": o[1], "mode": mode}


static func layer_count(positions: Array) -> int:
	var top := -1
	for p in positions:
		top = maxi(top, p.z)
	return top + 1
