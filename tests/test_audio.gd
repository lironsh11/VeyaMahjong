extends TestCase
## Audio wiring: every mapped file loads, every match sounds the same, variants
## never repeat back-to-back, and each world has a playlist of real pieces.

func _map() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(AudioService.MAP_PATH))


func test_all_mapped_audio_loads() -> void:
	var map := _map()
	var count := 0
	for ev in map.events:
		var files: Array = map.events[ev] if typeof(map.events[ev]) == TYPE_ARRAY else [map.events[ev]]
		for f in files:
			var s: AudioStream = load(AudioService.AUDIO_ROOT + str(f))
			check(s != null, "sfx %s loads" % f)
			if s:
				check(s.get_length() > 0.04 and s.get_length() < 6.5, "%s length %.2fs" % [f, s.get_length()])
				count += 1
	for w in map.music:
		check((map.music[w] as Array).size() >= 2, "%s has a playlist" % w)
		for f in map.music[w]:
			var m: AudioStream = load(AudioService.AUDIO_ROOT + str(f))
			check(m != null and m.get_length() > 120.0, "%s is a real piece (%.0fs)" % [f, m.get_length() if m else 0.0])
	check(count >= 21, "all sfx variants present (%d)" % count)


func test_every_event_used_by_the_game_exists() -> void:
	var map := _map()
	for ev in ["tap", "select", "button", "match", "invalid", "undo", "hint", "shuffle", "reward", "world_unlock", "victory", "soft_pop", "burst", "tray_alert", "fail"]:
		check(map.events.has(ev), "event %s mapped" % ev)


func test_every_match_sounds_the_same() -> void:
	# Owner request 2026-10-20: no pitch climb on streaks and no random spread on the match.
	check(not AudioService.VARIED.has("match"), "match is never randomly detuned")
	var src := FileAccess.get_file_as_string("res://scripts/gameplay/BoardController.gd")
	check(src.contains("AudioService.play(\"match\")"), "match plays at its own pitch")


func test_variants_never_repeat_back_to_back() -> void:
	var last: AudioStream = null
	for k in 200:
		var s: AudioStream = AudioService._pick("tap")
		check(s != last, "variant repeated at %d" % k)
		last = s
