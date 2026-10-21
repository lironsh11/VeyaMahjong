extends Node
## Earned progression. Everything here is idempotent and derived from immutable records:
## - A LiShi Light is recorded by its SOURCE key ("level:12", "daily:2026-10-18",
##   "tasks:2026-10-18", "ad:<grant id>"). Recording the same source twice is a no-op, so
##   replays, double taps, crashes-and-reloads and duplicate callbacks cannot farm Lights.
## - Bloom discoveries unlocked = floor(lights / lights_per_discovery) (capped), and tile
##   theme unlocks are computed from progress + verified entitlements. Lights are never a
##   mutable balance. (Coins are: see EconomyService, which is idempotent by grant id.)

signal light_awarded(source: String, total: int)
signal discovery_unlocked(discovery: Dictionary)
signal theme_unlocked(theme_id: String)


func lights() -> int:
	return GameState.lights()


func award_light(source: String) -> bool:
	if source == "" or GameState.has_light_source(source):
		return false
	var before_disc := discoveries_unlocked_count()
	var before_themes := unlocked_theme_ids()
	GameState.data.progress.light_sources.append(source)
	var total := lights()
	light_awarded.emit(source, total)
	var after_disc := discoveries_unlocked_count()
	var all := ContentService.all_discoveries()
	for i in range(before_disc, after_disc):
		discovery_unlocked.emit(all[i])
		AnalyticsService.track("bloom_item_unlocked", {"item": str(all[i].id), "lights": total})
	for t in unlocked_theme_ids():
		if not before_themes.has(t):
			theme_unlocked.emit(t)
	GameState.progress_changed.emit()
	return true


func complete_level(id: int, stats: Dictionary) -> Dictionary:
	## Records a level completion. Safe to call repeatedly for the same level.
	var completed: Dictionary = GameState.completed_levels()
	var key := str(id)
	var first := not completed.has(key)
	var before_disc := discoveries_unlocked_count()
	var before_themes := unlocked_theme_ids()
	var before_backs := unlocked_back_ids()
	var no_hint := int(stats.get("hints", 0)) == 0
	var score := int(stats.get("score", 0))
	var stars_now := clampi(int(stats.get("stars", 0)), 0, 3)
	var prev_best := 0
	if first:
		completed[key] = {"t": int(Time.get_unix_time_from_system()), "best_moves": int(stats.get("moves", 0)), "no_hint": no_hint,
			"best_score": score, "stars": stars_now}
	else:
		var rec: Dictionary = completed[key]
		rec["no_hint"] = bool(rec.get("no_hint", false)) or no_hint
		prev_best = int(rec.get("best_score", 0))
		rec["best_score"] = maxi(prev_best, score)
		rec["stars"] = maxi(int(rec.get("stars", 0)), stars_now)
	var light := award_light("level:%d" % id) if first else false
	var result := _result(first, light, before_disc, before_themes)
	result["stars"] = stars_now
	result["best_score"] = maxi(prev_best, score)
	result["new_best"] = not first and score > prev_best
	result["backs"] = unlocked_back_ids().filter(func(b: String) -> bool: return not before_backs.has(b))
	result.merge(_record_streak_win(id, first, stats), true)
	var w := ContentService.world_for_level(id)
	if first and not w.is_empty() and id == int(w.levels[1]):
		var nw := ContentService.world_for_level(id + 1)
		if not nw.is_empty() and nw.id != w.id:
			result["world_unlocked"] = nw.id
	if first:
		var coins := EconomyService.level_reward(id)
		if coins > 0 and EconomyService.grant("level:%d" % id, {"coins": coins}, "level"):
			result["coins"] = coins
		if not w.is_empty() and id == int(w.levels[1]):
			var bonus := EconomyService.reward("world_complete")
			if bonus > 0 and EconomyService.grant("world:" + str(w.id), {"coins": bonus}, "world"):
				result["world_bonus"] = bonus
	_count_board(stats)
	GameState.save_now()
	return result


func level_stars(id: int) -> int:
	var rec: Variant = GameState.completed_levels().get(str(id))
	return int(rec.get("stars", 0)) if typeof(rec) == TYPE_DICTIONARY else 0


# --- Win streak -----------------------------------------------------------------------
# Consecutive first-try wins of NEW levels. A full tray, or a fresh restart of the level being
# attempted, ends the streak. Replays of completed levels and the daily puzzle never change
# it. At 3+ every new level starts with a free extra tray slot; reaching 5 and 7 pays a fixed,
# disclosed gift (a Hint, a Shuffle) once per streak (EconomyService ledger id per run).

const STREAK_SLOT_AT := 3
const STREAK_GIFTS := {5: {"hint": 1}, 7: {"shuffle": 1}}


func _streak() -> Dictionary:
	return GameState.data.streak


func streak_count() -> int:
	return int(_streak().get("count", 0))


func streak_best() -> int:
	return int(_streak().get("best", 0))


func streak_bonus_active() -> bool:
	return streak_count() >= STREAK_SLOT_AT


func start_attempt(level_id: int) -> bool:
	## Called when a level starts FRESH (not resumed). Returns true when this is a retry of the
	## level already being attempted, which ends the streak. Completed levels are ignored.
	if GameState.is_level_completed(level_id):
		return false
	var s := _streak()
	if int(s.get("attempt", 0)) == level_id:
		break_streak("retry")
		return true
	s["attempt"] = level_id
	GameState.request_save()
	return false


func break_streak(reason: String) -> int:
	## Ends the current streak. Returns how long it was (0 if there was none).
	var s := _streak()
	var n := int(s.get("count", 0))
	if n > 0:
		AnalyticsService.track("win_streak_lost", {"count": n, "reason": reason})
		s["count"] = 0
		s["run"] = int(s.get("run", 0)) + 1
		GameState.save_now()
	return n


func _record_streak_win(id: int, first: bool, stats: Dictionary) -> Dictionary:
	## {"streak": count after this win (0 = not counted), "streak_gift": contents or {}}
	var s := _streak()
	if int(s.get("attempt", 0)) == id:
		s["attempt"] = 0
	if not first:
		return {"streak": 0, "streak_gift": {}}
	if int(stats.get("fails", 0)) > 0 or int(stats.get("retry", 0)) > 0:
		return {"streak": 0, "streak_gift": {}}
	var n := int(s.get("count", 0)) + 1
	s["count"] = n
	s["best"] = maxi(int(s.get("best", 0)), n)
	var gift: Dictionary = STREAK_GIFTS.get(n, {}).duplicate()
	if not gift.is_empty():
		if not EconomyService.grant("streak:%d:%d" % [int(s.get("run", 0)), n], gift, "streak"):
			gift = {}
	AnalyticsService.track("win_streak", {"count": n})
	return {"streak": n, "streak_gift": gift}


func complete_daily(date: String, stats: Dictionary) -> Dictionary:
	var before_disc := discoveries_unlocked_count()
	var before_themes := unlocked_theme_ids()
	var done: Dictionary = GameState.data.daily.completed
	var first := not done.has(date)
	if first:
		done[date] = {"t": int(Time.get_unix_time_from_system()), "moves": int(stats.get("moves", 0)), "hints": int(stats.get("hints", 0))}
	var light := award_light("daily:" + date) if first else false
	var result := _result(first, light, before_disc, before_themes)
	var coins := EconomyService.reward("daily_first_clear")
	if first and coins > 0 and EconomyService.grant("daily:" + date, {"coins": coins}, "daily"):
		result["coins"] = coins
	_count_board(stats)
	GameState.save_now()
	return result


func _count_board(stats: Dictionary) -> void:
	GameState.add_stat("boards_completed")
	GameState.add_stat("hints", int(stats.get("hints", 0)))
	GameState.add_stat("shuffles", int(stats.get("shuffles", 0)))
	GameState.add_stat("undos", int(stats.get("undos", 0)))


func _result(first: bool, light: bool, before_disc: int, before_themes: Array) -> Dictionary:
	var after := discoveries_unlocked_count()
	var all := ContentService.all_discoveries()
	var new_disc: Array = []
	for i in range(before_disc, after):
		new_disc.append(all[i])
	var new_themes: Array = []
	for t in unlocked_theme_ids():
		if not before_themes.has(t):
			new_themes.append(t)
	return {
		"first_time": first, "light_awarded": light, "lights": lights(),
		"next_progress": lights_progress(), "discoveries": new_disc, "themes": new_themes,
		"world_unlocked": "", "coins": 0, "world_bonus": 0,
	}


# --- Bloom --------------------------------------------------------------------------

func discoveries_unlocked_count() -> int:
	return mini(lights() / ContentService.lights_per_discovery(), ContentService.all_discoveries().size())


func is_discovery_unlocked(index: int) -> bool:
	return index < discoveries_unlocked_count()


func lights_progress() -> Vector2i:
	## (lights toward next discovery, lights needed per discovery); x == -1 when all found.
	var per := ContentService.lights_per_discovery()
	if discoveries_unlocked_count() >= ContentService.all_discoveries().size():
		return Vector2i(-1, per)
	return Vector2i(lights() % per, per)


func mark_discovery_seen(id: String) -> void:
	var seen: Array = GameState.data.bloom.seen
	if not seen.has(id):
		seen.append(id)
		GameState.request_save()


func unseen_discoveries() -> int:
	var n := 0
	var seen: Array = GameState.data.bloom.seen
	var all := ContentService.all_discoveries()
	for i in discoveries_unlocked_count():
		if not seen.has(all[i].id):
			n += 1
	return n


# --- Tile themes --------------------------------------------------------------------

func is_theme_unlocked(theme_id: String) -> bool:
	var t := ContentService.theme_def(theme_id)
	if t.is_empty():
		return false
	var ent := str(t.get("entitlement", ""))
	if ent != "" and IAPService.has_entitlement(ent):
		return true
	var u: Dictionary = t.get("unlock", {})
	match str(u.get("type", "")):
		"default":
			return true
		"lights":
			return lights() >= int(u.value)
		"level":
			return GameState.is_level_completed(int(u.value))
	return false


func unlocked_theme_ids() -> Array:
	var out: Array = []
	for t in ContentService.themes():
		if is_theme_unlocked(t.id):
			out.append(t.id)
	return out


func theme_unlock_hint(theme_id: String) -> String:
	var u: Dictionary = ContentService.theme_def(theme_id).get("unlock", {})
	match str(u.get("type", "")):
		"lights":
			return LocalizationService.t("unlock_by_lights", {"count": int(u.value), "have": lights()})
		"level":
			return LocalizationService.t("unlock_by_level", {"level": int(u.value)})
	return ""


func equipped_theme() -> String:
	var id := str(GameState.data.cosmetics.get("equipped_theme", "classic"))
	return id if is_theme_unlocked(id) else "classic"


func equip_theme(theme_id: String) -> bool:
	if not is_theme_unlocked(theme_id):
		return false
	GameState.data.cosmetics.equipped_theme = theme_id
	GameState.save_now()
	AnalyticsService.track("cosmetic_equipped", {"theme": theme_id})
	return true


# --- Tile backs ---------------------------------------------------------------------
# One per "Three New Worlds" world, earned by completing that world's last level. Derived from
# progress like themes, so it can never be lost or duplicated.

func is_back_unlocked(back_id: String) -> bool:
	if not ContentService.has_tile_back(back_id):
		return false
	return GameState.is_level_completed(ContentService.world_range(back_id).y)


func unlocked_back_ids() -> Array:
	var out: Array = []
	for b in ContentService.tile_backs():
		if is_back_unlocked(str(b.id)):
			out.append(str(b.id))
	return out


func equipped_back() -> String:
	## "" = no back: boards appear face-up at once, as before tile backs existed.
	var id := str(GameState.data.cosmetics.get("equipped_back", ""))
	return id if is_back_unlocked(id) else ""


func equip_back(back_id: String) -> bool:
	## back_id "" takes the back off.
	if back_id != "" and not is_back_unlocked(back_id):
		return false
	GameState.data.cosmetics.equipped_back = back_id
	GameState.save_now()
	AnalyticsService.track("tile_back_equipped", {"back": back_id if back_id != "" else "none"})
	return true
