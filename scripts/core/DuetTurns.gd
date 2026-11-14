class_name DuetTurns
extends RefCounted
## Play Together: two players share one board and one tray and take turns, one tile per turn.
##
## Nothing about turns is stored: whose turn it is and who earned what are worked out from the
## board's move history (GameSession.history), so Undo, rewinding, saving and resuming after the
## app is killed can never get out of step. Rules:
## - Every pick (into the tray or finishing a pair) ends the turn. Shuffles and sending tiles
##   back are team actions and don't. Undoing a pick gives the turn back to whoever made it.
## - A pair belongs to the player whose pick finished it. When the other player had put its
##   twin in the tray, it is a Team-up (a bonus, and the headline team statistic).

const TEAM_UP_BONUS := 5
const NAME_MAX := 14
const COLORS: Array[Color] = [Color("1E9E8C"), Color("D9577A"), Color("D9A21C"), Color("7B5BD6"), Color("2F7FD8"), Color("4E9F3D")]


static func pick_count(history: Array) -> int:
	var n := 0
	for e in history:
		if str(e.get("t", "")) == "p":
			n += 1
	return n


static func current_player(history: Array, first: int) -> int:
	return (first + pick_count(history)) % 2


static func summary(history: Array, first: int) -> Dictionary:
	## {"pairs": [a, b] pairs each player took part in (a Team-up counts for both),
	##  "finished": [a, b] pairs each player completed, "team_ups": [a, b] by finisher,
	##  "points": [a, b] by finisher (they add up to the team score), "picks": [a, b],
	##  "placer": {tile in tray or cleared: player who put it in the tray}}
	var out := {"pairs": [0, 0], "finished": [0, 0], "team_ups": [0, 0], "points": [0, 0], "picks": [0, 0], "placer": {}}
	var k := 0
	for e in history:
		if str(e.get("t", "")) != "p":
			continue
		var who := (first + k) % 2
		k += 1
		out.picks[who] += 1
		var partner := int(e.get("m", -1))
		if partner < 0:
			out.placer[int(e.i)] = who
			continue
		out.finished[who] += 1
		out.pairs[who] += 1
		out.points[who] += int(e.get("pts", 0))
		if int(out.placer.get(partner, who)) != who:
			out.team_ups[who] += 1
			out.pairs[1 - who] += 1
	return out


static func is_team_up(history: Array, first: int) -> bool:
	## Whether the last pick finished a pair whose twin the other player had put in the tray.
	if history.is_empty() or str(history[-1].get("t", "")) != "p" or int(history[-1].get("m", -1)) < 0:
		return false
	var s := summary(history.slice(0, history.size() - 1), first)
	var who := (first + pick_count(history) - 1) % 2
	return int(s.placer.get(int(history[-1].m), who)) != who


static func tray_owners(history: Array, first: int, tray: PackedInt32Array) -> PackedInt32Array:
	## For each tray slot, the player who put that tile there (-1 if unknown).
	var placer: Dictionary = summary(history, first).placer
	var out := PackedInt32Array()
	for t in tray:
		out.append(int(placer.get(t, -1)))
	return out


static func clean_name(text: String) -> String:
	## Player names stay on the device. Keeps letters, digits, spaces and simple punctuation:
	## no control characters, no emoji (the game fonts can't draw them), at most NAME_MAX.
	var out := ""
	for ch in text.strip_edges():
		var c := ch.unicode_at(0)
		if c < 0x20 or (c >= 0x7F and c < 0xA0) or (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) \
				or (c >= 0x2060 and c <= 0x206F) or (c >= 0x2600 and c <= 0x27BF) or (c >= 0xFE00 and c <= 0xFE0F) \
				or c >= 0x1F000 or (c >= 0xD800 and c <= 0xDFFF):
			continue
		out += ch
		if out.length() >= NAME_MAX:
			break
	return out.strip_edges()
