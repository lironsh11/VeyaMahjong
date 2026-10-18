class_name AdProviderBase
extends RefCounted
## Interface every ad provider adapter implements. Adapters translate a native plugin's API
## into these calls; AdsService owns all policy (caps, consent, duplicate protection).

func initialize(_personalized: bool) -> void:
	pass


func set_personalized(_personalized: bool) -> void:
	pass


func load_rewarded(_placement: String) -> void:
	pass


func cancel_load(_placement: String) -> void:
	pass


func is_rewarded_loaded(_placement: String) -> bool:
	return false


func show_rewarded(_placement: String, on_done: Callable) -> void:
	## on_done(earned: bool). Adapters may call it more than once (SDK quirks); AdsService
	## deduplicates by grant id.
	on_done.call(false)


func load_interstitial() -> void:
	pass


func is_interstitial_loaded() -> bool:
	return false


func show_interstitial(on_closed: Callable) -> void:
	on_closed.call()


func dispose() -> void:
	pass
