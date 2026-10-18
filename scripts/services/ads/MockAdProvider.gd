class_name MockAdProvider
extends AdProviderBase
## QA-ONLY fake provider (debug builds with feature flag qa_mock_services). Lets testers and
## automated tests exercise no-fill, timeout, not-completed and duplicate-callback paths.
## It is never selected in release builds and never shows anything resembling a real ad.

enum Mode { FILL, NO_FILL, NEVER_LOADS, NOT_COMPLETED, DUPLICATE_CALLBACK }

static var mode: int = Mode.FILL
var _loaded: Dictionary = {}
var _interstitial_loaded: bool = false


func load_rewarded(placement: String) -> void:
	match mode:
		Mode.FILL, Mode.NOT_COMPLETED, Mode.DUPLICATE_CALLBACK:
			_loaded[placement] = true
		_:
			_loaded.erase(placement)


func cancel_load(placement: String) -> void:
	_loaded.erase(placement)


func is_rewarded_loaded(placement: String) -> bool:
	return _loaded.has(placement)


func show_rewarded(placement: String, on_done: Callable) -> void:
	_loaded.erase(placement)
	match mode:
		Mode.NOT_COMPLETED:
			on_done.call(false)
		Mode.DUPLICATE_CALLBACK:
			on_done.call(true)
			on_done.call(true)
		_:
			on_done.call(true)


func load_interstitial() -> void:
	_interstitial_loaded = mode == Mode.FILL


func is_interstitial_loaded() -> bool:
	return _interstitial_loaded


func show_interstitial(on_closed: Callable) -> void:
	_interstitial_loaded = false
	on_closed.call()
