class_name AdProviderBase
extends RefCounted
## Interface every ad provider adapter implements. Adapters translate a native plugin's API
## into these calls; AdsService owns all policy (caps, consent, pacing, duplicate protection).
##
## `unit` is an ad unit NAME from data/config/economy.json (rewarded_bonus_coins,
## rewarded_bloom_bonus, interstitial_level_complete); adapters map it to the platform's ad
## unit id. `placement` is the app placement (win_double, booster, ...) for reporting only.

## Emitted when a unit finishes loading (loaded=true) or a load fails (failed=true).
signal load_state_changed(unit: String, loaded: bool, failed: bool)


func initialize(_personalized: bool) -> void:
	pass


func set_personalized(_personalized: bool) -> void:
	pass


func load_rewarded(_unit: String) -> void:
	pass


func is_rewarded_loaded(_unit: String) -> bool:
	return false


func show_rewarded(_unit: String, _placement: String, on_done: Callable) -> void:
	## on_done(earned: bool, show_failed: bool). Adapters may call it more than once (SDK
	## quirks); AdsService deduplicates by grant id and ignores late calls.
	on_done.call(false, true)


func load_interstitial(_unit: String) -> void:
	pass


func is_interstitial_loaded(_unit: String) -> bool:
	return false


func show_interstitial(_unit: String, _placement: String, on_closed: Callable) -> void:
	## on_closed() once the ad is gone (or could not be shown).
	on_closed.call()


func dispose() -> void:
	pass
