class_name BoardFit
extends RefCounted
## How a layered board is projected onto the screen and how big its tiles can be drawn. Pure (no
## nodes/autoloads), so the game (BoardView/BoardProjection), the level build tools and the tests
## all use exactly the same numbers. Lengths are in tile widths (the art cell's width) unless noted.
##
## Projection (2026-10-22): the board is drawn as a real stack seen from above and slightly to the
## front-right. Every tile shows its top FACE and two sides: the bottom side is the thickness band
## painted in the tile art, the right side is drawn by TileView. A tile on layer z is shifted
## up-left by z times that thickness (LIFT == SIDE), so a tile resting on another shows the lower
## tile's sides beneath it, and a tile half a tile off its supports visibly straddles them.
## Same-layer neighbours sit one FACE apart (plus a hairline GAP), so a layer reads as one floor.
##
## Because LIFT equals SIDE, a higher tile never reaches onto the face of a lower tile it does not
## cover (see BoardGeometry.draw_order and test_board_layout.gd), so what is drawn on top is
## exactly what the rules call "on top".

const ASPECT := 164.0 / 128.0       ## art cell height / width (LiShi v2 cells are 192x246)
## Opaque part of the art cell (fractions of the cell): the face plus the bottom side band. The
## rest of the cell is transparent padding with a soft baked shadow.
const BODY := Rect2(0.04, 0.025, 0.915, 0.905)
const FACE_FRAC := 0.80             ## face height as a fraction of the cell (measured on the art)
const FACE := Vector2(0.915, 0.80 * ASPECT)        ## top face: 0.915 x 1.025
const SIDE := Vector2(0.05, (0.905 - 0.80) * ASPECT)  ## right side (drawn) x bottom side (art): 0.05 x 0.135
const LIFT := SIDE                  ## screen shift per layer up (up-left)
const GAP := Vector2(0.02, 0.02)    ## hairline between same-layer neighbours
const PITCH := FACE + GAP           ## one full tile step on a layer (2 half units)
## Room for the baked soft shadow and the contact shadow past the right/bottom sides.
const SHADOW_PAD := Vector2(0.03, 0.05)
const MAX_TILE_W := 112.0

## Board area in tray play on a typical modern portrait phone (logical px; 540x1200 canvas,
## 20:9): compact HUD, the ornate tray, the toolbar, 6 px side margins and no banner while
## playing. Measured in-game (ScreenshotTour --levels prints it); a 16:9 phone is ~240 px shorter.
const PLAY_AREA := Vector2(528, 893)  ## measured 2026-10-19 with the 128 px premium tray
## Content target: the level and daily builds since 2026-10-22 ("tpl-1") were fitted to this area.
## Frozen, so rebuilding content reproduces the same files.
const REFERENCE_AREA := Vector2(528, 893)


static func face_pos(gx: int, gy: int, z: int) -> Vector2:
	## Top-left of a tile's face, relative to half-unit (0, 0) on layer 0.
	return Vector2(gx * 0.5 * PITCH.x - z * LIFT.x, gy * 0.5 * PITCH.y - z * LIFT.y)


static func solid_rect(gx: int, gy: int, z: int) -> Rect2:
	## Face plus its right and bottom sides: everything opaque a finger can touch.
	return Rect2(face_pos(gx, gy, z), FACE + SIDE)


static func bounds(geo: BoardGeometry) -> Rect2:
	## Union of every tile's face and sides, plus the shadow room, in tile widths.
	if geo.count == 0:
		return Rect2(Vector2.ZERO, FACE + SIDE + SHADOW_PAD)
	var r := solid_rect(geo.gx[0], geo.gy[0], geo.gz[0])
	for i in range(1, geo.count):
		r = r.merge(solid_rect(geo.gx[i], geo.gy[i], geo.gz[i]))
	r.size += SHADOW_PAD
	return r


static func board_units(geo: BoardGeometry) -> Vector2:
	## Board extent in tile widths (x and y), including layer lift, sides and shadows.
	return bounds(geo).size


static func fit_tile_width(geo: BoardGeometry, area: Vector2 = REFERENCE_AREA) -> float:
	var u := board_units(geo)
	return minf(minf(area.x / u.x, area.y / u.y), MAX_TILE_W)


static func columns_width(cols: int) -> float:
	## Width of `cols` side-by-side ground tiles, in tile widths.
	return (cols - 1) * PITCH.x + FACE.x + SIDE.x + SHADOW_PAD.x


static func rows_to_fill(cols: int, area: Vector2 = REFERENCE_AREA) -> int:
	## How many ground rows make a `cols`-wide board as tall as the area allows at the tile size
	## its width gives: the board then fills BOTH the width and the height of the screen.
	var tw := minf(area.x / columns_width(cols), MAX_TILE_W)
	var h := area.y / tw - (FACE.y + SIDE.y + SHADOW_PAD.y)
	return maxi(3, int(floor(h / PITCH.y + 0.001)) + 1)


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
