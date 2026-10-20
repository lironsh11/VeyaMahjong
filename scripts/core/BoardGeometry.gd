class_name BoardGeometry
extends RefCounted
## Immutable spatial relationships between tile slots, computed once per layout.
##
## Freedom rule (traditional Mahjong Solitaire):
##   A tile is FREE when (a) no tile on any higher layer overlaps its footprint, and
##   (b) its left side OR its right side is unobstructed on its own layer.
## A same-layer neighbour obstructs a side when it touches that edge (gx differs by exactly
## one tile width) and the two footprints share some vertical extent. With half-unit
## coordinates this correctly handles rows that are offset by half a tile.
##
## Geometry is shared (read-only) between BoardState clones, so it is safe to read from a
## worker thread while the UI thread holds a different BoardState.

var count: int = 0
var gx := PackedInt32Array()
var gy := PackedInt32Array()
var gz := PackedInt32Array()
var above: Array[PackedInt32Array] = []  ## tiles that cover tile i
var below: Array[PackedInt32Array] = []  ## tiles that tile i covers
var left: Array[PackedInt32Array] = []   ## same-layer tiles touching i's left edge
var right: Array[PackedInt32Array] = []  ## same-layer tiles touching i's right edge
var index_by_pos: Dictionary = {}        ## "gx,gy,z" -> index
var zobrist := PackedInt64Array()
var min_gx: int = 0
var max_gx: int = 0
var min_gy: int = 0
var max_gy: int = 0
var max_z: int = 0
var errors := PackedStringArray()


static func from_positions(positions: Array) -> BoardGeometry:
	## positions: Array of Vector3i in half units (gx, gy, z).
	var g := BoardGeometry.new()
	g._build(positions)
	return g


static func pos_key(p_gx: int, p_gy: int, p_z: int) -> String:
	return "%d,%d,%d" % [p_gx, p_gy, p_z]


func _build(positions: Array) -> void:
	count = positions.size()
	gx.resize(count)
	gy.resize(count)
	gz.resize(count)
	zobrist.resize(count)
	var rng := SeededRng.new(0x5EEDB0A4D)
	for i in count:
		var p: Vector3i = positions[i]
		gx[i] = p.x
		gy[i] = p.y
		gz[i] = p.z
		zobrist[i] = rng.next_u63() ^ (rng.next_u63() << 1)
		var key := pos_key(p.x, p.y, p.z)
		if index_by_pos.has(key):
			errors.append("duplicate position %s" % key)
		index_by_pos[key] = i
		if p.z < 0:
			errors.append("negative layer at %s" % key)
	if count > 0:
		min_gx = gx[0]; max_gx = gx[0]; min_gy = gy[0]; max_gy = gy[0]; max_z = gz[0]
	for i in count:
		min_gx = mini(min_gx, gx[i]); max_gx = maxi(max_gx, gx[i])
		min_gy = mini(min_gy, gy[i]); max_gy = maxi(max_gy, gy[i])
		max_z = maxi(max_z, gz[i])
		above.append(PackedInt32Array())
		below.append(PackedInt32Array())
		left.append(PackedInt32Array())
		right.append(PackedInt32Array())
	for i in count:
		for j in range(i + 1, count):
			var dx := gx[j] - gx[i]
			var dy := gy[j] - gy[i]
			var overlap_x := absi(dx) < TileModel.W
			var overlap_y := absi(dy) < TileModel.H
			if gz[i] == gz[j]:
				if overlap_x and overlap_y:
					errors.append("tiles %d and %d overlap on layer %d" % [i, j, gz[i]])
				elif overlap_y and dx == TileModel.W:
					right[i].append(j)
					left[j].append(i)
				elif overlap_y and dx == -TileModel.W:
					left[i].append(j)
					right[j].append(i)
			elif overlap_x and overlap_y:
				if gz[j] > gz[i]:
					above[i].append(j)
					below[j].append(i)
				else:
					above[j].append(i)
					below[i].append(j)


func is_supported(i: int) -> bool:
	## A tile above layer 0 should rest on at least one tile directly below it.
	if gz[i] == 0:
		return true
	for b in below[i]:
		if gz[b] == gz[i] - 1:
			return true
	return false


func width_half_units() -> int:
	return max_gx - min_gx + TileModel.W


func height_half_units() -> int:
	return max_gy - min_gy + TileModel.H


func draw_order() -> PackedInt32Array:
	## Back-to-front. A tile is always drawn after every tile it covers; otherwise the lower row
	## is in front (the slab look), even across layers: a higher tile a full row above a lower
	## one doesn't cover it, so it must not be drawn over its top edge.
	## Key gy + 2*gz (half units): a covering pair has |dy| <= 1 and dz >= 1, so the top tile's
	## key is always larger; equal keys are tiles a full row apart, ordered by row.
	var idx: Array = range(count)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ka := gy[a] + 2 * gz[a]
		var kb := gy[b] + 2 * gz[b]
		if ka != kb:
			return ka < kb
		if gy[a] != gy[b]:
			return gy[a] < gy[b]
		return gx[a] < gx[b])
	return PackedInt32Array(idx)
