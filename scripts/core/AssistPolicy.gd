class_name AssistPolicy
extends RefCounted
## What a helper costs right now. Pure functions so the rules are unit-tested and the screen
## only asks. Free ways forward always exist (restart, rewind to the last solvable point, the
## free rescue shuffle when the board is stuck, the first free continue after a full tray),
## so the economy can never soft-lock a board.

static func undo_cost(assists: Dictionary, free_per_board: int, owned: int, economy_on: bool) -> Dictionary:
	## {"allowed": bool, "free": bool}. The first `free_per_board` undos of a board are free.
	if not economy_on:
		return {"allowed": true, "free": true}
	if int(assists.get("free_undos_used", 0)) < free_per_board:
		return {"allowed": true, "free": true}
	return {"allowed": owned > 0, "free": false}


static func free_undos_left(assists: Dictionary, free_per_board: int) -> int:
	return maxi(0, free_per_board - int(assists.get("free_undos_used", 0)))


static func shuffle_cost(assists: Dictionary, free_rescues: int, stuck: bool, owned: int, economy_on: bool) -> Dictionary:
	## {"allowed": bool, "free": bool}. One free rescue shuffle per board, only when the board
	## is proven stuck (the moment players are most likely to give up).
	if not economy_on:
		return {"allowed": true, "free": true}
	if stuck and int(assists.get("rescue_shuffles_used", 0)) < free_rescues:
		return {"allowed": true, "free": true}
	return {"allowed": owned > 0, "free": false}


static func continue_cost(assists: Dictionary, costs: Array, coins: int, economy_on: bool) -> Dictionary:
	## {"allowed": bool, "free": bool, "coins": int}. Price of sending tiles back after a full
	## tray: costs[n] for the n-th continue on this board (the last price repeats). A price of 0
	## is free, so the first continue of a board is free with the default config.
	if not economy_on or costs.is_empty():
		return {"allowed": true, "free": true, "coins": 0}
	var n := int(assists.get("continues_used", 0))
	var price := int(costs[mini(n, costs.size() - 1)])
	if price <= 0:
		return {"allowed": true, "free": true, "coins": 0}
	return {"allowed": coins >= price, "free": false, "coins": price}


static func hint_should_charge(res: Dictionary, economy_on: bool) -> bool:
	## Pay only for information delivered: a tile was shown, it is not a dead end, and it is
	## not a free repeat of the hint already on screen.
	return economy_on and not PackedInt32Array(res.get("tiles", [])).is_empty() \
		and not bool(res.get("dead", false)) and not bool(res.get("repeat", false))
