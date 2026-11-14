extends SceneTree
## Writes the shipped level catalog, data/levels/world_1.json ... world_6.json (100 levels each,
## minified), from the source files (LevelCatalog.assemble: each world's 50 1.0 levels with their
## 1.1.0 ids, then its 50 second-half levels). Run after any build_levels.gd or
## build_early_levels.gd run:
##   godot --headless --path . -s res://tools/build_catalog.gd
## test_levels checks that the shipped files still equal what this writes.


func _initialize() -> void:
	await process_frame
	var errs := PackedStringArray()
	var levels := LevelCatalog.assemble(errs)
	if levels.size() != LevelCatalog.TOTAL:
		push_error("catalog sources incomplete: %s" % [errs])
		quit(1)
		return
	var sizes := PackedStringArray()
	for w in range(1, LevelCatalog.WORLDS + 1):
		var part: Array = levels.slice((w - 1) * LevelCatalog.PER_WORLD, w * LevelCatalog.PER_WORLD)
		var text := catalog_text(part)
		var f := FileAccess.open(LevelCatalog.WORLD_PATH % w, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		sizes.append("world %d: %d KB" % [w, text.length() / 1024])
	print("CATALOG %d levels; %s" % [levels.size(), ", ".join(sizes)])
	quit(0)


static func catalog_text(levels: Array) -> String:
	## One level per line (diffs stay readable), no indentation.
	var lines := PackedStringArray()
	for d in levels:
		lines.append(JSON.stringify(_ints(d), "", false))
	return "[\n" + ",\n".join(lines) + "\n]\n"


static func _ints(v: Variant) -> Variant:
	## JSON.parse_string reads every number as a float and stringify then writes "2.0"; whole
	## numbers go back to ints so the files stay small.
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if float(v) == roundf(v) and absf(v) < 1e12 else v
		TYPE_ARRAY:
			var a: Array = []
			for x in v:
				a.append(_ints(x))
			return a
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[k] = _ints(v[k])
			return o
	return v
