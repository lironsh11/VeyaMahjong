class_name BoardProjection
extends RefCounted
## Where every tile of a board is drawn on screen for one tile width, in which order, and which
## tile a touch lands on. Pure (no nodes): BoardView draws from it and the tests check it headless.
##
## Rects per tile (screen px):
##   face   - the top face (the symbol)
##   solid  - face + right and bottom sides: the opaque tile a finger can touch
##   sprite - the whole art cell, incl. its transparent padding and baked shadow (never touched)
## Hit-testing walks the tiles front to back (reverse draw order), so the tile under the finger is
## the one drawn on top there - never a lower tile through a higher one - and it ignores shadows
## and transparent padding. Draw order is BoardGeometry.draw_order(), not z_index.

var geo: BoardGeometry
var tile_w: float = 64.0
var origin: Vector2 = Vector2.ZERO  ## screen px of half-unit (0, 0) on layer 0
var order := PackedInt32Array()     ## back to front
var rank := PackedInt32Array()      ## tile -> its place in `order`


static func make(p_geo: BoardGeometry, p_tile_w: float, p_origin: Vector2) -> BoardProjection:
	var p := BoardProjection.new()
	p.geo = p_geo
	p.tile_w = p_tile_w
	p.origin = p_origin
	p.order = p_geo.draw_order()
	p.rank.resize(p_geo.count)
	for k in p.order.size():
		p.rank[p.order[k]] = k
	return p


static func centered(p_geo: BoardGeometry, area: Vector2, p_tile_w: float = -1.0, pan: Vector2 = Vector2.ZERO) -> BoardProjection:
	## The board fitted (or at p_tile_w) and centred in a control of size `area`.
	var tw := BoardFit.fit_tile_width(p_geo, area) if p_tile_w <= 0.0 else p_tile_w
	var b := BoardFit.bounds(p_geo)
	var o := (area - b.size * tw) * 0.5 + pan - b.position * tw
	return make(p_geo, tw, o)


func content_rect() -> Rect2:
	## The whole board on screen (faces, sides, shadow room).
	var b := BoardFit.bounds(geo)
	return Rect2(origin + b.position * tile_w, b.size * tile_w)


func face_rect(i: int) -> Rect2:
	return Rect2(origin + BoardFit.face_pos(geo.gx[i], geo.gy[i], geo.gz[i]) * tile_w, BoardFit.FACE * tile_w)


func solid_rect(i: int) -> Rect2:
	return Rect2(origin + BoardFit.face_pos(geo.gx[i], geo.gy[i], geo.gz[i]) * tile_w, (BoardFit.FACE + BoardFit.SIDE) * tile_w)


func sprite_rect(i: int) -> Rect2:
	## The art cell: its BODY starts at the face's top-left.
	var size := Vector2(tile_w, tile_w * BoardFit.ASPECT)
	return Rect2(face_rect(i).position - BoardFit.BODY.position * size, size)


func pick(point: Vector2, removed: PackedByteArray, grow: float = 0.0) -> int:
	## Topmost remaining tile whose face or sides contain `point` (-1 if none). With `grow` > 0,
	## a touch in a gap goes to the nearest tile whose slightly enlarged solid contains it.
	for k in range(order.size() - 1, -1, -1):
		var i := order[k]
		if removed[i] == 0 and solid_rect(i).has_point(point):
			return i
	if grow <= 0.0:
		return -1
	var best := -1
	var best_d := INF
	for k in range(order.size() - 1, -1, -1):
		var i := order[k]
		if removed[i] != 0:
			continue
		var r := solid_rect(i)
		r = r.grow(r.size.x * grow)
		if r.has_point(point):
			var d := r.get_center().distance_squared_to(point)
			if d < best_d - 0.01:
				best_d = d
				best = i
	return best
