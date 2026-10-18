class_name DifficultyAnalyzer
extends RefCounted
## Measures difficulty from several real board properties (not tile count alone):
## - opening free pairs and average available pairs along random plausible play
## - layer depth and stacking ratio
## - dead-end rate: share of seeded random playouts that get stuck before clearing
## - solver effort (nodes) to find a full solution
## The combined score is a heuristic for ordering/pacing review, not a promise of feel;
## tester feedback must still calibrate it.

static func analyze(level: LevelDefinition, playouts: int = 24, seed_value: int = 7) -> Dictionary:
	var geo := level.build_geometry()
	var state := level.build_state(geo)
	var opening_pairs := state.available_pairs().size()
	var stacked := 0
	for i in geo.count:
		if geo.gz[i] > 0:
			stacked += 1
	var rng := SeededRng.new(seed_value ^ SeededRng.hash_string(level.key))
	var stuck := 0
	var choice_sum := 0
	var choice_n := 0
	var progress_sum := 0.0
	for p in playouts:
		var s := state.clone()
		while s.remaining > 0:
			var pairs := s.available_pairs()
			if pairs.is_empty():
				stuck += 1
				break
			choice_sum += pairs.size()
			choice_n += 1
			var mv: Vector2i = pairs[rng.rand_int(0, pairs.size() - 1)]
			s.remove_pair(mv.x, mv.y)
		progress_sum += 1.0 - float(s.remaining) / float(maxi(1, geo.count))
	var solver := BoardSolver.new(200000)
	var res := solver.solve(state)
	var dead_rate := float(stuck) / float(maxi(1, playouts))
	var avg_choices := float(choice_sum) / float(maxi(1, choice_n))
	var score := 0.0
	score += geo.count / 144.0 * 25.0
	score += geo.max_z * 6.0
	score += float(stacked) / float(maxi(1, geo.count)) * 15.0
	score += dead_rate * 35.0
	score += clampf(6.0 - avg_choices, 0.0, 6.0) * 2.5
	score += clampf(log(float(maxi(1, res.nodes))) / log(10.0), 0.0, 6.0) * 1.5
	var band := "relaxed"
	if score >= 45.0:
		band = "challenge"
	elif score >= 25.0:
		band = "standard"
	return {
		"key": level.key, "tiles": geo.count, "layers": geo.max_z + 1, "stacked_ratio": snappedf(float(stacked) / float(maxi(1, geo.count)), 0.01),
		"opening_pairs": opening_pairs, "avg_choices": snappedf(avg_choices, 0.01),
		"dead_end_rate": snappedf(dead_rate, 0.01), "avg_random_progress": snappedf(progress_sum / playouts, 0.01),
		"solver_nodes": res.nodes, "solver_result": res.result,
		"score": snappedf(score, 0.1), "band": band,
	}
