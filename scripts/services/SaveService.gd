extends Node
## Crash-safe, versioned local persistence under user://.
##
## On-disk envelope:  {"format": "veya-save", "schema_version": N, "sha256": "...", "payload": "<json>"}
## The payload is stored as a JSON *string* so the checksum covers the exact bytes written
## (re-serialising parsed JSON would change number formatting).
##
## Write protocol (atomic as far as the platform allows):
##   1. write <file>.tmp and close it
##   2. verify the tmp file reads back with a valid checksum
##   3. rotate current <file> -> <file>.bak
##   4. rename <file>.tmp -> <file>
## Load order: primary, then tmp (a crash between 3 and 4), then bak. Corrupt files are kept
## aside as <file>.corrupt-<time> for support, never silently deleted.

signal recovered_from_backup(source: String)

const FORMAT := "veya-save"
const SCHEMA_VERSION := 1

var save_dir: String = "user://save"
var file_name: String = "veya_save.json"
var last_load_source: String = ""


func _init() -> void:
	# Debug/QA isolation: --save-dir=user://somewhere keeps tours and tests off real data.
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--save-dir="):
				save_dir = a.trim_prefix("--save-dir=")


func path() -> String:
	return save_dir.path_join(file_name)


func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))


func encode(payload: Dictionary) -> String:
	var body := JSON.stringify(payload)
	return JSON.stringify({
		"format": FORMAT, "schema_version": SCHEMA_VERSION,
		"sha256": body.sha256_text(), "payload": body,
	})


func decode(text: String) -> Variant:
	## Returns the payload Dictionary or null if the text is not a valid save.
	if text.is_empty():
		return null
	var env: Variant = JSON.parse_string(text)
	if typeof(env) != TYPE_DICTIONARY or env.get("format") != FORMAT:
		return null
	var body: Variant = env.get("payload")
	if typeof(body) != TYPE_STRING or (body as String).sha256_text() != str(env.get("sha256", "")):
		return null
	var payload: Variant = JSON.parse_string(body)
	if typeof(payload) != TYPE_DICTIONARY:
		return null
	payload["schema_version"] = int(env.get("schema_version", 0))
	return payload


func write(payload: Dictionary) -> bool:
	_ensure_dir()
	var p := path()
	var tmp := p + ".tmp"
	var bak := p + ".bak"
	var text := encode(payload)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveService: cannot open %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.flush()
	f.close()
	if decode(FileAccess.get_file_as_string(tmp)) == null:
		push_warning("SaveService: verification of temp save failed")
		return false
	var da := DirAccess.open(save_dir)
	if da == null:
		return false
	if FileAccess.file_exists(p):
		if FileAccess.file_exists(bak):
			da.remove(bak.get_file())
		da.rename(p.get_file(), bak.get_file())
	var err := da.rename(tmp.get_file(), p.get_file())
	return err == OK


func read() -> Dictionary:
	## Returns {"payload": Dictionary or null, "source": "primary"|"tmp"|"bak"|"none"}
	var p := path()
	for entry in [["primary", p], ["tmp", p + ".tmp"], ["bak", p + ".bak"]]:
		if not FileAccess.file_exists(entry[1]):
			continue
		var payload: Variant = decode(FileAccess.get_file_as_string(entry[1]))
		if payload != null:
			last_load_source = entry[0]
			if entry[0] != "primary":
				recovered_from_backup.emit(entry[0])
			return {"payload": payload, "source": entry[0]}
		_quarantine(entry[1])
	last_load_source = "none"
	return {"payload": null, "source": "none"}


func _quarantine(file_path: String) -> void:
	var da := DirAccess.open(save_dir)
	if da == null:
		return
	var dest := "%s.corrupt-%d" % [file_path.get_file(), Time.get_unix_time_from_system()]
	da.rename(file_path.get_file(), dest)
	push_warning("SaveService: corrupt save moved to %s" % dest)


func delete_all() -> void:
	## Local reset only. Store entitlements are restored from the platform, not from here.
	var da := DirAccess.open(save_dir)
	if da == null:
		return
	for f in da.get_files():
		if f.begins_with(file_name):
			da.remove(f)
