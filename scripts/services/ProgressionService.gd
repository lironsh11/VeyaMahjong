extends Node
## Earned progression. Everything here is idempotent and derived from immutable records:
## - A Veya Light is recorded by its SOURCE key ("level:12", "daily:2026-10-18",
##   "tasks:2026-10-18", "ad:<grant id>"). Recording the same source twice is a no-op, so
##   replays, double taps, crashes-and-reloads and duplicate callbacks cannot farm Lights.
## - Bloom discoveries unlocked = floor(lights / lights_per_discovery) (capped), and tile
##   theme unlocks are computed from progress + verified entitlements. Nothing is a mutable
##   balance that could go negative or be lost.

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
	var no_hint := int(stats.get("hints", 0)) == 0
	if first:
		completed[key] = {"t": int(Time.get_unix_time_from_system()), "best_moves": int(stats.get("moves", 0)), "no_hint": no_hint}
	else:
		var rec: Dictionary = completed[key]
		rec["no_hint"] = bool(rec.get("no_hint", false)) or no_hint
	var light := award_light("level:%d" % id) if first else false
	var result := _result(first, light, before_disc, before_themes)
	var w := ContentService.world_for_level(id)
	if first and not w.is_empty() and id == int(w.levels[1]):
		var nw := ContentService.world_for_level(id + 1)
		if not nw.is_empty() and nw.id != w.id:
			result["world_unlocked"] = nw.id
	_count_board(stats)
	GameState.save_now()
	return result


func complete_daily(date: String, stats: Dictionary) -> Dictionary:
	var before_disc := discoveries_unlocked_count()
	var before_themes := unlocked_theme_ids()
	var done: Dictionary = GameState.data.daily.completed
	var first := not done.has(date)
	if first:
		done[date] = {"t": int(Time.get_unix_time_from_system()), "moves": int(stats.get("moves", 0)), "hints": int(stats.get("hints", 0))}
	var light := award_light("daily:" + date) if first else false
	_count_board(stats)
	GameState.save_now()
	return _result(first, light, before_disc, before_themes)


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
		"world_unlocked": "",
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
