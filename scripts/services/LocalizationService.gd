extends Node
## Ten launch locales with named placeholders, CLDR-style plurals, RTL and locale formatting.
##
## Files: res://data/localization/<code>.json  {"locale", "rtl", "native_name", "strings": {...}}
## A string value may be a plural object {"one": "...", "few": "...", "other": "..."}; t() picks
## the category from vars["count"]. Placeholders are {name}; translators may reorder freely.
##
## Strings are also registered with TranslationServer so Godot's TextServer shapes text with
## the right language (affects CJK line breaking and the system-font fallback it selects).

signal locale_changed(code: String)

## code -> Godot locale id
const LOCALES := {
	"en": "en", "ja": "ja", "ko": "ko", "de": "de", "fr": "fr", "es": "es",
	"pt-BR": "pt_BR", "zh-Hant-TW": "zh_TW", "he": "he", "ru": "ru",
}
const ORDER := ["en", "ja", "ko", "de", "fr", "es", "pt-BR", "zh-Hant-TW", "he", "ru"]
const FALLBACK := "en"
const DIR := "res://data/localization/"

var current: String = FALLBACK
var _tables: Dictionary = {}      # code -> strings dict
var _meta: Dictionary = {}        # code -> {rtl, native_name, ...}
var _registered: Dictionary = {}  # code -> Translation


func _ready() -> void:
	_load_table(FALLBACK)
	apply_setting(str(GameState.setting("locale")))


func _load_table(code: String) -> bool:
	if _tables.has(code):
		return true
	if not FileAccess.file_exists(DIR + code + ".json"):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + code + ".json"))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("strings")) != TYPE_DICTIONARY:
		push_warning("Localization: missing or invalid table for %s" % code)
		return false
	_tables[code] = parsed.strings
	_meta[code] = {"rtl": bool(parsed.get("rtl", false)), "native_name": str(parsed.get("native_name", code))}
	var tr_res := Translation.new()
	tr_res.locale = LOCALES.get(code, code)
	for k in parsed.strings:
		var v: Variant = parsed.strings[k]
		if typeof(v) == TYPE_STRING:
			tr_res.add_message(k, v)
	TranslationServer.add_translation(tr_res)
	_registered[code] = tr_res
	return true


static func map_os_locale(os_locale: String) -> String:
	## Maps an OS locale (e.g. "pt_BR", "zh_Hant_TW", "iw_IL") to a supported code or "".
	var l := os_locale.replace("-", "_")
	var lang := l.get_slice("_", 0).to_lower()
	match lang:
		"en", "ja", "ko", "de", "fr", "es", "ru":
			return lang
		"he", "iw":  # older Android reports Hebrew as "iw"
			return "he"
		"pt":
			return "pt-BR"  # closest supported variant; we never ship European Portuguese as BR
		"zh":
			# Traditional Chinese only: Taiwan, Hong Kong, Macau or explicit Hant script.
			var upper := l.to_upper()
			if upper.contains("HANT") or upper.ends_with("_TW") or upper.ends_with("_HK") or upper.ends_with("_MO"):
				return "zh-Hant-TW"
			return ""  # Simplified Chinese is not a launch locale -> English fallback
	return ""


func device_locale() -> String:
	var code := map_os_locale(OS.get_locale())
	return code if code != "" else FALLBACK


func apply_setting(setting_value: String) -> void:
	var code := device_locale() if setting_value == "auto" or setting_value == "" else setting_value
	if not LOCALES.has(code):
		code = FALLBACK
	set_locale(code)


func set_locale(code: String) -> void:
	if not _load_table(code):
		code = FALLBACK
	current = code
	TranslationServer.set_locale(LOCALES[code])
	locale_changed.emit(code)


func is_rtl() -> bool:
	return bool(_meta.get(current, {}).get("rtl", false))


func native_name(code: String) -> String:
	_load_table(code)
	return str(_meta.get(code, {}).get("native_name", code))


func has_key(key: String, code: String = "") -> bool:
	var c := current if code == "" else code
	_load_table(c)
	return _tables.get(c, {}).has(key)


func t(key: String, vars: Dictionary = {}) -> String:
	var v: Variant = _tables.get(current, {}).get(key)
	if v == null:
		v = _tables.get(FALLBACK, {}).get(key)
	if v == null:
		if OS.is_debug_build():
			push_warning("Missing localization key: " + key)
		return key
	var text: String
	if typeof(v) == TYPE_DICTIONARY:
		var cat := plural_category(current, int(vars.get("count", 0)))
		text = str(v.get(cat, v.get("other", key)))
	else:
		text = str(v)
	return format(text, vars)


func format(text: String, vars: Dictionary) -> String:
	for k in vars:
		var val: Variant = vars[k]
		var s: String = format_number(val) if typeof(val) == TYPE_INT else str(val)
		text = text.replace("{" + str(k) + "}", s)
	return text


static func plural_category(code: String, n: int) -> String:
	## CLDR cardinal rules for integer counts in the launch locales.
	match code:
		"ja", "ko", "zh-Hant-TW":
			return "other"
		"fr", "pt-BR":
			return "one" if n == 0 or n == 1 else "other"
		"he":
			if n == 1:
				return "one"
			if n == 2:
				return "two"
			return "other"
		"ru":
			var m10 := n % 10
			var m100 := n % 100
			if m10 == 1 and m100 != 11:
				return "one"
			if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
				return "few"
			return "many"
		_:
			return "one" if n == 1 else "other"


static func group_separator(code: String) -> String:
	match code:
		"de", "es", "pt-BR":
			return "."
		"fr":
			return " "  # narrow no-break space
		"ru":
			return " "
		_:
			return ","


func format_number(n: int, code: String = "") -> String:
	var c := current if code == "" else code
	var neg := n < 0
	var digits := str(absi(n))
	# Spanish conventionally omits the separator for 4-digit numbers.
	if c == "es" and digits.length() <= 4:
		return ("-" if neg else "") + digits
	var sep := group_separator(c)
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = sep + out
	return ("-" if neg else "") + out


func format_date(date: String, code: String = "") -> String:
	## date: "YYYY-MM-DD" -> localized long date using the table's "date_long" pattern and
	## month names ("month_N", genitive forms where the language needs them).
	var c := current if code == "" else code
	_load_table(c)
	var parts := date.split("-")
	if parts.size() != 3:
		return date
	var table: Dictionary = _tables.get(c, _tables[FALLBACK])
	var pattern := str(table.get("date_long", "{month} {day}, {year}"))
	var month := str(table.get("month_%d" % int(parts[1]), parts[1]))
	return pattern.replace("{year}", str(int(parts[0]))).replace("{month}", month).replace("{day}", str(int(parts[2])))


func month_title(year: int, month: int) -> String:
	var table: Dictionary = _tables.get(current, _tables[FALLBACK])
	var name := str(table.get("month_title_%d" % month, table.get("month_%d" % month, str(month))))
	return str(table.get("month_year", "{month} {year}")).replace("{month}", name).replace("{year}", str(year))


func week_start() -> int:
	## 0 = Sunday, 1 = Monday
	return int(str(_tables.get(current, {}).get("week_start", "0")))


func weekday_short(wd: int) -> String:
	return t("weekday_short_%d" % wd)
