extends TestCase
## Engagement layer: score and stars, the win streak (first-try wins of new levels, its free
## extra slot and its fixed gifts), and the Extra Slot booster.

func _reset() -> void:
	FeatureFlags.clear_overrides()
	SaveService.save_dir = "user://test_run"
	SaveService.delete_all()
	GameState.data = GameState.defaults()
	EconomyService.reload_config()
	EconomyService._apply_start_grants()


func _clean() -> Dictionary:
	return {"moves": 10, "hints": 0, "undos": 0, "fails": 0, "retry": 0}


# --- score and stars -------------------------------------------------------------------

func test_points_and_stars() -> void:
	check_eq(Scoring.points_for(1), 10)
	check_eq(Scoring.points_for(4), 40)
	check_eq(Scoring.points_for(50), 100, "multiplier capped")
	check_eq(Scoring.base_score(20), 100, "10 pairs")
	check_eq(Scoring.clean_bonus(20, {"undos": 0, "fails": 0}), 50)
	check_eq(Scoring.clean_bonus(20, {"undos": 1}), 0, "an undo loses the clean bonus")
	check_eq(Scoring.clean_bonus(20, {"fails": 1}), 0, "a full tray loses it too")
	var relaxed := Scoring.final(100, 20, {})
	check_eq(int(relaxed.score), 150, "score + clean bonus")
	check_eq(int(relaxed.stars), 1, "no combos at all: 1 star")
	check_eq(int(Scoring.final(120, 20, {}).stars), 2, "a few combos: 2 stars")
	check_eq(int(Scoring.final(260, 20, {}).stars), 3, "steady combos: 3 stars")
	check_eq(int(Scoring.final(260, 20, {"undos": 2}).stars), 2, "without the bonus it drops a star")


func test_best_score_and_stars_are_kept() -> void:
	_reset()
	var s := _clean()
	s.score = 300
	s.stars = 2
	var r := ProgressionService.complete_level(1, s)
	check_eq(int(r.stars), 2)
	check(not bool(r.new_best), "a first clear is not a 'new best'")
	s.score = 200
	s.stars = 1
	r = ProgressionService.complete_level(1, s)
	check_eq(ProgressionService.level_stars(1), 2, "stars never go down")
	check_eq(int(r.best_score), 300)
	s.score = 500
	s.stars = 3
	r = ProgressionService.complete_level(1, s)
	check(bool(r.new_best))
	check_eq(ProgressionService.level_stars(1), 3)


# --- win streak ------------------------------------------------------------------------

func test_streak_counts_first_try_first_clears() -> void:
	_reset()
	for id in [1, 2]:
		check(not ProgressionService.start_attempt(id))
		var r := ProgressionService.complete_level(id, _clean())
		check_eq(int(r.streak), id)
	check_eq(ProgressionService.streak_count(), 2)
	var replay := ProgressionService.complete_level(1, _clean())
	check_eq(int(replay.streak), 0, "a replay is not counted")
	check_eq(ProgressionService.streak_count(), 2, "and does not break the streak")
	ProgressionService.start_attempt(3)
	var f := _clean()
	f.fails = 1
	check_eq(int(ProgressionService.complete_level(3, f).streak), 0, "a win after a full tray is not a first try")


func test_streak_breaks_on_fail_and_retry() -> void:
	_reset()
	for id in [1, 2, 3]:
		ProgressionService.start_attempt(id)
		ProgressionService.complete_level(id, _clean())
	check(ProgressionService.streak_bonus_active(), "3 in a row: extra slot bonus")
	check_eq(ProgressionService.break_streak("fail"), 3)
	check_eq(ProgressionService.streak_count(), 0)
	check_eq(ProgressionService.streak_best(), 3, "best is kept")
	check_eq(ProgressionService.break_streak("fail"), 0, "nothing to break twice")
	# A fresh restart of the level being attempted is a retry.
	ProgressionService.start_attempt(4)
	ProgressionService.complete_level(4, _clean())
	check_eq(ProgressionService.streak_count(), 1)
	check(not ProgressionService.start_attempt(5))
	check(ProgressionService.start_attempt(5), "second fresh start = retry")
	check_eq(ProgressionService.streak_count(), 0)
	check(not ProgressionService.start_attempt(1), "completed levels never count as retries")


func test_streak_gifts_paid_once_per_streak() -> void:
	_reset()
	var hints := EconomyService.count("hint")
	var gifts := 0
	for id in range(1, 8):
		ProgressionService.start_attempt(id)
		var r := ProgressionService.complete_level(id, _clean())
		gifts += Dictionary(r.streak_gift).size()
	check_eq(gifts, 2, "gifts at 5 and 7")
	check_eq(EconomyService.count("hint"), hints + 1)
	# A new streak can earn them again (new run id), the same streak never twice.
	ProgressionService.break_streak("fail")
	GameState.data.streak.count = 4
	ProgressionService.start_attempt(8)
	check(not Dictionary(ProgressionService.complete_level(8, _clean()).streak_gift).is_empty(), "new streak, new gift")


func test_migration_adds_streak() -> void:
	var old := {"schema_version": 2, "settings": {}, "economy": {"coins": 10, "inv": {"hint": 1}}}
	var m := GameState.migrate(old)
	check_eq(int(m.schema_version), GameState.defaults().schema_version)
	check_eq(int(m.streak.count), 0)
	check_eq(int(m.economy.inv.hint), 1, "inventory kept")
	check_eq(int(m.economy.inv.extra_slot), 0, "new booster starts at 0 before the intro gift")


# --- Extra Slot ------------------------------------------------------------------------

func test_extra_slot_economy() -> void:
	_reset()
	check(EconomyService.items().has("extra_slot"))
	check_eq(EconomyService.count("extra_slot"), 2, "intro gift for everyone")
	EconomyService._apply_start_grants()
	check_eq(EconomyService.count("extra_slot"), 2, "intro gift only once")
	check(EconomyService.price("extra_slot", 1) > 0, "sold for coins")


func test_extra_slot_in_session() -> void:
	var faces := ["circle_1", "circle_2", "circle_3", "circle_4", "circle_5", "circle_5", "circle_4", "circle_3", "circle_2", "circle_1"]
	var L := level_from_rows(["XXXXXXXXXX"], [], faces)
	var g := GameSession.start(L)
	for i in 4:
		g.tap(i)
	check(g.failed)
	check(g.add_slot(), "an extra slot rescues a full tray")
	check(not g.failed)
	check_eq(g.capacity, 5)
	check_eq(g.tap(4).r, GameSession.Tap.FAILED, "a 5th unmatched tile still loses")
	g.undo()
	check_eq(g.capacity, 5, "undo never takes the slot away")
	check(g.add_slot())
	check(not g.add_slot(), "at most two extra slots")
	var g2 := GameSession.restore(L, JSON.parse_string(JSON.stringify(g.to_dict())))
	check(g2 != null and g2.capacity == GameSession.MAX_CAPACITY, "capacity saved")
	var st := L.build_state()
	check_eq(TraySolver.new(100000, 0, 5).solve(st).result, BoardSolver.Result.SOLVED, "more room never hurts solvability")


func test_v4_migration_drops_old_level_board() -> void:
	# Levels were rebuilt as screen-filling boards: a level saved mid-game starts fresh, the
	# daily keeps its own key check, and progress is untouched.
	var old := {"schema_version": 3, "settings": {}, "progress": {"completed": {"5": {"t": 0, "stars": 2}}, "light_sources": ["level:5"]},
		"active_session": {"mode": "level", "key": "level:6", "level_id": 6, "session": {}}}
	var m := GameState.migrate(old)
	check(Dictionary(m.active_session).is_empty(), "old level board dropped")
	check(m.progress.completed.has("5"), "progress kept")
	var old2 := {"schema_version": 3, "settings": {}, "active_session": {"mode": "daily", "key": "daily:2026-10-19", "session": {}}}
	check_eq(str(GameState.migrate(old2).active_session.mode), "daily", "daily snapshot left to its own checks")
