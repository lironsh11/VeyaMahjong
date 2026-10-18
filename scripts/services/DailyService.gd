extends Node
## Daily Puzzle and optional Daily Tasks, fully offline.
##
## Dates are LOCAL calendar dates ("YYYY-MM-DD"). Puzzles are deterministic per date
## (DailyGenerator), so a clock change or timezone/DST shift just means a different date is
## "today"; nothing is invalidated and completions are keyed by date so each date can be
## claimed once. Players may freely play the last ARCHIVE_DAYS days, so missing a day never
## costs anything and there is no streak to lose.

signal tasks_changed

const ARCHIVE_DAYS := 30
const TASKS_PATH := "res://data/config/daily_tasks.json"

var _boards: Dictionary = {}     # date -> LevelDefinition (memory cache)
var _task_defs: Array = []
var _per_day: int = 3
var today_override: String = ""  # tests only


func _ready() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(TASKS_PATH))
	if typeof(j) == TYPE_DICTIONARY:
		_task_defs = j.get("tasks", [])
		_per_day = int(j.get("per_day", 3))


func today() -> String:
	if today_override != "":
		return today_override
	return Time.get_date_string_from_system(false)


static func add_days(date: String, days: int) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	return Time.get_date_string_from_unix_time(unix + days * 86400)


static func days_between(a: String, b: String) -> int:
	var ua := Time.get_unix_time_from_datetime_string(a + "T12:00:00")
	var ub := Time.get_unix_time_from_datetime_string(b + "T12:00:00")
	return int(round((ub - ua) / 86400.0))


func is_playable(date: String) -> bool:
	if not DailyGenerator.is_valid_date(date):
		return false
	var d := days_between(date, today())
	return d >= 0 and d <= ARCHIVE_DAYS


func is_completed(date: String) -> bool:
	return GameState.data.daily.completed.has(date)


func board_cached(date: String) -> LevelDefinition:
	return _boards.get(date)


func request_board(date: String, on_ready: Callable) -> void:
	## Generation + validation run on a worker thread; never blocks the UI.
	if _boards.has(date):
		on_ready.call(_boards[date])
		return
	Jobs.run(func() -> LevelDefinition: return DailyGenerator.build(date),
		func(L: Variant) -> void:
			if L != null:
				_boards[date] = L
			on_ready.call(L))


func level_for_key(key: String) -> LevelDefinition:
	## Synchronous fallback used when restoring a saved daily session.
	var date := key.trim_prefix("daily:")
	if not _boards.has(date):
		var L := DailyGenerator.build(date)
		if L == null:
			return null
		_boards[date] = L
	return _boards[date]


# --- tasks --------------------------------------------------------------------------

func _ensure_day() -> void:
	var d: Dictionary = GameState.data.daily
	if str(d.get("tasks_date", "")) != today():
		d.tasks_date = today()
		d.task_stats = {}
		d.tasks_claimed = false
		GameState.request_save()


func tasks_today() -> Array:
	_ensure_day()
	var pool := _task_defs.duplicate()
	var rng := SeededRng.new(SeededRng.hash_string("tasks|" + today()))
	rng.shuffle(pool)
	return pool.slice(0, mini(_per_day, pool.size()))


func task_progress(task: Dictionary) -> int:
	_ensure_day()
	return mini(int(GameState.data.daily.task_stats.get(task.stat, 0)), int(task.target))


func all_tasks_done() -> bool:
	for t in tasks_today():
		if task_progress(t) < int(t.target):
			return false
	return true


func tasks_claimed() -> bool:
	_ensure_day()
	return bool(GameState.data.daily.tasks_claimed)


func claim_tasks_reward() -> bool:
	if not FeatureFlags.enabled("daily_tasks_enabled") or not all_tasks_done() or tasks_claimed():
		return false
	GameState.data.daily.tasks_claimed = true
	var ok := ProgressionService.award_light("tasks:" + today())
	GameState.save_now()
	tasks_changed.emit()
	return ok


func _bump(stat: String, amount: int = 1) -> void:
	_ensure_day()
	var s: Dictionary = GameState.data.daily.task_stats
	s[stat] = int(s.get(stat, 0)) + amount


func record_match(face: String) -> void:
	_bump("matches")
	if MahjongRules.is_flower(face):
		_bump("flowers_cleared", 2)
	elif MahjongRules.is_season(face):
		_bump("seasons_cleared", 2)
	GameState.add_stat("matches")


func record_board_complete(hints_used: int, is_daily: bool) -> void:
	_bump("boards_completed")
	if hints_used == 0:
		_bump("boards_no_hints")
	if is_daily:
		_bump("daily_completed")
	GameState.request_save()
	tasks_changed.emit()
