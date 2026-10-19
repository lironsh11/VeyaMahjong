class_name Scoring
extends RefCounted
## Score and stars for tray play. Pure functions so the numbers are unit-tested.
##
## - Each pair is worth POINTS_PER_PAIR × the combo multiplier (BoardController owns combo
##   timing; the multiplier is capped at MAX_MULTIPLIER).
## - A clean board (no undo, no full tray) earns CLEAN_BONUS_PER_PAIR per pair on top.
## - Stars compare the final score with the board's base score (every pair without a combo):
##   any win is 1 star; TWO_STAR_RATIO × base is 2; THREE_STAR_RATIO × base is 3.
##   A relaxed clean player lands near 1.5× base; steady combos reach 3×. Tune here.

const POINTS_PER_PAIR := 10
const MAX_MULTIPLIER := 10
const CLEAN_BONUS_PER_PAIR := 5
const TWO_STAR_RATIO := 1.6
const THREE_STAR_RATIO := 3.0


static func points_for(combo: int) -> int:
	return POINTS_PER_PAIR * clampi(combo, 1, MAX_MULTIPLIER)


static func base_score(tiles: int) -> int:
	return (tiles / 2) * POINTS_PER_PAIR


static func clean_bonus(tiles: int, stats: Dictionary) -> int:
	if int(stats.get("undos", 0)) > 0 or int(stats.get("fails", 0)) > 0:
		return 0
	return (tiles / 2) * CLEAN_BONUS_PER_PAIR


static func stars(total: int, tiles: int) -> int:
	var base := maxi(1, base_score(tiles))
	var r := float(total) / float(base)
	if r >= THREE_STAR_RATIO:
		return 3
	if r >= TWO_STAR_RATIO:
		return 2
	return 1


static func final(score: int, tiles: int, stats: Dictionary) -> Dictionary:
	## {"score": total incl. bonus, "bonus": clean bonus, "stars": 1..3}
	var bonus := clean_bonus(tiles, stats)
	var total := score + bonus
	return {"score": total, "bonus": bonus, "stars": stars(total, tiles)}
