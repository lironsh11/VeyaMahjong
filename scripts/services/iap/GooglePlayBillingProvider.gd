class_name GooglePlayBillingProvider
extends IAPProviderBase
## Adapter for godot-sdk-integrations/godot-google-play-billing 3.x (Billing Library 9.x),
## whose GDScript wrapper is `class_name BillingClient extends Node` backed by the
## "GodotGooglePlayBilling" Android singleton. API per the plugin's 3.3.0 docs.
##
## STATUS: the plugin (3.3.0, Billing Library 9.1.0) is installed in res://addons and enabled
## in project.godot; field names were checked against its Utils.kt. NOT yet exercised on a
## device: validate with Play Console testing once the products exist (docs/MONETIZATION.md).
## It is only selected when the plugin's singleton and wrapper class are both present.
##
## The wrapper is resolved dynamically so this file parses even without the addon.

const SINGLETON := "GodotGooglePlayBilling"
const RESPONSE_OK := 0
const RESPONSE_USER_CANCELED := 1
const RESPONSE_ITEM_ALREADY_OWNED := 7
const PURCHASE_STATE_PURCHASED := 1
const PURCHASE_STATE_PENDING := 2

var _client: Node = null
var _inapp_type: int = 0


static func _wrapper_script() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "BillingClient":
			return load(str(c.path))
	return null


static func is_available() -> bool:
	return Engine.has_singleton(SINGLETON) and _wrapper_script() != null


func source_name() -> String:
	return "google_play"


func connect_store() -> void:
	var script := _wrapper_script()
	if script == null:
		service._on_store_error("billing_wrapper_missing")
		return
	_client = script.new()
	var consts := script.get_script_constant_map()
	if consts.has("ProductType") and typeof(consts.ProductType) == TYPE_DICTIONARY:
		_inapp_type = int(consts.ProductType.get("INAPP", 0))
	service.add_child(_client)
	_client.connect("connected", func() -> void: service._on_store_connected())
	_client.connect("connect_error", func(code: int, msg: String) -> void: service._on_store_error("connect_error_%d" % code))
	_client.connect("query_product_details_response", _on_details)
	_client.connect("query_purchases_response", _on_owned)
	_client.connect("on_purchase_updated", _on_updated)
	if _client.has_signal("consume_purchase_response"):
		_client.connect("consume_purchase_response", _on_consumed)
	_client.call("start_connection")


func query_products(platform_ids: PackedStringArray) -> void:
	_client.call("query_product_details", platform_ids, _inapp_type)


func query_owned() -> void:
	if _client:
		_client.call("query_purchases", _inapp_type)


func purchase(platform_id: String) -> void:
	var r: Variant = _client.call("purchase", platform_id)
	if typeof(r) == TYPE_DICTIONARY and int(r.get("response_code", RESPONSE_OK)) != RESPONSE_OK:
		service._on_purchase_failed(platform_id, "launch_%d" % int(r.response_code))


func acknowledge(transaction: String) -> void:
	_client.call("acknowledge_purchase", transaction)


func consume(transaction: String) -> void:
	## Consumables: consuming also acknowledges. If it fails (or the app dies first) the item
	## stays owned; the next query_purchases replays it, IAPService's ledger blocks a second
	## grant, and consume is retried.
	if _client and transaction != "":
		_client.call("consume_purchase", transaction)


func _on_consumed(_response: Dictionary) -> void:
	# Nothing to do on failure: re-querying here could loop; the next store sync (app start or
	# Restore) replays the unconsumed purchase and retries the consume.
	pass


func _on_details(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) != RESPONSE_OK:
		service._on_store_error("details_%d" % int(response.get("response_code", -1)))
		return
	var out := {}
	for d in response.get("product_details", []):
		# Field names follow Billing Library ProductDetails; formatted price is store-localized.
		var pid := str(d.get("product_id", d.get("productId", "")))
		# 3.3.0 sends a list ("one_time_purchase_offer_details_list", Billing Library 8+);
		# older builds sent a single dictionary.
		var offer: Variant = d.get("one_time_purchase_offer_details_list", d.get("one_time_purchase_offer_details", d.get("oneTimePurchaseOfferDetails", {})))
		if offer == null:
			offer = {}
		var price := ""
		if typeof(offer) == TYPE_DICTIONARY:
			price = str(offer.get("formatted_price", offer.get("formattedPrice", "")))
		elif typeof(offer) == TYPE_ARRAY and not offer.is_empty():
			price = str(offer[0].get("formatted_price", offer[0].get("formattedPrice", "")))
		if pid != "":
			out[pid] = {"price": price, "title": str(d.get("name", d.get("title", "")))}
	service._on_products(out)


func _normalise(purchases: Array) -> Array:
	var out: Array = []
	for p in purchases:
		var state := "unknown"
		match int(p.get("purchase_state", 0)):
			PURCHASE_STATE_PURCHASED: state = "purchased"
			PURCHASE_STATE_PENDING: state = "pending"
		for pid in p.get("product_ids", []):
			out.append({"platform_id": str(pid), "transaction": str(p.get("purchase_token", "")), "state": state, "acknowledged": bool(p.get("is_acknowledged", false))})
	return out


func _on_owned(response: Dictionary) -> void:
	if int(response.get("response_code", -1)) == RESPONSE_OK:
		service._on_owned(_normalise(response.get("purchases", [])))


func _on_updated(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code == RESPONSE_OK:
		service._on_purchase_update(_normalise(response.get("purchases", [])))
	elif code == RESPONSE_USER_CANCELED:
		service._on_purchase_failed("", "cancelled")
	elif code == RESPONSE_ITEM_ALREADY_OWNED:
		query_owned()
	else:
		service._on_purchase_failed("", "code_%d" % code)
