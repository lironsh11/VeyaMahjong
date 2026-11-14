extends TestCase
## Board Studio (2026-11): share codes (encode/decode, forgiving input, typo detection, errors),
## deterministic boards that are proven winnable, the pinned code fingerprints, presets.

const PINNED := {
	# Recorded 2026-11-14 for StudioCode.VERSION 1 / StudioBoard "studio-1". A mismatch means a
	# shared algorithm changed the boards that codes build: follow the note in StudioBoard.gd.
	"LS-5VSW-11BK": "7106590cdaed7769",
	"LS-4TBN-PV9S": "b6ade65a14cf808c",
	"LS-5K1R-45E0": "95c3bdb372c01a54",
	"LS-6MHR-5Q12": "508389ec19c97e68",
	"LS-5P7J-K6R2": "0c3fc6e9d56210a5",
}


static func _p(fam: String, cols: int, layers: int, mode: String, tiles: int, seed_value: int) -> Dictionary:
	return {"family": fam, "cols": cols, "layers": layers, "mode": mode, "tiles": tiles, "seed": seed_value}


static func _fp(L: LevelDefinition) -> String:
	return (",".join(L.faces()) + "|" + str(L.positions())).sha256_text().left(16)


func test_round_trip_every_field() -> void:
	var n := 0
	for fam in LayoutTemplates.FAMILIES:
		for cols in range(StudioCode.MIN_COLS, StudioCode.MAX_COLS + 1):
			for layers in range(StudioCode.MIN_LAYERS, StudioCode.MAX_LAYERS + 1):
				for mode in LayoutTemplates.MODES:
					for tiles in [StudioCode.MIN_TILES, 72, StudioCode.MAX_TILES]:
						for s in [0, 1, 12345, StudioCode.SEED_MAX]:
							var p := _p(fam, cols, layers, mode, tiles, s)
							var c := StudioCode.encode(p)
							var d := StudioCode.decode(c)
							if not check_eq(d.err, StudioCode.Err.OK, "decode %s" % c) or not check(d.params == p, "%s -> %s" % [p, d.params]):
								return
							n += 1
	check(n > 5000, "covered %d combinations" % n)


func test_code_format() -> void:
	var re := RegEx.create_from_string("^LS-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$")
	for s in 200:
		var c := StudioCode.encode(_p("turtle", 6, 4, "top", 76, s * 163))
		check(re.search(c) != null, "format of %s" % c)
		for bad in ["I", "L", "O", "U"]:
			check(not c.substr(3).contains(bad), "%s has no %s" % [c, bad])
	check_eq(StudioCode.encode(_p("nope", 6, 3, "top", 72, 1)), "", "unknown shape")
	check_eq(StudioCode.encode(_p("pyramid", 6, 3, "top", 73, 1)), "", "odd tiles")
	check_eq(StudioCode.encode(_p("pyramid", 6, 3, "top", 146, 1)), "", "too many tiles")
	check_eq(StudioCode.encode(_p("pyramid", 6, 3, "top", 72, 40000)), "", "seed too big")


func test_neighbouring_seeds_look_different() -> void:
	var a := StudioCode.encode(_p("pyramid", 6, 3, "top", 72, 100))
	var b := StudioCode.encode(_p("pyramid", 6, 3, "top", 72, 101))
	var same := 0
	for k in a.length():
		if a[k] == b[k]:
			same += 1
	check(same <= 6, "%s vs %s share only the prefix and a few characters" % [a, b])


func test_forgiving_input() -> void:
	var c := StudioCode.encode(_p("bridge", 7, 4, "edge", 96, 32767))
	var body := c.substr(3).replace("-", "")
	var variants := [c, c.to_lower(), " " + c + " ", body, body.to_lower(), "ls " + body.substr(0, 4) + " " + body.substr(4),
		String.chr(0x2066) + c + String.chr(0x2069), c.replace("0", "O").replace("1", "I")]
	for v in variants:
		var d := StudioCode.decode(v)
		check_eq(d.err, StudioCode.Err.OK, "'%s' accepted" % v)
		check_eq(d.code, c, "'%s' is canonical" % v)


func test_every_single_typo_is_caught() -> void:
	for s in [0, 7, 999, 32767]:
		var c := StudioCode.encode(_p("frame", 5, 2, "edge", 36, s))
		var body := c.substr(3).replace("-", "")
		for k in body.length():
			for ch in StudioCode.ALPHABET:
				if ch == body[k]:
					continue
				var typo := body.substr(0, k) + ch + body.substr(k + 1)
				var d := StudioCode.decode(typo)
				if not check(d.err != StudioCode.Err.OK, "typo %s of %s accepted" % [typo, body]):
					return


func test_most_neighbour_swaps_are_caught() -> void:
	var swaps := 0
	var caught := 0
	for s in 120:
		var body := StudioCode.encode(_p("ridge", 6, 5, "top", 120, s * 271)).substr(3).replace("-", "")
		for k in body.length() - 1:
			if body[k] == body[k + 1]:
				continue
			var sw := body.substr(0, k) + body[k + 1] + body[k] + body.substr(k + 2)
			swaps += 1
			if StudioCode.decode(sw).err != StudioCode.Err.OK:
				caught += 1
	check(float(caught) / swaps >= 0.95, "caught %d of %d swaps" % [caught, swaps])


func test_error_kinds() -> void:
	check_eq(StudioCode.decode("").err, StudioCode.Err.EMPTY)
	check_eq(StudioCode.decode("   ").err, StudioCode.Err.EMPTY)
	check_eq(StudioCode.decode("LS-1234").err, StudioCode.Err.LENGTH)
	check_eq(StudioCode.decode("LS-12#4-ABCD").err, StudioCode.Err.CHARS)
	check_eq(StudioCode.decode("UUUUUUUU").err, StudioCode.Err.CHARS)
	var c := StudioCode.encode(_p("pyramid", 6, 3, "top", 72, 5)).substr(3).replace("-", "")
	var last := StudioCode.ALPHABET.find(c[7])
	check_eq(StudioCode.decode(c.substr(0, 7) + StudioCode.ALPHABET[(last + 1) % 32]).err, StudioCode.Err.CHECKSUM)
	# A well-formed code from a future format version.
	var digits := PackedInt32Array()
	var value := (7 << 32) | 12345
	for k in 7:
		digits.insert(0, value & 31)
		value >>= 5
	digits.append(StudioCode.check_digit(digits))
	var future := ""
	for d in digits:
		future += StudioCode.ALPHABET[d]
	check_eq(StudioCode.decode(future).err, StudioCode.Err.VERSION)
	for e in [StudioCode.Err.EMPTY, StudioCode.Err.LENGTH, StudioCode.Err.CHARS, StudioCode.Err.CHECKSUM, StudioCode.Err.VERSION, StudioCode.Err.BOARD]:
		check(LocalizationService.t(StudioCode.error_key(e)) != StudioCode.error_key(e), "error %d has a message" % e)


func test_shape_that_cannot_hold_the_tiles_is_a_board_error() -> void:
	var c := StudioCode.encode(_p("turtle", 4, 1, "top", 144, 3))
	check(c != "", "the code itself is well-formed")
	var r := StudioBoard.from_code(c)
	check_eq(r.err, StudioCode.Err.BOARD)
	check(r.level == null)


func test_pinned_fingerprints() -> void:
	check_eq(StudioCode.VERSION, 1)
	check_eq(StudioBoard.SEED_PREFIX, "studio-1")
	for code in PINNED:
		StudioBoard.clear_cache()
		var r := StudioBoard.from_code(code)
		if not check_eq(r.err, StudioCode.Err.OK, code):
			continue
		check_eq(_fp(r.level), PINNED[code], "fingerprint of %s" % code)


func test_same_code_same_board_and_proven_winnable() -> void:
	StudioBoard.clear_cache()
	var a := StudioBoard.from_code(StudioBoard.SAMPLE_CODE)
	StudioBoard.clear_cache()
	var b := StudioBoard.from_code(StudioBoard.SAMPLE_CODE.to_lower())
	check_eq(_fp(a.level), _fp(b.level), "deterministic")
	check_eq(a.level.key, "studio:" + StudioBoard.SAMPLE_CODE)
	var report := BoardValidator.validate(a.level, StudioBoard.VALIDATE_NODES)
	check(report.ok, "sample board passes the validator: %s" % report.errors)
	var other := StudioBoard.build(_p("pyramid", 6, 3, "top", 72, 2027))
	check(other != null and _fp(other) != _fp(a.level), "another seed builds another board")


func test_make_builds_validated_boards_and_adjusts() -> void:
	var made := 0
	for fam in LayoutTemplates.FAMILIES:
		var r := StudioBoard.tile_range(_p(fam, 6, 3, "top", 64, 42))
		check(r.x == StudioCode.MIN_TILES and r.y >= r.x and r.y % 2 == 0, "%s range %s" % [fam, r])
		var res := StudioBoard.make(_p(fam, 6, 3, "top", mini(r.y, 64), 42))
		if not check(res.ok, "%s 6x3 makes a board" % fam):
			continue
		made += 1
		check(BoardValidator.validate(res.level, StudioBoard.VALIDATE_NODES).ok, "%s validated" % fam)
		StudioBoard.clear_cache()
		var again := StudioBoard.from_code(str(res.code))
		check_eq(_fp(again.level), _fp(res.level), "%s: the code (adjusted=%s) rebuilds the same board" % [fam, res.adjusted])
		check(str(res.band) in ["relaxed", "standard", "challenge"])
	check_eq(made, LayoutTemplates.FAMILIES.size())
	var none := StudioBoard.make(_p("turtle", 4, 1, "top", 144, 1))
	check(not none.ok, "impossible settings report failure")


func test_preview_matches_the_board() -> void:
	var p := _p("terraces", 6, 4, "edge", 88, 31)
	var res := StudioBoard.make(p)
	if check(res.ok) and res.adjusted == "":
		check_eq(str(StudioBoard.positions_for(p)), str(res.level.positions()), "preview shape is the played shape")


func test_presets_get_bigger_with_difficulty() -> void:
	var avg := {}
	for d in StudioBoard.DIFFICULTIES:
		var tiles := 0.0
		var layers := 0.0
		for s in 6:
			var p := StudioBoard.preset(d, s * 1009)
			check(StudioCode.params_valid(p), "%s preset valid: %s" % [d, p])
			check(int(p.tiles) <= StudioBoard.tile_range(p).y and not StudioBoard.positions_for(p).is_empty(), "%s fits its shape" % d)
			tiles += int(p.tiles)
			layers += int(p.layers)
		avg[d] = Vector2(tiles / 6.0, layers / 6.0)
	check(avg.easy.x < avg.medium.x and avg.medium.x < avg.hard.x, "tiles grow: %s" % avg)
	check(avg.easy.y < avg.hard.y, "layers grow: %s" % avg)
	for s in 3:
		check(StudioBoard.make(StudioBoard.preset("hard", s)).ok, "hard preset %d makes a board" % s)


func test_every_shape_has_a_name() -> void:
	for fam in LayoutTemplates.FAMILIES:
		check(LocalizationService.t("shape_" + fam) != "shape_" + fam, "shape_%s translated" % fam)
