class_name MockAdProvider
extends AdProviderBase
## QA-ONLY fake provider (debug builds with feature flag qa_mock_services). Lets testers and
## automated tests exercise no-fill, not-completed, show-failure and duplicate-callback paths.
## It is never selected in release builds and never shows anything resembling a real ad.

enum Mode { FILL, NO_FILL, NEVER_LOADS, NOT_COMPLETED, DUPLICATE_CALLBACK, SHOW_FAILS }

static var mode: int = Mode.FILL
var _loaded: Dictionary = {}
var _interstitial_loaded: Dictionary = {}
var shown: Array = []   ## units shown, for tests


func load_rewarded(unit: String) -> void:
	match mode:
		Mode.FILL, Mode.NOT_COMPLETED, Mode.DUPLICATE_CALLBACK, Mode.SHOW_FAILS:
			_loaded[unit] = true
			load_state_changed.emit(unit, true, false)
		Mode.NO_FILL:
			_loaded.erase(unit)
			load_state_changed.emit(unit, false, true)
		_:
			_loaded.erase(unit)


func is_rewarded_loaded(unit: String) -> bool:
	return _loaded.has(unit)


func show_rewarded(unit: String, _placement: String, on_done: Callable) -> void:
	_loaded.erase(unit)
	shown.append(unit)
	match mode:
		Mode.NOT_COMPLETED:
			on_done.call(false, false)
		Mode.SHOW_FAILS:
			on_done.call(false, true)
		Mode.DUPLICATE_CALLBACK:
			on_done.call(true, false)
			on_done.call(true, false)
		_:
			on_done.call(true, false)


func load_interstitial(unit: String) -> void:
	if mode == Mode.FILL:
		_interstitial_loaded[unit] = true
		load_state_changed.emit(unit, true, false)
	else:
		_interstitial_loaded.erase(unit)


func is_interstitial_loaded(unit: String) -> bool:
	return _interstitial_loaded.has(unit)


func show_interstitial(unit: String, _placement: String, on_closed: Callable) -> void:
	_interstitial_loaded.erase(unit)
	shown.append(unit)
	on_closed.call()
