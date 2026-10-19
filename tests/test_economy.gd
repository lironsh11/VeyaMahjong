extends TestCase
## Booster economy: grants are idempotent, balances never go negative, coins come only from
## first clears / dailies / ads / purchases, and helpers never soft-lock a board.

func _reset() -> void:
	FeatureFlags.clear_overrides()
	SaveService.save_dir = "user://test_run"
	SaveService.delete_all()
	GameState.data = GameState.defaults()
	DailyService.today_override = ""
	EconomyService.reload_config()
	EconomyService._apply_start_grants()


func test_start_grant_once() -> void:
	_reset()
	var start: Dictionary = EconomyService.cfg.start_grant
	check_eq(EconomyService.coins(), int(start.coins))
	check_eq(EconomyService.count("hint"), int(start.hint))
	EconomyService._apply_start_grants()
	check_eq(EconomyService.coins(), int(start.coins), "start pack never granted twice")


func test_ledger_idempotency_and_limits() -> void:
	_reset()
	var c := EconomyService.coins()
	check(EconomyService.grant("t:1", {"coins": 10, "undo": 2}, "test"))
	check(not EconomyService.grant("t:1", {"coins": 10, "undo": 2}, "test"), "same id refused")
	check_eq(EconomyService.coins(), c + 10)
	EconomyService.grant("t:big", {"coins": 99999999}, "test")
	check_eq(EconomyService.coins(), int(EconomyService.cfg.limits.max_coins), "clamped to the limit")


func test_buy_and_consume() -> void:
	_reset()
	GameState.data.economy.coins = 100
	check(not EconomyService.buy("hint", 1), "cannot buy without enough coins")
	check_eq(EconomyService.coins(), 100, "nothing spent on failure")
	GameState.data.economy.coins = 1000
	var before := EconomyService.count("hint")
	check(EconomyService.buy("hint", 5))
	check_eq(EconomyService.count("hint"), before + 5)
	check_eq(EconomyService.coins(), 1000 - EconomyService.price("hint", 5))
	check(not EconomyService.buy("hint", 3), "unsold pack size refused")
	GameState.data.economy.inv.undo = 1
	check(EconomyService.consume("undo"))
	check(not EconomyService.consume("undo"), "never below zero")
	check_eq(EconomyService.count("undo"), 0)
	FeatureFlags.set_override("economy_enabled", false)
	check(EconomyService.consume("undo"), "economy off: helpers are free")
	check_eq(EconomyService.count("undo"), 0, "and nothing is spent")


func test_existing_players_get_welcome_once() -> void:
	_reset()
	var old := {"schema_version": 1, "settings": {}, "progress": {"completed": {"1": {"t": 0}}, "light_sources": ["level:1"]}}
	GameState.data = GameState.migrate(old)
	check(bool(GameState.data.economy.legacy_player), "v1 save marked as an existing player")
	check(EconomyService.welcome_notice_pending(), "explained once on Home")
	EconomyService._apply_start_grants()
	var expect := int(EconomyService.cfg.start_grant.coins) + int(EconomyService.cfg.legacy_welcome_grant.coins)
	check_eq(EconomyService.coins(), expect, "start + welcome")
	EconomyService._apply_start_grants()
	check_eq(EconomyService.coins(), expect, "welcome never repeats")
	check_eq(int(GameState.migrate(GameState.data).economy.coins), expect, "a v2 save is not migrated again")


func test_first_clear_coins_world_bonus_and_replays() -> void:
	_reset()
	var c0 := EconomyService.coins()
	var r := ProgressionService.complete_level(3, {"moves": 5, "hints": 0})
	check_eq(int(r.coins), EconomyService.level_reward(3))
	check_eq(EconomyService.coins(), c0 + EconomyService.level_reward(3))
	var r2 := ProgressionService.complete_level(3, {"moves": 5, "hints": 0})
	check_eq(int(r2.coins), 0, "replays pay nothing")
	var last := int(ContentService.worlds[0].levels[1])
	var r3 := ProgressionService.complete_level(last, {"moves": 5, "hints": 0})
	check_eq(int(r3.world_bonus), EconomyService.reward("world_complete"), "world bonus on the last level")
	check(EconomyService.level_reward(120) > EconomyService.level_reward(10), "later worlds pay more")


func test_daily_and_tasks_coins_once_per_date() -> void:
	_reset()
	DailyService.today_override = "2026-10-19"
	var c0 := EconomyService.coins()
	ProgressionService.complete_daily("2026-10-19", {"moves": 1, "hints": 0})
	ProgressionService.complete_daily("2026-10-19", {"moves": 1, "hints": 0})
	check_eq(EconomyService.coins(), c0 + EconomyService.reward("daily_first_clear"), "daily coins once")


func test_reset_regrants_start_only() -> void:
	_reset()
	GameState.data.economy.legacy_player = true
	EconomyService._apply_start_grants()
	GameState.reset_local_data()
	check_eq(EconomyService.coins(), int(EconomyService.cfg.start_grant.coins), "start pack again, no welcome")


func test_assist_policy() -> void:
	var a := {"free_undos_used": 0, "rescue_shuffles_used": 0}
	check(AssistPolicy.undo_cost(a, 2, 0, true).free, "first undo free")
	a.free_undos_used = 2
	check(not AssistPolicy.undo_cost(a, 2, 0, true).allowed, "then needs an Undo booster")
	check(AssistPolicy.undo_cost(a, 2, 1, true).allowed and not AssistPolicy.undo_cost(a, 2, 1, true).free)
	check(AssistPolicy.undo_cost(a, 2, 0, false).free, "economy off: always free")
	check(AssistPolicy.shuffle_cost(a, 1, true, 0, true).free, "free rescue shuffle when stuck")
	check(not AssistPolicy.shuffle_cost(a, 1, false, 0, true).allowed, "not while the board is clearable")
	a.rescue_shuffles_used = 1
	check(not AssistPolicy.shuffle_cost(a, 1, true, 0, true).allowed, "only once per board")
	var one := PackedInt32Array([1])
	check(AssistPolicy.hint_should_charge({"tiles": one, "dead": false}, true))
	check(not AssistPolicy.hint_should_charge({"tiles": PackedInt32Array()}, true), "nothing shown, no charge")
	check(not AssistPolicy.hint_should_charge({"tiles": one, "dead": true}, true), "dead-end hint free")
	check(not AssistPolicy.hint_should_charge({"tiles": one, "repeat": true}, true), "repeat free")


func test_continue_cost() -> void:
	var a := {"continues_used": 0}
	var costs := [0, 100, 200]
	check(AssistPolicy.continue_cost(a, costs, 0, true).free, "first continue of a board is free")
	a.continues_used = 1
	var c := AssistPolicy.continue_cost(a, costs, 50, true)
	check(not c.allowed and int(c.coins) == 100, "second costs 100, not affordable with 50")
	check(AssistPolicy.continue_cost(a, costs, 100, true).allowed)
	a.continues_used = 7
	check_eq(int(AssistPolicy.continue_cost(a, costs, 999, true).coins), 200, "last price repeats")
	check(AssistPolicy.continue_cost(a, costs, 0, false).free, "economy off: always free")


func test_session_assists_roundtrip() -> void:
	var L := ContentService.get_level(5)
	var s := GameSession.start(L)
	s.assists.free_undos_used = 2
	s.assists.rescue_shuffles_used = 1
	var r := GameSession.restore(L, s.to_dict())
	check_eq(int(r.assists.free_undos_used), 2, "quitting cannot refill free undos")
	var old := s.to_dict()
	old.erase("assists")
	var r2 := GameSession.restore(L, old)
	check(r2 != null and int(r2.assists.free_undos_used) == 0, "snapshots from before the economy still restore")


func test_hint_counted_only_when_shown() -> void:
	# The hint statistic feeds no-hint records and a daily task; a request alone must not count.
	var L := ContentService.get_level(2)
	var s := GameSession.start(L)
	var c := BoardController.new(s, "level", false)
	c._on_hint_done({"tiles": PackedInt32Array(), "safe": false, "dead": false}, c._gen)
	check_eq(int(s.stats.hints), 0, "nothing shown -> not counted")
