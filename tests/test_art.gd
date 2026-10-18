extends TestCase
## LiShi v2 graphics contract (art/lishi_v2, produced by tools/import_lishi_v2.gd): every face
## of every tile theme resolves at both resolutions with the board's slot proportions, state
## overlays exist, every Bloom discovery has a sprite, and the UI never asks for missing art.

func _face_ids() -> Array:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/lishi_v2/tiles/sakura_premium/sakura_premium_192_atlas.json"))
	return (meta.mapping as Dictionary).keys()


func test_every_theme_has_all_faces_at_slot_aspect() -> void:
	var ids := _face_ids()
	check_eq(ids.size(), 42, "faces in atlas")
	for theme in ContentService.TILE_THEME_ART.keys():
		for hi in [true, false]:
			for id in ids:
				var t := ContentService.tile_texture(theme, id, hi)
				if not check(t != null, "%s %s hi=%s resolves" % [theme, id, hi]):
					continue
				check(absf(t.get_height() / float(t.get_width()) - BoardFit.ASPECT) < 0.01, "%s %s cell matches BoardFit.ASPECT" % [theme, id])


func test_atlas_faces_match_level_faces() -> void:
	# Every face a level can deal must exist in the art (ids are semantic, never inferred).
	var ids := _face_ids()
	for i in range(1, ContentService.level_count() + 1, 7):
		var L := ContentService.get_level(i)
		if L == null:
			continue
		for f in L.build_state().faces:
			if not ids.has(f):
				fail("level %d face %s has no art" % [i, f])
				return


func test_atlas_body_matches_board_view() -> void:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/lishi_v2/tiles/jade_garden/jade_garden_96_atlas.json"))
	var b: Array = meta.body
	check(Rect2(b[0], b[1], b[2], b[3]).is_equal_approx(BoardView.BODY), "import tool BODY == BoardView.BODY")


func test_state_overlays_exist() -> void:
	for st in ["selected", "hint", "blocked", "match", "pressed"]:
		for hi in [true, false]:
			check(ContentService.tile_overlay(st, hi) != null, "overlay %s hi=%s" % [st, hi])


func test_bloom_discoveries_have_sprites() -> void:
	for d in ContentService.all_discoveries():
		for hi in [true, false]:
			check(ContentService.discovery_texture(d, hi) != null, "discovery %s hi=%s" % [d.id, hi])


func test_backgrounds_resolve() -> void:
	for w in ContentService.worlds:
		for kind in ["world", "map", "gameplay"]:
			for low in [true, false]:
				check(ContentService.world_bg(str(w.id), kind, low) != null, "%s %s low=%s" % [w.id, kind, low])
	for screen in ContentService.SCREEN_BACKGROUNDS.keys():
		for low in [true, false]:
			check(ContentService.screen_bg(screen, low) != null, "screen %s low=%s" % [screen, low])


func test_ui_art_resolves() -> void:
	# Icon names used by screens (including aliased ones) in both colourways.
	for n in ["back", "check", "home", "settings", "daily", "collection", "worlds", "shop", "hint", "shuffle", "undo", "pause", "next", "flower", "lock", "calendar_check", "sparkle"]:
		for white in [true, false]:
			check(ContentService.icon(n, white) != null, "icon %s white=%s" % [n, white])
	for col in UITheme.BUTTON_COLORS:
		for size in ["large", "small"]:
			for st in ["normal", "pressed", "disabled"]:
				var p := "ui/buttons/%s_%s_%s.png" % [UITheme.BUTTON_FILES.get(col, col), size, st]
				check(ContentService.art(p) != null, p)
	for n in ["available", "complete", "current", "locked"]:
		check(ContentService.art("ui/level_nodes/%s.png" % n) != null, "level node " + n)
