class_name FreePlayService
extends RefCounted
## Saved data for Play Together and Board Studio: the two players' names and colours, whose turn
## starts the next game, the player's saved Studio boards (share codes only) and local results.
## None of it affects progression: no coins, Lights, streak, Daily Tasks or level completion.
## Names never leave the device (not in analytics, not in share text).

const MAX_BOARDS := 30
const SLOT_DUET := "duet_session"
const SLOT_STUDIO := "studio_session"


static func _duet() -> Dictionary:
	return GameState.data.duet


static func _studio() -> Dictionary:
	return GameState.data.studio


# --- players --------------------------------------------------------------------------

static func _players() -> Array:
	var ps: Variant = _duet().get("players")
	if typeof(ps) != TYPE_ARRAY:
		ps = []
		_duet().players = ps
	while ps.size() < 2:
		ps.append({"name": "", "color": ps.size()})
	for k in 2:
		if typeof(ps[k]) != TYPE_DICTIONARY:
			ps[k] = {"name": "", "color": k}
	return ps


static func player(i: int) -> Dictionary:
	return _players()[clampi(i, 0, 1)]


static func player_name(i: int) -> String:
	## The saved name, or "Player 1"/"Player 2" in the current language.
	var n := DuetTurns.clean_name(str(player(i).get("name", "")))
	return n if n != "" else LocalizationService.t("player_n", {"n": i + 1})


static func color_index(i: int) -> int:
	return clampi(int(player(i).get("color", i)), 0, DuetTurns.COLORS.size() - 1)


static func player_color(i: int) -> Color:
	return DuetTurns.COLORS[color_index(i)]


static func set_player_name(i: int, text: String) -> void:

	var ps := _players()
	ps[i] = {"name": DuetTurns.clean_name(text), "color": color_index(i)}
	GameState.request_save()


static func set_player_color(i: int, c: int) -> void:
	## Two players never share a colour: taking the other player's colour swaps them.
	var ps := _players()
	var other := 1 - i
	c = clampi(c, 0, DuetTurns.COLORS.size() - 1)
	if color_index(other) == c:
		ps[other] = {"name": str(player(other).get("name", "")), "color": color_index(i)}
	ps[i] = {"name": str(player(i).get("name", "")), "color": c}
	GameState.request_save()


static func next_first() -> int:
	return clampi(int(_duet().get("first", 0)), 0, 1)


static func difficulty() -> String:
	var d := str(_duet().get("difficulty", "easy"))
	return d if d in StudioBoard.DIFFICULTIES else "easy"


static func set_difficulty(d: String) -> void:
	if d in StudioBoard.DIFFICULTIES:
		_duet().difficulty = d
		GameState.request_save()


static func game_started() -> int:
	## Who starts this game; the other player starts the next one.
	var first := next_first()
	_duet().first = 1 - first
	_duet().games = int(_duet().get("games", 0)) + 1
	GameState.request_save()
	return first


static func record_duet_win(key: String, score: int) -> bool:
	## Returns true for a new best team score on this kind of board.
	_duet().wins = int(_duet().get("wins", 0)) + 1
	var best: Dictionary = _duet().best
	var is_best := score > int(best.get(key, 0))
	if is_best:
		best[key] = score
	GameState.request_save()
	return is_best


static func team_wins() -> int:
	return int(_duet().get("wins", 0))


# --- studio boards --------------------------------------------------------------------

static func boards() -> Array:
	var b: Variant = _studio().get("boards", [])
	return b if typeof(b) == TYPE_ARRAY else []


static func find_board(code: String) -> int:
	var list := boards()
	for k in list.size():
		if typeof(list[k]) == TYPE_DICTIONARY and str(list[k].get("code", "")) == code:
			return k
	return -1


static func save_board(code: String, from_friend: bool) -> String:
	## "saved" | "exists" | "full" | "invalid". New boards go first; nothing is ever dropped to
	## make room (the player deletes boards themselves).
	if StudioCode.decode(code).err != StudioCode.Err.OK:
		return "invalid"
	if find_board(code) >= 0:
		return "exists"
	if boards().size() >= MAX_BOARDS:
		return "full"
	var list := boards()
	list.insert(0, {"code": code, "friend": from_friend, "solved": false, "best": 0,
		"added": int(Time.get_unix_time_from_system())})
	_studio().boards = list
	if not from_friend:
		_studio().made = int(_studio().get("made", 0)) + 1
	GameState.request_save()
	return "saved"


static func delete_board(code: String) -> bool:
	var k := find_board(code)
	if k < 0:
		return false
	var list := boards()
	list.remove_at(k)
	_studio().boards = list
	GameState.request_save()
	return true


static func record_studio_win(code: String, score: int) -> bool:
	## Marks a saved board solved; returns true for a new best score on it.
	var k := find_board(code)
	if k < 0:
		return false
	var b: Dictionary = boards()[k]
	b.solved = true
	var is_best := score > int(b.get("best", 0))
	if is_best:
		b.best = score
	GameState.request_save()
	return is_best


static func boards_made() -> int:
	return int(_studio().get("made", 0))


# --- "new" badges on Home -------------------------------------------------------------

static func seen(feature: String) -> bool:
	var d: Dictionary = _duet() if feature == "duet" else _studio()
	return bool(d.get("seen", false))


static func mark_seen(feature: String) -> void:
	var d: Dictionary = _duet() if feature == "duet" else _studio()
	if not bool(d.get("seen", false)):
		d.seen = true
		GameState.request_save()
