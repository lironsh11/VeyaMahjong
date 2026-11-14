class_name StudioCode
extends RefCounted
## Board Studio share codes: "LS-XXXX-XXXX".
##
## A code carries only the board's build settings, never player data or player text:
##   version (3 bits, outside the scramble) | shape (4) | width-4 (2) | layers-1 (3) | carve (1)
##   | tiles/2-1 (7) | seed (15)  = 35 bits = 7 Crockford base-32 characters, plus one Luhn mod-32
## check character. The 32 payload bits are mixed (an invertible multiply, then XOR) so codes for
## neighbouring seeds look unrelated.
##
## The same code must build the same board forever (StudioBoard keeps one builder per version).
## LayoutTemplates.FAMILIES order is part of the format: new shapes may only be appended.

enum Err { OK, EMPTY, LENGTH, CHARS, CHECKSUM, VERSION, BOARD }

const VERSION := 1
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"   ## Crockford: no I, L, O, U
const PREFIX := "LS"
const SCRAMBLE := 0x5A3C96E1
const MIX := 0x9E3779B1               ## odd, so multiplying mod 2^32 is invertible
const M32 := 0xFFFFFFFF
const SEED_MAX := 32767
const MIN_TILES := 16
const MAX_TILES := 144
const MIN_COLS := 4
const MAX_COLS := 7
const MIN_LAYERS := 1
const MAX_LAYERS := 6
const ERR_KEYS := {
	Err.EMPTY: "code_err_empty", Err.LENGTH: "code_err_length", Err.CHARS: "code_err_chars",
	Err.CHECKSUM: "code_err_checksum", Err.VERSION: "code_err_version", Err.BOARD: "code_err_board",
}


static func params_valid(p: Dictionary) -> bool:
	## Field ranges only (StudioBoard checks that the shape can hold the tiles).
	var fam := LayoutTemplates.FAMILIES.find(str(p.get("family", "")))
	var tiles := int(p.get("tiles", 0))
	return fam >= 0 and fam < 16 \
		and int(p.get("cols", 0)) >= MIN_COLS and int(p.get("cols", 0)) <= MAX_COLS \
		and int(p.get("layers", 0)) >= MIN_LAYERS and int(p.get("layers", 0)) <= MAX_LAYERS \
		and str(p.get("mode", "")) in LayoutTemplates.MODES \
		and tiles >= MIN_TILES and tiles <= MAX_TILES and tiles % 2 == 0 \
		and int(p.get("seed", -1)) >= 0 and int(p.get("seed", -1)) <= SEED_MAX


static func encode(p: Dictionary) -> String:
	## "" when the settings are out of range.
	if not params_valid(p):
		return ""
	var payload := LayoutTemplates.FAMILIES.find(str(p.family))
	payload = (payload << 2) | (int(p.cols) - MIN_COLS)
	payload = (payload << 3) | (int(p.layers) - 1)
	payload = (payload << 1) | LayoutTemplates.MODES.find(str(p.mode))
	payload = (payload << 7) | (int(p.tiles) / 2 - 1)
	payload = (payload << 15) | int(p.seed)
	var value := (VERSION << 32) | (((payload * MIX) & M32) ^ SCRAMBLE)
	var digits := PackedInt32Array()
	digits.resize(7)
	for k in range(6, -1, -1):
		digits[k] = value & 31
		value >>= 5
	digits.append(check_digit(digits))
	var s := ""
	for d in digits:
		s += ALPHABET[d]
	return "%s-%s-%s" % [PREFIX, s.substr(0, 4), s.substr(4, 4)]


static func normalize(text: String) -> String:
	## Forgiving input: case, spaces, dashes and the LS prefix don't matter; O reads as 0 and
	## I/L as 1 (the usual Crockford look-alikes).
	var s := text.strip_edges().to_upper()
	for c in [0x20, 0x2D, 0x5F, 0x2E, 0x09, 0xA0, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014]:
		s = s.replace(String.chr(c), "")
	# Direction marks a phone may paste around a code.
	for c in [0x200E, 0x200F, 0x2066, 0x2067, 0x2068, 0x2069, 0x202A, 0x202B, 0x202C]:
		s = s.replace(String.chr(c), "")
	if s.begins_with(PREFIX) and s.length() == 10:
		s = s.substr(2)
	return s.replace("O", "0").replace("I", "1").replace("L", "1")


static func decode(text: String) -> Dictionary:
	## {"err": Err, "params": {...}, "code": canonical code}. params is empty unless err == OK.
	var s := normalize(text)
	if s.is_empty():
		return {"err": Err.EMPTY, "params": {}, "code": ""}
	if s.length() != 8:
		return {"err": Err.LENGTH, "params": {}, "code": ""}
	var digits := PackedInt32Array()
	for ch in s:
		var d := ALPHABET.find(ch)
		if d < 0:
			return {"err": Err.CHARS, "params": {}, "code": ""}
		digits.append(d)
	var body := digits.slice(0, 7)
	if check_digit(body) != digits[7]:
		return {"err": Err.CHECKSUM, "params": {}, "code": ""}
	var value := 0
	for d in body:
		value = (value << 5) | d
	var version := value >> 32
	if version != VERSION:
		return {"err": Err.VERSION, "params": {}, "code": ""}
	var payload := ((((value & M32) ^ SCRAMBLE) * _mix_inverse()) & M32)
	var seed := payload & 0x7FFF
	payload >>= 15
	var tiles := ((payload & 0x7F) + 1) * 2
	payload >>= 7
	var mode_i := payload & 1
	payload >>= 1
	var layers := (payload & 7) + 1
	payload >>= 3
	var cols := (payload & 3) + MIN_COLS
	payload >>= 2
	var fam := payload & 15
	if fam >= LayoutTemplates.FAMILIES.size():
		return {"err": Err.BOARD, "params": {}, "code": ""}
	var p := {"family": LayoutTemplates.FAMILIES[fam], "cols": cols, "layers": layers,
		"mode": LayoutTemplates.MODES[mode_i], "tiles": tiles, "seed": seed}
	if not params_valid(p):
		return {"err": Err.BOARD, "params": {}, "code": ""}
	return {"err": Err.OK, "params": p, "code": encode(p)}


static func check_digit(digits: PackedInt32Array) -> int:
	## Luhn mod 32: catches every single-character change and most swaps of neighbours.
	var n := ALPHABET.length()
	var factor := 2
	var total := 0
	for k in range(digits.size() - 1, -1, -1):
		var addend := factor * digits[k]
		factor = 1 if factor == 2 else 2
		total += addend / n + addend % n
	return (n - total % n) % n


static func is_code_like(text: String) -> bool:
	return decode(text).err == Err.OK


static func error_key(err: int) -> String:
	return str(ERR_KEYS.get(err, "code_err_board"))


static func display(code: String) -> String:
	## Wrapped in a left-to-right isolate so it never reorders inside a right-to-left sentence.
	return String.chr(0x2066) + code + String.chr(0x2069)


static func _mix_inverse() -> int:
	## MIX^-1 mod 2^32 (Newton's iteration; 64-bit wrap-around keeps the low 32 bits exact).
	var x := MIX
	for k in 5:
		x = (x * (2 - MIX * x)) & M32
	return x
