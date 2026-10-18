extends TestCase
## Localization QA: all ten launch locales must have exactly the English key set, valid
## placeholders, the plural categories their language needs, and no leftover English.

const DIR := "res://data/localization/"
const CODES := ["en", "ja", "ko", "de", "fr", "es", "pt-BR", "zh-Hant-TW", "he", "ru"]
const PLURALS := {
	"en": ["one", "other"], "de": ["one", "other"], "es": ["one", "other"],
	"fr": ["one", "other"], "pt-BR": ["one", "other"], "he": ["one", "two", "other"],
	"ru": ["one", "few", "many"], "ja": ["other"], "ko": ["other"], "zh-Hant-TW": ["other"],
}
## Keys whose English value may legitimately stay identical (brand names, symbols).
const SAME_OK := ["app_name", "veya_bloom", "ok", "lights_progress", "week_start", "date_long", "month_year", "buy_for", "share_text", "time_taken"]

var _re := RegEx.create_from_string("\\{([a-z_]+)\\}")


func _load(code: String) -> Dictionary:
	var p := DIR + code + ".json"
	if not FileAccess.file_exists(p):
		return {}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return j if typeof(j) == TYPE_DICTIONARY else {}


func _placeholders(v: Variant) -> Array:
	var texts: Array = []
	if typeof(v) == TYPE_DICTIONARY:
		texts = v.values()
	else:
		texts = [v]
	var out := {}
	for t in texts:
		for m in _re.search_all(str(t)):
			out[m.get_string(1)] = true
	var keys := out.keys()
	keys.sort()
	return keys


func test_all_locale_files_present_and_parse() -> void:
	for code in CODES:
		var d := _load(code)
		check(not d.is_empty(), "%s.json exists and parses" % code)
		if d.is_empty():
			continue
		check(typeof(d.get("strings")) == TYPE_DICTIONARY, "%s has strings" % code)
		check_eq(bool(d.get("rtl", false)), code == "he", "%s rtl flag" % code)
		check(str(d.get("native_name", "")) != "", "%s native_name" % code)


func test_key_parity_and_placeholders() -> void:
	var en: Dictionary = _load("en").get("strings", {})
	check(en.size() > 200, "english table is complete (%d keys)" % en.size())
	for code in CODES:
		if code == "en":
			continue
		var tr: Dictionary = _load(code).get("strings", {})
		if tr.is_empty():
			fail("%s missing" % code)
			continue
		var missing: Array = []
		var extra: Array = []
		for k in en:
			if not tr.has(k):
				missing.append(k)
		for k in tr:
			if not en.has(k):
				extra.append(k)
		check(missing.is_empty(), "%s missing keys: %s" % [code, missing])
		check(extra.is_empty(), "%s unknown keys: %s" % [code, extra])
		for k in en:
			if not tr.has(k):
				continue
			var ev: Variant = en[k]
			var tv: Variant = tr[k]
			# Plural objects must stay plural objects with this language's categories.
			if typeof(ev) == TYPE_DICTIONARY:
				if typeof(tv) != TYPE_DICTIONARY:
					fail("%s.%s must be a plural object" % [code, k])
					continue
				for cat in PLURALS[code]:
					check(tv.has(cat) and str(tv[cat]).strip_edges() != "", "%s.%s needs plural '%s'" % [code, k, cat])
			else:
				check(typeof(tv) == TYPE_STRING and str(tv).strip_edges() != "", "%s.%s non-empty" % [code, k])
			check(_placeholders(tv) == _placeholders(ev), "%s.%s placeholders %s != %s" % [code, k, _placeholders(tv), _placeholders(ev)])


func test_no_untranslated_english() -> void:
	var en: Dictionary = _load("en").get("strings", {})
	for code in CODES:
		if code == "en":
			continue
		var tr: Dictionary = _load(code).get("strings", {})
		var same: Array = []
		for k in en:
			if SAME_OK.has(k) or not tr.has(k) or typeof(en[k]) != TYPE_STRING:
				continue
			if str(en[k]).length() > 10 and str(tr[k]) == str(en[k]):
				same.append(k)
		check(same.is_empty(), "%s has English left in: %s" % [code, same])


func test_plural_rules() -> void:
	var L := load("res://scripts/services/LocalizationService.gd")
	check_eq(L.plural_category("en", 1), "one")
	check_eq(L.plural_category("en", 2), "other")
	check_eq(L.plural_category("fr", 0), "one")
	check_eq(L.plural_category("he", 2), "two")
	check_eq(L.plural_category("he", 5), "other")
	check_eq(L.plural_category("ru", 1), "one")
	check_eq(L.plural_category("ru", 3), "few")
	check_eq(L.plural_category("ru", 5), "many")
	check_eq(L.plural_category("ru", 11), "many")
	check_eq(L.plural_category("ru", 21), "one")
	check_eq(L.plural_category("ru", 22), "few")
	check_eq(L.plural_category("ja", 1), "other")


func test_os_locale_mapping() -> void:
	var L := load("res://scripts/services/LocalizationService.gd")
	check_eq(L.map_os_locale("en_US"), "en")
	check_eq(L.map_os_locale("pt_BR"), "pt-BR")
	check_eq(L.map_os_locale("pt_PT"), "pt-BR")
	check_eq(L.map_os_locale("zh_TW"), "zh-Hant-TW")
	check_eq(L.map_os_locale("zh_Hant_HK"), "zh-Hant-TW")
	check_eq(L.map_os_locale("zh_CN"), "", "Simplified Chinese is never substituted")
	check_eq(L.map_os_locale("iw_IL"), "he", "legacy Android Hebrew code")
	check_eq(L.map_os_locale("he-IL"), "he")
	check_eq(L.map_os_locale("ar_EG"), "", "unsupported -> fallback")


func test_group_separators() -> void:
	var L := load("res://scripts/services/LocalizationService.gd")
	check_eq(L.group_separator("de"), ".")
	check_eq(L.group_separator("en"), ",")
	check_eq(L.group_separator("ru"), " ")


func test_date_patterns_present() -> void:
	for code in CODES:
		var s: Dictionary = _load(code).get("strings", {})
		if s.is_empty():
			continue
		var pat := str(s.get("date_long", ""))
		check(pat.contains("{day}") and pat.contains("{month}") and pat.contains("{year}"), "%s date_long" % code)
		check(str(s.get("week_start", "")) in ["0", "1"], "%s week_start" % code)
		for m in range(1, 13):
			check(str(s.get("month_%d" % m, "")) != "", "%s month_%d" % [code, m])
