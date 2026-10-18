extends SceneTree
## Loads every GDScript under res://scripts, res://tests and res://tools and reports parse
## failures. Exit code 1 on any failure.
##   godot --headless --path . -s res://tools/check_scripts.gd

func _initialize() -> void:
	var bad := 0
	var n := 0
	for root in ["res://scripts", "res://tests", "res://tools"]:
		for p in _walk(root):
			n += 1
			if p.ends_with("check_scripts.gd"):
				continue
			var s: Script = load(p)
			if s == null or not s.can_instantiate() and not p.ends_with("run_tests.gd"):
				bad += 1
				print("FAILED: ", p)
	print("%d scripts checked, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)


func _walk(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_walk(dir.path_join(d)))
	return out
