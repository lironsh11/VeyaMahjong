extends TestCase
## Play Together (2026-11): turns worked out from the move history, pair credit and Team-ups,
## chain combos, separate resume slots, free helper allowances, and that a shared board never
## touches progression (coins, Lights, streak, levels, Daily Tasks, stats).


func _reset() -> void:
	FeatureFlags.clear_overrides()
	SaveService.save_dir = "user://test_run"
	SaveService.delete_all()
	GameState.data = GameState.defaults()
	DailyService.today_override = "2026-11-14"
	StudioBoard.clear_cache()


static func _sample() -> LevelDefinition:
	return StudioBoard.from_code(StudioBoard.SAMPLE_CODE).level


static func _picks(L: LevelDefinition) -> PackedInt32Array:
	return TraySolver.flatten(L.solution)


func test_turn_passes_on_every_pick() -> void:
	var L := _sample()
	var s := GameSession.start(L)
	var picks := _picks(L)
	for first in [0, 1]:
		s = GameSession.start(L)
		check_eq(DuetTurns.current_player(s.history, first), first, "player %d starts" % first)
		for k in 6:
			s.tap(picks[k])
			check_eq(DuetTurns.current_player(s.history, first), (first + k + 1) % 2, "after pick %d" % k)


func test_team_actions_keep_the_turn_and_undo_gives_it_back() -> void:
	var L := _sample()
	var s := GameSession.start(L)
	var picks := _picks(L)
	s.tap(picks[0])
	s.tap(picks[1])  # finishes the first pair of the witness
	var who := DuetTurns.current_player(s.history, 0)
	check_eq(who, 0, "two picks: player 0 again")
	check(s.shuffle().ok, "shuffle works")
	check_eq(DuetTurns.current_player(s.history, 0), who, "a shuffle doesn't pass the turn")
	s.undo()  # undo the shuffle
	s.undo()  # undo the last pick: its player picks again
	check_eq(DuetTurns.current_player(s.history, 0), 1 - who, "undo gives the turn back")


func test_send_back_keeps_the_turn() -> void:
	var L := _sample()
	var s := GameSession.start(L)
	# Fill the tray with unmatched tiles until it is full.
	var seen := {}
	for i in s.state.free_tiles():
		if s.failed:
			break
		if seen.has(s.state.keys[i]):
			continue
		seen[s.state.keys[i]] = true
		s.tap(i)
	check(s.failed, "the tray filled up")
	var who := DuetTurns.current_player(s.history, 1)
	check(not s.send_back(3).is_empty())
	check_eq(DuetTurns.current_player(s.history, 1), who, "sending tiles back doesn't pass the turn")


func test_credit_and_team_ups() -> void:
	var L := _sample()
	var s := GameSession.start(L)
	var a: int = L.solution[0].x
	var b: int = L.solution[0].y
	s.tap(a)             # player 0 puts a tile in the tray
	check(not DuetTurns.is_team_up(s.history, 0))
	s.tap(b)             # player 1 finishes the pair: a Team-up
	check(DuetTurns.is_team_up(s.history, 0), "finishing the partner's pair is a Team-up")
	s.award(Scoring.points_for(1) + DuetTurns.TEAM_UP_BONUS, 1)
	var c: int = L.solution[1].x
	var d: int = L.solution[1].y
	s.tap(c)             # player 0
	s.tap(d)             # player 1 finishes it, but player 0 placed c... still a Team-up
	check(DuetTurns.is_team_up(s.history, 0))
	s.award(Scoring.points_for(2), 2)
	var sum := DuetTurns.summary(s.history, 0)
	check_eq(sum.finished, [0, 2], "a pair is finished by whoever picked its second tile")
	check_eq(sum.pairs, [2, 2], "a Team-up counts for both players")
	check_eq(sum.team_ups, [0, 2])
	check_eq(int(sum.points[0]) + int(sum.points[1]), s.score, "player points add up to the team score")
	s.undo()
	sum = DuetTurns.summary(s.history, 0)
	check_eq(int(sum.points[0]) + int(sum.points[1]), s.score, "still adds up after undo")
	check_eq(DuetTurns.tray_owners(s.history, 0, s.tray), PackedInt32Array([0]), "the tray tile is player 0's")


func test_own_pair_is_not_a_team_up() -> void:
	# Player 0 places a tile; both pick other tiles; player 0 finishes their own pair.
	var L := _sample()
	var s := GameSession.start(L)
	var picks := _picks(L)
	var placed := {}
	var own_found := false
	for k in picks.size():
		var who := DuetTurns.current_player(s.history, 0)
		var r := s.tap(picks[k])
		if r.r == GameSession.Tap.MATCHED:
			var placer := int(placed.get(int(r.partner), -1))
			check_eq(DuetTurns.is_team_up(s.history, 0), placer != who, "team-up iff the other player placed the twin")
			own_found = own_found or placer == who
		elif r.r == GameSession.Tap.TO_TRAY:
			placed[picks[k]] = who
		else:
			break
	check(s.completed, "the solution clears the board when played alternately")


func test_chain_combo() -> void:
	check_eq(BoardController.next_combo(0, true, 999999), 1)
	check_eq(BoardController.next_combo(3, true, 999999), 4, "a chain ignores time")
	check_eq(BoardController.next_combo(3, false, 500), 4)
	check_eq(BoardController.next_combo(3, false, BoardController.COMBO_WINDOW_MS + 1), 1, "timed combo still expires")


func test_free_play_allowance() -> void:
	var limits := {"hint": 3, "undo": 3, "shuffle": 2, "send_back": 1}
	var a := GameSession.new().assists
	check_eq(AssistPolicy.free_play_left("hint", a, limits), 3)
	for k in 3:
		AssistPolicy.free_play_use("hint", a)
	check_eq(AssistPolicy.free_play_left("hint", a, limits), 0, "used up")
	AssistPolicy.free_play_use("send_back", a)
	check_eq(AssistPolicy.free_play_left("send_back", a, limits), 0)
	check_eq(AssistPolicy.free_play_left("coins", a, limits), 0, "unknown helpers have none")
	var cfg := EconomyService.free_play_limits()
	for k in ["hint", "undo", "shuffle", "send_back"]:
		check(int(cfg.get(k, 0)) > 0, "economy.json gives some %s" % k)
	# Saved with the board, so quitting can't refill it; old snapshots without it still load.
	var L := _sample()
	var s := GameSession.start(L)
	AssistPolicy.free_play_use("hint", s.assists)
	check_eq(int(GameSession.restore(L, s.to_dict()).assists.hints_used), 1)
	var old := s.to_dict()
	(old.assists as Dictionary).erase("hints_used")
	check_eq(int(GameSession.restore(L, old).assists.hints_used), 0)


func test_resume_slots_are_independent() -> void:
	_reset()
	GameState.set_active_session({"mode": "level", "key": "level:7", "level_id": 7, "session": {}})
	var L := _sample()
	var c := BoardController.new(GameSession.start(L), "duet")
	c.slot = FreePlayService.SLOT_DUET
	c.extra = {"code": StudioBoard.SAMPLE_CODE, "first": 1}
	c.save()
	check_eq(str(GameState.active_session().get("key", "")), "level:7", "a duet board never replaces the level in progress")
	var d := GameState.session(FreePlayService.SLOT_DUET)
	check_eq(str(d.get("code", "")), StudioBoard.SAMPLE_CODE)
	check_eq(int(d.get("first", -1)), 1, "who started is saved with the board")
	check(GameState.session(FreePlayService.SLOT_STUDIO).is_empty())
	GameState.clear_session(FreePlayService.SLOT_DUET)
	check_eq(str(GameState.active_session().get("key", "")), "level:7")


func test_migration_from_v4_keeps_the_level_in_progress() -> void:
	var v4 := GameState.defaults()
	v4.schema_version = 4
	v4.erase("duet")
	v4.erase("studio")
	v4.erase("duet_session")
	v4.active_session = {"mode": "level", "key": "level:9", "level_id": 9, "session": {}}
	var m := GameState.migrate(v4)
	check_eq(int(m.schema_version), int(GameState.defaults().schema_version))
	check_eq(str(m.active_session.key), "level:9")
	check(typeof(m.duet) == TYPE_DICTIONARY and (m.duet.players as Array).size() == 2, "duet section added")
	check(typeof(m.studio) == TYPE_DICTIONARY and (m.studio.boards as Array).is_empty(), "studio section added")


func test_shared_board_never_touches_progress() -> void:
	_reset()
	var before := {"coins": EconomyService.coins(), "lights": GameState.lights(), "levels": GameState.completed_levels().size(),
		"streak": ProgressionService.streak_count(), "matches": GameState.stat("matches"), "tasks": str(GameState.data.daily.task_stats)}
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var board := BoardView.new()
	root.add_child(board)
	board.size = Vector2(540, 800)
	var L := _sample()
	var s := GameSession.start(L)
	board.setup(s.state, "classic")
	var c := BoardController.new(s, "duet")
	c.slot = FreePlayService.SLOT_DUET
	c.chain_combo = true
	c.attach_view(board)
	check(not c.tracked(), "duet boards are not tracked")
	for i in _picks(L):
		c._on_tap(i)
	check(s.completed, "cleared through the controller")
	check_eq(EconomyService.coins(), before.coins, "no coins")
	check_eq(GameState.lights(), before.lights, "no Lights")
	check_eq(GameState.completed_levels().size(), before.levels, "no levels")
	check_eq(ProgressionService.streak_count(), before.streak, "no streak")
	check_eq(GameState.stat("matches"), before.matches, "global match stats untouched")
	check_eq(str(GameState.data.daily.task_stats), before.tasks, "Daily Tasks untouched")
	check(GameState.active_session().is_empty(), "nothing in the level slot")
	root.remove_child(board)
	board.free()


func test_players_names_colours_and_records() -> void:
	_reset()
	check_eq(FreePlayService.player_name(0), LocalizationService.t("player_n", {"n": 1}), "default name follows the language")
	FreePlayService.set_player_name(0, "  Maya" + String.chr(0x1F600) + String.chr(0x202E) + "\n ")
	check_eq(FreePlayService.player_name(0), "Maya", "emoji, controls and direction overrides removed")
	FreePlayService.set_player_name(1, "A very long player name indeed")
	check_eq(FreePlayService.player_name(1).length(), DuetTurns.NAME_MAX)
	FreePlayService.set_player_color(0, FreePlayService.color_index(1))
	check(FreePlayService.color_index(0) != FreePlayService.color_index(1), "taking the partner's colour swaps them")
	var f1 := FreePlayService.game_started()
	var f2 := FreePlayService.game_started()
	check(f1 != f2, "who starts alternates")
	check(FreePlayService.record_duet_win("easy", 500), "first score is a best")
	check(not FreePlayService.record_duet_win("easy", 400))
	check_eq(FreePlayService.team_wins(), 2)
	var data := SaveService.write(GameState.data)
	check(data, "saves")


func test_my_boards() -> void:
	_reset()
	check_eq(FreePlayService.save_board("nonsense", false), "invalid")
	check_eq(FreePlayService.save_board(StudioBoard.SAMPLE_CODE, false), "saved")
	check_eq(FreePlayService.save_board(StudioBoard.SAMPLE_CODE, true), "exists")
	check_eq(FreePlayService.boards_made(), 1)
	for s in FreePlayService.MAX_BOARDS - 1:
		FreePlayService.save_board(StudioCode.encode({"family": "pyramid", "cols": 6, "layers": 3, "mode": "top", "tiles": 72, "seed": 100 + s}), true)
	check_eq(FreePlayService.boards().size(), FreePlayService.MAX_BOARDS)
	check_eq(FreePlayService.save_board(StudioCode.encode({"family": "pyramid", "cols": 6, "layers": 3, "mode": "top", "tiles": 72, "seed": 9}), true), "full", "a full list refuses, never drops")
	check(FreePlayService.record_studio_win(StudioBoard.SAMPLE_CODE, 900))
	check(FreePlayService.delete_board(StudioBoard.SAMPLE_CODE))
	check_eq(FreePlayService.find_board(StudioBoard.SAMPLE_CODE), -1)


func test_screens_build() -> void:
	# Smoke test: the three new screens build in English and Hebrew without script errors.
	_reset()
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for loc in ["en", "he"]:
		LocalizationService.set_locale(loc)
		for spec in [["duet", {}], ["studio", {"tab": "create"}], ["studio", {"tab": "mine"}], ["studio", {"tab": "code"}],
				["freeplay", {"kind": "duet", "code": StudioBoard.SAMPLE_CODE}], ["freeplay", {"kind": "studio", "code": StudioBoard.SAMPLE_CODE}]]:
			Router.params = spec[1]
			var scr: Control = load(Router.SCREENS[spec[0]]).instantiate()
			root.add_child(scr)
			check(scr.get_child_count() > 0, "%s %s built (%s)" % [spec[0], spec[1], loc])
			if spec[0] == "freeplay":
				check(scr.session != null and scr.board != null, "board ready")
				check_eq(scr.get("_turn_bar") != null, str(spec[1].kind) == "duet", "turn bar only when playing together")
			root.remove_child(scr)  # leaves the tree now (restores the ad banner), not at frame end
			scr.free()
	LocalizationService.set_locale("en")
	Router.params = {}
	_reset()
