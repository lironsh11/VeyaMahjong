extends Node
## Audio from the pack's AUDIO_MAP.json: pooled one-shot SFX and cross-faded world loops.
## Buses: Master > Music, SFX, Ambience (Ambience is reserved; the pack has no ambience bed).
## Interruptions: music pauses when the app is backgrounded and resumes on return.

const MAP_PATH := "res://assets/veya/audio/AUDIO_MAP.json"
const AUDIO_ROOT := "res://assets/veya/audio/"
const POOL_SIZE := 6
const FADE_S := 0.8

var _sfx: Dictionary = {}       # event -> AudioStream
var _loops: Dictionary = {}     # world -> path
var _pool: Array[AudioStreamPlayer] = []
var _pool_i: int = 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_world: String = ""
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	var map: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if typeof(map) == TYPE_DICTIONARY:
		for ev in map.get("events", {}):
			var p: String = AUDIO_ROOT + str(map.events[ev])
			if ResourceLoader.exists(p):
				_sfx[ev] = load(p)
		for w in map.get("loops", {}):
			_loops[w] = AUDIO_ROOT + str(map.loops[w])
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	apply_settings()
	GameState.settings_changed.connect(func(_k: String) -> void: apply_settings())


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")


static func linear_to_db_safe(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func apply_settings() -> void:
	var music_on := bool(GameState.setting("music_on"))
	var sfx_on := bool(GameState.setting("sfx_on"))
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(mi, linear_to_db_safe(float(GameState.setting("music_volume"))))
	AudioServer.set_bus_volume_db(si, linear_to_db_safe(float(GameState.setting("sfx_volume"))))
	AudioServer.set_bus_mute(mi, not music_on)
	AudioServer.set_bus_mute(si, not sfx_on)


func play(event: String, pitch: float = 1.0) -> void:
	if not _sfx.has(event) or not bool(GameState.setting("sfx_on")):
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sfx[event]
	p.pitch_scale = pitch
	p.play()


func play_world_music(world_id: String) -> void:
	if world_id == _music_world or not _loops.has(world_id):
		return
	_music_world = world_id
	var stream: AudioStream = load(_loops[world_id])
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	# Cross-fade: incoming on B, outgoing A fades out; then swap roles.
	var incoming := _music_b
	var outgoing := _music_a
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, FADE_S)
	_music_tween.tween_property(outgoing, "volume_db", -60.0, FADE_S)
	_music_tween.chain().tween_callback(outgoing.stop)
	_music_a = incoming
	_music_b = outgoing


func stop_music() -> void:
	_music_world = ""
	_music_a.stop()
	_music_b.stop()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_music_a.stream_paused = true
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_music_a.stream_paused = false
