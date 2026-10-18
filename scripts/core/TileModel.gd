class_name TileModel
extends RefCounted
## One physical tile slot on a board: stable instance id, logical geometry and face.
##
## Geometry is expressed in HALF-TILE units: a tile occupies a 2x2 footprint starting at
## (gx, gy) on layer z. The asset pack uses whole-tile integer coordinates, which map to
## gx = 2x, gy = 2y. Half units let future layouts offset tiles by half a tile (classic
## "turtle" caps, bridges) without changing the rules engine.
##
## Visual bounds (sprite padding, shadow, layer offset) are deliberately NOT stored here;
## BoardView derives them, so input hit-testing and rendering never alter rules.

const W := 2  ## footprint width in half units
const H := 2  ## footprint height in half units

var id: int = 0
var gx: int = 0
var gy: int = 0
var z: int = 0
var face: String = ""


static func make(p_id: int, p_gx: int, p_gy: int, p_z: int, p_face: String) -> TileModel:
	var t := TileModel.new()
	t.id = p_id
	t.gx = p_gx
	t.gy = p_gy
	t.z = p_z
	t.face = p_face
	return t


func pos_key() -> String:
	return "%d,%d,%d" % [gx, gy, z]


func overlaps_xy(other: TileModel) -> bool:
	## True when the two footprints share area (touching edges do not count).
	return absi(gx - other.gx) < W and absi(gy - other.gy) < H
