extends Node
## In-app purchase facade for NON-CONSUMABLE cosmetic products and Remove Ads.
##
## - Products come from data/config/products.json; a product is offered only when it has a
##   platform product ID AND the store returned details (with a store-formatted price).
##   We never display invented prices.
## - Entitlements are stored per grant with the platform transaction id/token; a
##   transaction is processed at most once (processed_transactions), so duplicate store
##   callbacks cannot double-grant. Pending purchases grant nothing until completed.
## - restore() reconciles with what the store reports: missing previously-granted items are
##   marked revoked (refund/chargeback), present ones are (re)activated.
## - Client-side checks are NOT fraud-proof. Server-side receipt validation needs a backend
##   (see docs/MONETIZATION.md); none is configured.

signal products_updated
signal purchase_result(product_id: String, status: String, message: String)  # success|cancelled|pending|failed|already_owned
signal entitlements_changed

enum Status { UNAVAILABLE, NOT_CONFIGURED, CONNECTING, READY, ERROR }

const PRODUCTS_PATH := "res://data/config/products.json"

var status: int = Status.UNAVAILABLE
var status_reason: String = ""
var provider: IAPProviderBase = null
var _products: Array = []          # catalogue from json
var _details: Dictionary = {}      # product id -> {"price": String, "title": String}


func _ready() -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRODUCTS_PATH))
	_products = j.get("products", []) if typeof(j) == TYPE_DICTIONARY else []
	initialize()


func platform_key() -> String:
	if OS.has_feature("android"):
		return "google_play_id"
	if OS.has_feature("ios"):
		return "app_store_id"
	return ""


func platform_id(product: Dictionary) -> String:
	var k := platform_key()
	if FeatureFlags.enabled("qa_mock_services") and OS.is_debug_build():
		return "qa." + str(product.id)
	return str(product.get(k, "")) if k != "" else ""


func configured_products() -> Array:
	var out: Array = []
	for p in _products:
		if platform_id(p) != "":
			out.append(p)
	return out


func initialize() -> void:
	if not FeatureFlags.enabled("shop_enabled"):
		_set_status(Status.UNAVAILABLE, "feature_flag_off")
		return
	if FeatureFlags.enabled("qa_mock_services") and OS.is_debug_build():
		provider = MockIAPProvider.new()
	elif OS.has_feature("android") and GooglePlayBillingProvider.is_available():
		provider = GooglePlayBillingProvider.new()
	else:
		_set_status(Status.UNAVAILABLE, "no_billing_plugin")
		return
	if configured_products().is_empty():
		_set_status(Status.NOT_CONFIGURED, "no_product_ids")
		return
	_set_status(Status.CONNECTING, "")
	provider.attach(self)
	provider.connect_store()


func _set_status(s: int, reason: String) -> void:
	status = s
	status_reason = reason
	products_updated.emit()


# --- provider callbacks -------------------------------------------------------------

func _on_store_connected() -> void:
	var ids := PackedStringArray()
	for p in configured_products():
		ids.append(platform_id(p))
	provider.query_products(ids)
	provider.query_owned()


func _on_store_error(reason: String) -> void:
	_set_status(Status.ERROR, reason)


func _on_products(details: Dictionary) -> void:
	## details: platform id -> {"price": localized string from the store, "title": ...}
	_details.clear()
	for p in configured_products():
		var pid := platform_id(p)
		if details.has(pid) and str(details[pid].get("price", "")) != "":
			_details[p.id] = details[pid]
	_set_status(Status.READY, "")


func _on_purchase_update(purchases: Array) -> void:
	## purchases: [{"platform_id", "transaction", "state": "purchased"|"pending", "acknowledged": bool}]
	for pu in purchases:
		var product := _product_by_platform_id(str(pu.platform_id))
		if product.is_empty():
			continue
		match str(pu.state):
			"purchased":
				var newly := _grant(product, str(pu.transaction))
				if not bool(pu.get("acknowledged", true)):
					provider.acknowledge(str(pu.transaction))
				purchase_result.emit(product.id, "success" if newly else "already_owned", "")
				if newly:
					AnalyticsService.track("iap_completed", {"product": str(product.id)})
			"pending":
				for g in product.grants:
					if not has_entitlement(g):
						GameState.data.entitlements[g] = {"product": product.id, "state": "pending", "transaction": str(pu.transaction), "t": int(Time.get_unix_time_from_system())}
				GameState.save_now()
				purchase_result.emit(product.id, "pending", "")


func _on_purchase_failed(platform_pid: String, reason: String) -> void:
	var product := _product_by_platform_id(platform_pid)
	var pid := str(product.get("id", platform_pid))
	if reason == "cancelled":
		purchase_result.emit(pid, "cancelled", "")
	else:
		AnalyticsService.track("iap_failed", {"product": pid, "reason": reason})
		purchase_result.emit(pid, "failed", reason)


func _on_owned(owned: Array) -> void:
	## Authoritative list of what the store says the user owns (restore / startup sync).
	var owned_ids := {}
	for o in owned:
		var product := _product_by_platform_id(str(o.platform_id))
		if product.is_empty():
			continue
		owned_ids[product.id] = true
		_on_purchase_update([o])
	# Revocation: entitlements from this store that the store no longer reports.
	for g in GameState.data.entitlements.keys():
		var e: Dictionary = GameState.data.entitlements[g]
		if str(e.get("state")) == "active" and not owned_ids.has(str(e.get("product"))) and str(e.get("source", "")) == provider.source_name():
			e.state = "revoked"
	GameState.save_now()
	entitlements_changed.emit()


# --- entitlements -------------------------------------------------------------------

func _grant(product: Dictionary, transaction: String) -> bool:
	var processed: Array = GameState.data.processed_transactions
	var already := transaction != "" and processed.has(transaction)
	var changed := false
	for g in product.grants:
		var e: Dictionary = GameState.data.entitlements.get(g, {})
		if str(e.get("state", "")) != "active":
			GameState.data.entitlements[g] = {
				"product": product.id, "state": "active", "transaction": transaction,
				"source": provider.source_name() if provider else "", "t": int(Time.get_unix_time_from_system()),
			}
			changed = true
	if transaction != "" and not already:
		processed.append(transaction)
	GameState.save_now()
	if changed:
		entitlements_changed.emit()
	return changed and not already


func has_entitlement(grant: String) -> bool:
	var e: Variant = GameState.data.entitlements.get(grant)
	return typeof(e) == TYPE_DICTIONARY and str(e.get("state")) == "active"


func _product_by_platform_id(pid: String) -> Dictionary:
	for p in _products:
		if platform_id(p) == pid:
			return p
	return {}


# --- UI-facing API ------------------------------------------------------------------

func offered_products() -> Array:
	## Only products the store actually returned (with real localized prices).
	var out: Array = []
	if status != Status.READY:
		return out
	for p in configured_products():
		if _details.has(p.id):
			out.append(p)
	return out


func price_text(product_id: String) -> String:
	return str(_details.get(product_id, {}).get("price", ""))


func is_owned(product: Dictionary) -> bool:
	for g in product.grants:
		if not has_entitlement(g):
			return false
	return true


func purchase(product_id: String) -> bool:
	if status != Status.READY or not _details.has(product_id):
		return false
	for p in configured_products():
		if p.id == product_id:
			if is_owned(p):
				purchase_result.emit(product_id, "already_owned", "")
				return true
			AnalyticsService.track("iap_attempted", {"product": product_id})
			provider.purchase(platform_id(p))
			return true
	return false


func restore() -> bool:
	if provider == null or status in [Status.UNAVAILABLE, Status.NOT_CONFIGURED]:
		return false
	provider.query_owned()
	return true
