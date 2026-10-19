class_name TrayRules
extends RefCounted
## The tray every picked tile flies into. Pure helpers over a plain list of tile indices.
##
## - A tile whose twin is already in the tray clears with it at once, so the tray never holds
##   two tiles of one match key.
## - Otherwise the tile is appended (slot order = arrival order).
## - A tray holding `capacity` tiles is a loss: there is no room to bring a twin in.
##
## Because pairs clear at once, the tray is fully determined by the set of tiles off the
## board: it holds exactly the keys with an odd count of tiles taken. Solvers use that to
## memoise on the board hash alone.

const CAPACITY := 4


static func partner_slot(tray: PackedInt32Array, keys: PackedInt32Array, i: int) -> int:
	## Slot of the tray tile that matches tile i, or -1.
	var k := keys[i]
	for s in tray.size():
		if keys[tray[s]] == k:
			return s
	return -1


static func is_full(tray: PackedInt32Array, capacity: int = CAPACITY) -> bool:
	return tray.size() >= capacity


static func keys_valid(tray: PackedInt32Array, keys: PackedInt32Array) -> bool:
	## A saved tray must never hold two tiles of one key (they would have cleared).
	var seen := {}
	for i in tray:
		if i < 0 or i >= keys.size() or seen.has(keys[i]):
			return false
		seen[keys[i]] = true
	return true
