extends Node
## Coins and booster inventory (hint, shuffle, undo). Numbers live in data/config/economy.json.
##
## Rules that keep the economy safe:
## - grant() is the ONLY way coins or boosters are added. Every grant has a unique id that is
##   recorded in a ledger before it is saved, so retries, duplicate SDK callbacks, IAP replays
##   and double taps never pay twice.
## - Balances never go negative and are clamped to the configured limits.
## - Spending (buy/consume) is synchronous and tied to an action that already happened.
## - The flag "economy_enabled" is a kill switch: when off, helpers are free and unlimited.
##
## Grant id namespaces: start_v1, welcome_existing_v1, level:<id>, world:<id>, daily:<date>,
## tasks:<date>, ad:<placement>:<seq>, iap:<transaction>.

signal wallet_changed
signal inventory_changed(item: String)

const PATH := "res://data/config/economy.json"
const AD_LEDGER_KEEP := 400  ## newest ad grant ids kept (ids are monotonic, so old ones can't recur)

var cfg: Dictionary = {}


func _ready() -> void:
	reload_config()
	GameState.data_reset.connect(_apply_start_grants)
	_apply_start_grants()
	_prune_ad_ledger()


func reload_config() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _econ() -> Dictionary:
	return GameState.data.economy


func _apply_start_grants() -> void:
	var start: Dictionary = cfg.get("start_grant", {})
	if not start.is_empty():
		grant(str(start.id), start, "start")
	var e := _econ()
	if bool(e.get("legacy_player", false)):
		var welcome: Dictionary = cfg.get("legacy_welcome_grant", {})
		if not welcome.is_empty():
			grant(str(welcome.id), welcome, "welcome")


# --- state ----------------------------------------------------------------------------

func helpers_free() -> bool:
	return not FeatureFlags.enabled("economy_enabled")


func items() -> Array:
	return cfg.get("items", ["hint", "shuffle", "undo"])


func coins() -> int:
	return int(_econ().get("coins", 0))


func count(item: String) -> int:
	return int(_econ().inv.get(item, 0))


func has_grant(grant_id: String) -> bool:
	return _econ().ledger.has(grant_id)


# --- adding ---------------------------------------------------------------------------

func grant(grant_id: String, contents: Dictionary, source: String) -> bool:
	## Adds coins/items from `contents` (keys: coins, hint, shuffle, undo) once per grant id.
	## Returns false (and changes nothing) if this id was already granted.
	if grant_id == "" or has_grant(grant_id):
		return false
	var e := _econ()
	var limits: Dictionary = cfg.get("limits", {})
	var added_coins := int(contents.get("coins", 0))
	if added_coins > 0:
		e.coins = mini(coins() + added_coins, int(limits.get("max_coins", 999999)))
	var changed_items: Array = []
	for item in items():
		var n := int(contents.get(item, 0))
		if n > 0:
			e.inv[item] = mini(count(item) + n, int(limits.get("max_item", 999)))
			changed_items.append(item)
	e.ledger[grant_id] = int(Time.get_unix_time_from_system())
	GameState.save_now()
	if added_coins > 0:
		AnalyticsService.track("currency_earned", {"source": source, "amount": added_coins})
		wallet_changed.emit()
	for item in changed_items:
		inventory_changed.emit(item)
	return true


# --- spending -------------------------------------------------------------------------

func price(item: String, qty: int) -> int:
	## Coin price for a pack of `qty`, or -1 if that pack is not sold.
	var table: Dictionary = cfg.get("prices", {}).get(item, {})
	return int(table.get(str(qty), -1))


func pack_sizes(item: String) -> Array:
	var out: Array = []
	for k in cfg.get("prices", {}).get(item, {}):
		out.append(int(k))
	out.sort()
	return out


func can_afford(item: String, qty: int) -> bool:
	var p := price(item, qty)
	return p >= 0 and coins() >= p


func buy(item: String, qty: int) -> bool:
	var p := price(item, qty)
	if p < 0 or coins() < p:
		return false
	var e := _econ()
	e.coins = coins() - p
	e.inv[item] = mini(count(item) + qty, int(cfg.get("limits", {}).get("max_item", 999)))
	GameState.save_now()
	AnalyticsService.track("currency_spent", {"item": item, "qty": qty, "amount": p})
	wallet_changed.emit()
	inventory_changed.emit(item)
	return true


func consume(item: String) -> bool:
	## Uses one booster. Always succeeds (without spending) when the economy is off.
	if helpers_free():
		return true
	if count(item) <= 0:
		return false
	_econ().inv[item] = count(item) - 1
	GameState.request_save()
	inventory_changed.emit(item)
	return true


# --- rewards and config ---------------------------------------------------------------

func level_reward(level_id: int) -> int:
	for band in cfg.get("rewards", {}).get("level_first_clear", []):
		if level_id >= int(band.from) and level_id <= int(band.to):
			return int(band.coins)
	return 0


func reward(key: String) -> int:
	## world_complete, daily_first_clear, daily_tasks_claim
	return int(cfg.get("rewards", {}).get(key, 0))


func free_undos_per_board() -> int:
	return 0 if helpers_free() else int(cfg.get("free_undos_per_board", 0))


func free_rescue_shuffles_per_board() -> int:
	return int(cfg.get("free_rescue_shuffles_per_board", 0))


func rewarded_cfg(placement: String) -> Dictionary:
	return cfg.get("rewarded", {}).get(placement, {})


func rewarded_placements() -> Array:
	return cfg.get("rewarded", {}).keys()


func ad_unit_for(placement: String) -> String:
	## App placement (win_double, booster, shop_coins, bloom_bonus, interstitial) -> ad unit name.
	if placement == "interstitial":
		return str(cfg.get("interstitial", {}).get("ad_unit", ""))
	return str(rewarded_cfg(placement).get("ad_unit", ""))


func iap_contents(product_id: String) -> Dictionary:
	return cfg.get("iap_contents", {}).get(product_id, {})


func starter_bundle_min_level() -> int:
	return int(cfg.get("starter_bundle_min_level", 0))


func welcome_contents() -> Dictionary:
	return cfg.get("legacy_welcome_grant", {})


func welcome_notice_pending() -> bool:
	return bool(_econ().get("welcome_notice_pending", false))


func clear_welcome_notice() -> void:
	_econ().welcome_notice_pending = false
	GameState.request_save()


func cap_day(today: String) -> String:
	## Day used for daily ad caps: never earlier than the latest day seen, so turning the
	## clock back cannot reset a cap.
	var e := _econ()
	var hw := str(e.get("clock_hw_day", ""))
	if today > hw:
		e.clock_hw_day = today
		return today
	return hw


func _prune_ad_ledger() -> void:
	var e := _econ()
	var ad_ids: Array = []
	for k in e.ledger:
		if str(k).begins_with("ad:"):
			ad_ids.append(k)
	if ad_ids.size() <= AD_LEDGER_KEEP:
		return
	ad_ids.sort_custom(func(a: String, b: String) -> bool: return int(e.ledger[a]) < int(e.ledger[b]))
	for i in ad_ids.size() - AD_LEDGER_KEEP:
		e.ledger.erase(ad_ids[i])
