class_name SeededRng
extends RefCounted
## Deterministic, engine-version-independent PRNG (xorshift64*), seeded via SplitMix64.
##
## We deliberately do not use RandomNumberGenerator for content generation: daily puzzles and
## generated levels must reproduce bit-for-bit across Godot upgrades and platforms, so the
## algorithm is pinned here. GDScript ints are signed 64-bit and wrap on overflow, which is what
## these algorithms expect; logical right shifts are emulated with masks.

const _MASK_63 := 0x7FFFFFFFFFFFFFFF

var _state: int = 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_state = _splitmix64(seed_value)
	if _state == 0:
		_state = 0x2545F4914F6CDD1D


static func _lsr(x: int, n: int) -> int:
	## Logical shift right for a 64-bit two's-complement int.
	if n <= 0:
		return x
	return (x >> n) & (_MASK_63 >> (n - 1))


static func _splitmix64(x: int) -> int:
	var z := x + -7046029254386353131  # 0x9E3779B97F4A7C15 as signed int64
	z =(z ^ _lsr(z, 30)) * -4658895280553007687  # 0xBF58476D1CE4E5B9
	z = (z ^ _lsr(z, 27)) * -7723592293110705685  # 0x94D049BB133111EB
	return z ^ _lsr(z, 31)


func next_u63() -> int:
	## Returns a non-negative 63-bit integer.
	var x := _state
	x ^= _lsr(x, 12)
	x ^= x << 25
	x ^= _lsr(x, 27)
	_state = x
	return (x * 2685821657736338717) & _MASK_63


func rand_int(lo: int, hi: int) -> int:
	## Inclusive range. Uses rejection-free modulo; bias is negligible for game-sized ranges.
	if hi <= lo:
		return lo
	return lo + next_u63() % (hi - lo + 1)


func rand_float() -> float:
	return float(next_u63() >> 10) / float(1 << 53)


func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rand_int(0, arr.size() - 1)]


func shuffle(arr: Array) -> void:
	## Fisher-Yates, in place.
	for i in range(arr.size() - 1, 0, -1):
		var j := rand_int(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func hash_string(text: String) -> int:
	## FNV-1a 64-bit over UTF-8 bytes; stable seed derivation for dates and level keys.
	var h := -3750763034362895579  # 0xCBF29CE484222325 as signed
	for b in text.to_utf8_buffer():
		h ^= b
		h *= 1099511628211
	return h
