class_name BoardValidator
extends RefCounted
## Content gate for any board before it reaches a player (pack levels, generated levels,
## daily boards). Produces a report instead of throwing so tools can list every problem.

static func validate(level: LevelDefinition, solver_nodes: int = 400000, require_witness: bool = true) -> Dictionary:
	var report := {
		"key": level.key, "ok": false, "errors": PackedStringArray(), "warnings": PackedStringArray(),
		"tiles": level.tiles.size(), "witness_legal": false, "solver": "not_run", "solver_nodes": 0,
	}
	var errors: PackedStringArray = report.errors
	errors.append_array(level.errors)
	if not errors.is_empty():
		return report
	var geo := level.build_geometry()
	errors.append_array(geo.errors)
	for i in geo.count:
		if not geo.is_supported(i):
			report.warnings.append("tile %d at layer %d has no support below" % [i, geo.gz[i]])
	var state := level.build_state(geo)
	state.side_blocking = true  # content is gated by the classic rules (stricter than the tray)
	if not state.face_counts_valid():
		errors.append("face counts incompatible with matching rules (a match group has an odd count)")
	if not state.has_moves():
		errors.append("no legal opening move")
	if not errors.is_empty():
		return report
	if level.solution.is_empty():
		if require_witness:
			errors.append("missing witness solution")
	else:
		report.witness_legal = BoardSolver.replay_is_legal(state, level.solution)
		if not report.witness_legal:
			errors.append("witness solution is not legal step-by-step")
		var play := level.build_state(geo)
		if not TraySolver.replay_is_legal(play, PackedInt32Array(), TraySolver.flatten(level.solution)):
			errors.append("witness solution is not legal in tray play")
	# Independent solver check (does not trust the witness).
	var solver := BoardSolver.new(solver_nodes)
	var res := solver.solve(state)
	report.solver_nodes = res.nodes
	match res.result:
		BoardSolver.Result.SOLVED:
			report.solver = "solved"
			if not BoardSolver.replay_is_legal(state, res.solution):
				errors.append("solver produced an illegal sequence (engine bug)")
		BoardSolver.Result.UNSOLVABLE:
			report.solver = "unsolvable"
			errors.append("solver proved the board unsolvable")
		_:
			report.solver = "budget"
			if not report.witness_legal:
				errors.append("solver budget exceeded and no legal witness")
			else:
				report.warnings.append("solver budget exceeded; witness proves solvability")
	report.ok = errors.is_empty()
	return report
