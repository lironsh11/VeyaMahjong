extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=name]
## Exit code 0 = all passed, 1 = failures. Prints one line per test.

func _initialize() -> void:
	# Let autoload services run _ready() before tests use them.
	await process_frame
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
	var files: Array = []
	for f in DirAccess.get_files_at("res://tests/"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var passed := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			print("LOAD FAIL  ", f)
			failed += 1
			continue
		var methods: Array = []
		for m in script.get_script_method_list():
			if str(m.name).begins_with("test_") and not methods.has(m.name):
				methods.append(m.name)
		for m in methods:
			if filter != "" and not (f + "::" + m).contains(filter):
				continue
			var inst: TestCase = script.new()
			inst._current = m
			var ts := Time.get_ticks_msec()
			inst.call(m)
			var dt := Time.get_ticks_msec() - ts
			if inst.failures.is_empty():
				passed += 1
				print("PASS  %s::%s (%d ms)" % [f, m, dt])
			else:
				failed += 1
				print("FAIL  %s::%s" % [f, m])
				for msg in inst.failures:
					print("        ", msg)
	print("\n%d passed, %d failed in %.1fs" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)
