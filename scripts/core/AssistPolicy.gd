class_name AssistPolicy
extends RefCounted
## What a helper costs right now. Pure functions so the rules are unit-tested and the screen
## only asks. Free ways forward always exist (restart, rewind to the last solvable point, the
## free rescue shuffle when no moves remain), so the economy can never soft-lock a board.

static func undo_cost(assists: Dictionary, free_per_board: int, owned: int, economy_on: bool) -> Dictionary:
	## {"allowed": bool, "free": bool}. The first `free_per_board` undos of a board are free.
	if not economy_on:
		return {"allowed": true, "free": true}
	if int(assists.get("free_undos_used", 0)) < free_per_board:
		return {"allowed": true, "free": true}
	return {"allowed": owned > 0, "free": false}


static func free_undos_left(assists: Dictionary, free_per_board: int) -> int:
	return maxi(0, free_per_board - int(assists.get("free_undos_used", 0)))


static func shuffle_cost(assists: Dictionary, free_rescues: int, no_moves: bool, owned: int, economy_on: bool) -> Dictionary:
	## {"allowed": bool, "free": bool}. One free rescue shuffle per board, only when no legal
	## moves remain (the moment players are most likely to give up).
	if not economy_on:
		return {"allowed": true, "free": true}
	if no_moves and int(assists.get("rescue_shuffles_used", 0)) < free_rescues:
		return {"allowed": true, "free": true}
	return {"allowed": owned > 0, "free": false}


static func hint_should_charge(res: Dictionary, economy_on: bool) -> bool:
	## Pay only for information delivered: a pair was shown, it is not a dead end, and it is
	## not a free repeat of the hint already on screen.
	return economy_on and res.get("pair") != null and not bool(res.get("dead", false)) \
		and not bool(res.get("repeat", false))
