class_name BoardFit
extends RefCounted
## How big tiles can be drawn for a board in a given screen area. Pure (no nodes/autoloads), so
## the game (BoardView), the level build tools and the tests all use exactly the same numbers.
##
## Tiles are taller than wide (128x164 art), and phones are portrait, so a board should usually
## have more rows than columns. best_orientation() picks original vs. transposed geometry.

## Fractions of the sprite size (pack tiles are 128x164 / 256x328 with padding + shadow).
const STEP_X := 0.915
const STEP_Y := 0.885
const LAYER_DX := -0.07
const LAYER_DY := -0.055
const ASPECT := 164.0 / 128.0
const MAX_TILE_W := 112.0

## Board area on a typical modern portrait phone (logical px; 540-wide canvas, 20:9 screen,
## minus HUD, toolbar and a bottom banner). Measured in-game: 508x987 without the banner.
const REFERENCE_AREA := Vector2(508, 880)


static func board_units(geo: BoardGeometry) -> Vector2:
	## Board extent in tile-widths (x and y), including layer offsets and the tile aspect.
	var w := (geo.max_gx - geo.min_gx) / 2.0 * STEP_X + 1.0 + geo.max_z * absf(LAYER_DX)
	var h := ((geo.max_gy - geo.min_gy) / 2.0 * STEP_Y + 1.0 + geo.max_z * absf(LAYER_DY)) * ASPECT
	return Vector2(w, h)


static func fit_tile_width(geo: BoardGeometry, area: Vector2 = REFERENCE_AREA) -> float:
	var u := board_units(geo)
	return minf(minf(area.x / u.x, area.y / u.y), MAX_TILE_W)


static func transposed(positions: Array) -> Array:
	## Swap columns and rows. Tiles are 2x2 in half units on both axes, so a valid layout stays
	## valid (no overlaps, same support), but left/right blocking now runs along the old rows -
	## i.e. it is a different puzzle and must be (re)generated and validated as such.
	var out: Array = []
	for p in positions:
		out.append(Vector3i(p.y, p.x, p.z))
	return out


static func best_orientation(positions: Array, area: Vector2 = REFERENCE_AREA) -> Array:
	## Returns the positions (original or transposed) that give the bigger tiles in `area`.
	var t := transposed(positions)
	var f0 := fit_tile_width(BoardGeometry.from_positions(positions), area)
	var f1 := fit_tile_width(BoardGeometry.from_positions(t), area)
	return t if f1 > f0 + 0.01 else positions
