extends Node
## Owner of all persistent player data. Other services read/write through here so there is
## exactly one save envelope and one migration path.
##
## Note: JSON numbers come back as floats; accessors coerce to int where it matters.

signal settings_changed(key: String)
signal progress_changed
signal data_reset

const SETTINGS_REV := 1  ## bump with a one-time step in migrate()
const DEFAULT_SETTINGS := {
	"locale": "auto",
	"music_volume": 0.7,
	"sfx_volume": 0.9,
	"music_on": true,
	"sfx_on": true,
	"haptics": true,
	"high_contrast": false,
	"large_tiles": false,
	"reduced_motion": false,
	"graphics": "auto",        # auto | low | standard
	"highlight_free": false,   # dim tiles that cannot be picked (opt-in assist: it gives away
	                           # which tiles are free, which removes most of the challenge)
	"soften_background": false,
	"show_timer": false,       # optional personal statistic, hidden by default
}

var data: Dictionary = {}
var _save_queued: bool = false
var loaded_from: String = ""


func _ready() -> void:
	load_game()


static func defaults() -> Dictionary:
	return {
		"schema_version": 6,
		"settings_rev": SETTINGS_REV,
		"created_unix": int(Time.get_unix_time_from_system()),
		"tutorial_done": false,
		"first_open_logged": false,
		# `open`: levels unlocked although the level before them isn't completed (a 1.0 player who
		# had reached a world keeps it open). `level_ids`: 2 = 1.1.0 numbering (100 per world).
		"progress": {"completed": {}, "light_sources": [], "open": [], "level_ids": 2, "new_levels_notice": false},
		"bloom": {"seen": []},
		# `granted`: themes and tile backs earned under the 1.0 unlock levels (kept for good).
		"cosmetics": {"equipped_theme": "classic", "seen_themes": ["classic"], "equipped_back": "", "granted": []},
		"entitlements": {},
		"processed_transactions": [],
		"ads": {"reward_grants": [], "rewarded_day": "", "rewarded_count": 0, "rewarded_counts": {},
			"placement_seq": {}, "last_fullscreen_unix": 0,
			"interstitial_day": "", "interstitial_count": 0, "levels_since_interstitial": 0},
		# Coins and boosters. Balances start at zero; the start pack (and the one-time welcome
		# pack for players from before the economy) is applied by EconomyService.grant().
		"economy": {"coins": 0, "inv": {"hint": 0, "shuffle": 0, "undo": 0, "extra_slot": 0}, "ledger": {},
			"legacy_player": false, "welcome_notice_pending": false, "clock_hw_day": ""},
		"daily": {"completed": {}, "tasks_date": "", "task_stats": {}, "tasks_claimed": false},
		# Win streak: consecutive first-try wins of new levels (ProgressionService). `run`
		# numbers each streak so milestone gifts are paid once per streak; `attempt` is the
		# level whose fresh attempt is in progress (a second fresh start there is a retry).
		"streak": {"count": 0, "best": 0, "run": 0, "attempt": 0},
		"active_session": {},
		# Play Together and Board Studio (schema 5): each has its own resume slot, so neither can
		# overwrite a level in progress. Names stay on the device. Studio boards are share codes.
		"duet_session": {},
		"studio_session": {},
		"duet": {"players": [{"name": "", "color": 0}, {"name": "", "color": 1}], "first": 0, "wins": 0, "games": 0,
			"best": {}, "seen": false, "difficulty": "easy"},
		"studio": {"boards": [], "made": 0, "seen": false},
		"settings": DEFAULT_SETTINGS.duplicate(),
		"privacy": {"analytics_consent": "unset", "ads_consent": "unset", "notice_seen": false},
		"stats": {"boards_completed": 0, "matches": 0, "hints": 0, "shuffles": 0, "undos": 0},
	}


static func _deep_fill(target: Dictionary, defs: Dictionary) -> void:
	## Adds missing keys from defaults without overwriting existing player data.
	for k in defs:
		if not target.has(k):
			target[k] = defs[k].duplicate(true) if typeof(defs[k]) in [TYPE_DICTIONARY, TYPE_ARRAY] else defs[k]
		elif typeof(defs[k]) == TYPE_DICTIONARY and typeof(target[k]) == TYPE_DICTIONARY and k != "completed" and k != "task_stats" and k != "entitlements":
			_deep_fill(target[k], defs[k])


static func migrate(payload: Dictionary) -> Dictionary:
	## Upgrades older save payloads in place. Add one step per schema bump.
	var v := int(payload.get("schema_version", 0))
	if v < 1:
		# v0 (pre-release prototype) stored completed levels as a plain list.
		var prog: Variant = payload.get("progress", {})
		if typeof(prog) == TYPE_DICTIONARY and typeof(prog.get("completed")) == TYPE_ARRAY:
			var as_dict := {}
			for id in prog.completed:
				as_dict[str(int(id))] = {"t": 0, "best_moves": 0, "no_hint": false}
			prog.completed = as_dict
		v = 1
	if v < 2:
		# v1 saves come from before the booster economy (free helpers): a one-time welcome
		# pack is granted by EconomyService and explained once on Home.
		payload["economy"] = {"legacy_player": true, "welcome_notice_pending": true}
		v = 2
	if v < 3:
		# v2 saves come from before tray play: no win streak yet (starts at 0), and the
		# Extra Slot booster joins the inventory (the intro gift is an EconomyService grant).
		payload["streak"] = {"count": 0, "best": 0, "run": 0, "attempt": 0}
		v = 3
	if v < 4:
		# Levels 4-150 were rebuilt as screen-filling boards (2026-10-19): a level board saved
		# mid-game belongs to the old geometry, so it starts fresh. Progress, stars and coins stay.
		var act: Variant = payload.get("active_session")
		if typeof(act) == TYPE_DICTIONARY and str(act.get("mode", "")) == "level":
			payload["active_session"] = {}
		v = 4
	if v < 5:
		# Play Together and Board Studio: new sections and resume slots only (filled from defaults).
		v = 5
	if v < 6:
		# 1.1.0: every world grew from 50 to 100 levels, so every saved level id moves.
		migrate_level_ids(payload)
		v = 6
	payload["schema_version"] = v
	# One-time settings revisions (no schema change: settings are free-form).
	var settings: Variant = payload.get("settings")
	if int(payload.get("settings_rev", 0)) < 1 and typeof(settings) == TYPE_DICTIONARY:
		# Rev 1: "Dim Blocked Tiles" became opt-in. Every earlier save stored the old default
		# (on), so turn it off once; a player who re-enables it afterwards keeps it.
		settings["highlight_free"] = false
	payload["settings_rev"] = SETTINGS_REV
	_deep_fill(payload, defaults())
	return payload


## The 1.0 unlock levels of the cosmetics whose unlock level moved in 1.1.0 (frozen: a save
## earned these under the 1.0 numbering). Themes by theme id, tile backs by world id.
const LEGACY_UNLOCK_LEVELS := {
	"ocean": 50, "nocturne": 100,
	"jade_bamboo_valley": 200, "sunset_lotus_palace": 250, "frostlight_village": 300,
}


static func migrate_level_ids(payload: Dictionary) -> void:
	## One-time move of every level id in a 1.0 save to the 1.1.0 numbering (LevelCatalog.new_id:
	## 1.0 level 50(w-1)+k is now 100(w-1)+k). New collections are built instead of renaming in
	## place, so "level:51" -> "level:101" can never collide with the old "level:101". Runs once:
	## the schema version, and progress.level_ids = 2 as a second guard.
	var prog: Variant = payload.get("progress")
	if typeof(prog) != TYPE_DICTIONARY:
		return
	if int(prog.get("level_ids", 1)) >= 2:
		return
	var old_done := {}
	if typeof(prog.get("completed")) == TYPE_DICTIONARY:
		var moved := {}
		for k in prog.completed:
			if not str(k).is_valid_int():
				continue
			old_done[int(k)] = true
			moved[str(LevelCatalog.new_id(int(k)))] = prog.completed[k]
		prog.completed = moved
	if typeof(prog.get("light_sources")) == TYPE_ARRAY:
		prog.light_sources = (prog.light_sources as Array).map(func(s: Variant) -> String: return moved_level_key(str(s)))
	# A 1.0 player who finished a world had the next world open; it stays open although the
	# world's 50 new levels come before it now.
	var opened: Array = []
	for w in range(2, LevelCatalog.WORLDS + 1):
		if old_done.has((w - 1) * LevelCatalog.LEGACY_PER_WORLD):
			opened.append((w - 1) * LevelCatalog.PER_WORLD + 1)
	prog["open"] = opened
	prog["level_ids"] = 2
	prog["new_levels_notice"] = not old_done.is_empty()
	# Themes and tile backs earned under their 1.0 unlock levels stay earned.
	var cos: Variant = payload.get("cosmetics")
	if typeof(cos) == TYPE_DICTIONARY:
		var granted: Array = cos.get("granted", []) if typeof(cos.get("granted")) == TYPE_ARRAY else []
		for id in LEGACY_UNLOCK_LEVELS:
			if old_done.has(int(LEGACY_UNLOCK_LEVELS[id])) and not granted.has(id):
				granted.append(id)
		cos["granted"] = granted
	# Coin and ad grants per level ("level:N", "ad:win_double:level:N"): a moved level keeps its
	# paid-once record, and the new level that took its old number can pay out.
	var econ: Variant = payload.get("economy")
	if typeof(econ) == TYPE_DICTIONARY and typeof(econ.get("ledger")) == TYPE_DICTIONARY:
		var ledger := {}
		for k in econ.ledger:
			ledger[moved_level_key(str(k))] = econ.ledger[k]
		econ.ledger = ledger
	var ads: Variant = payload.get("ads")
	if typeof(ads) == TYPE_DICTIONARY and typeof(ads.get("reward_grants")) == TYPE_ARRAY:
		ads.reward_grants = (ads.reward_grants as Array).map(func(s: Variant) -> String: return moved_level_key(str(s)))
	var streak: Variant = payload.get("streak")
	if typeof(streak) == TYPE_DICTIONARY and int(streak.get("attempt", 0)) > 0:
		streak.attempt = LevelCatalog.new_id(int(streak.attempt))
	# A level board in progress resumes on its new number (same board, same tiles).
	var act: Variant = payload.get("active_session")
	if typeof(act) == TYPE_DICTIONARY and str(act.get("mode", "")) == "level" and int(act.get("level_id", 0)) > 0:
		var id := LevelCatalog.new_id(int(act.level_id))
		act.level_id = id
		act.key = moved_level_key(str(act.get("key", "")))
		if typeof(act.get("session")) == TYPE_DICTIONARY:
			act.session.level_key = moved_level_key(str(act.session.get("level_key", "")))


static func moved_level_key(key: String) -> String:
	## "level:N" (also inside grant ids such as "ad:win_double:level:N") with N in 1.1.0 numbering.
	var at := key.rfind("level:")
	if at < 0:
		return key
	var tail := key.substr(at + 6)
	if not tail.is_valid_int():
		return key
	return key.substr(0, at + 6) + str(LevelCatalog.new_id(int(tail)))


func load_game() -> void:
	var res: Dictionary = SaveService.read()
	loaded_from = res.source
	if res.payload == null:
		data = defaults()
	else:
		data = migrate(res.payload)


func save_now() -> bool:
	_save_queued = false
	return SaveService.write(data)


func request_save() -> void:
	## Coalesces several changes within a frame into one write.
	if _save_queued:
		return
	_save_queued = true
	save_now.call_deferred()


func reset_local_data() -> void:
	## Explicitly confirmed by the player. Clears local progress only; platform entitlements
	## are re-applied from the store via Restore Purchases.
	var keep_settings: Dictionary = data.get("settings", {}).duplicate(true)
	SaveService.delete_all()
	data = defaults()
	data.settings = keep_settings
	save_now()
	data_reset.emit()
	progress_changed.emit()


# --- settings -----------------------------------------------------------------------

func setting(key: String) -> Variant:
	return data.settings.get(key, DEFAULT_SETTINGS.get(key))


func set_setting(key: String, value: Variant) -> void:
	if data.settings.get(key) == value:
		return
	data.settings[key] = value
	request_save()
	settings_changed.emit(key)


# --- progress helpers ---------------------------------------------------------------

func completed_levels() -> Dictionary:
	return data.progress.completed


func is_level_completed(id: int) -> bool:
	return data.progress.completed.has(str(id))


func highest_completed() -> int:
	var hi := 0
	for k in data.progress.completed:
		hi = maxi(hi, int(k))
	return hi


func is_level_unlocked(id: int) -> bool:
	## Linear journey: a level opens when the previous one is completed. Completed levels
	## always stay replayable; progress.open holds the world starts a 1.0 save had reached.
	return id == 1 or is_level_completed(id) or is_level_completed(id - 1) or is_level_opened(id)


func is_level_opened(id: int) -> bool:
	var opened: Variant = data.progress.get("open", [])
	if typeof(opened) != TYPE_ARRAY:
		return false
	for x in opened:
		if int(x) == id:  # JSON brings ints back as floats
			return true
	return false


func next_level(max_level: int) -> int:
	## The level after the furthest one completed, so a 1.0 player continues where they were
	## rather than at the levels 1.1.0 added to earlier worlds (those wait on the world map).
	## Once the last level is done: the first level still open, or the last level.
	var hi := highest_completed()
	if hi < max_level:
		return hi + 1
	for id in range(1, max_level + 1):
		if not is_level_completed(id):
			return id
	return max_level


func lights() -> int:
	return data.progress.light_sources.size()


func has_light_source(source: String) -> bool:
	return data.progress.light_sources.has(source)


func stat(key: String) -> int:
	return int(data.stats.get(key, 0))


func add_stat(key: String, amount: int = 1) -> void:
	data.stats[key] = stat(key) + amount


# --- active board snapshot ----------------------------------------------------------

func set_active_session(d: Dictionary) -> void:
	data.active_session = d
	request_save()


func clear_active_session() -> void:
	data.active_session = {}
	request_save()


func active_session() -> Dictionary:
	var s: Variant = data.get("active_session", {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


# --- resume slots (one board per kind of play) ---------------------------------------

const SESSION_SLOTS: PackedStringArray = ["active_session", "duet_session", "studio_session"]


func session(slot: String) -> Dictionary:
	var s: Variant = data.get(slot, {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


func set_session(slot: String, d: Dictionary) -> void:
	data[slot] = d
	request_save()


func clear_session(slot: String) -> void:
	data[slot] = {}
	request_save()
