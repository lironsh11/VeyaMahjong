class_name AppStoreProvider
extends IAPProviderBase
## Adapter for the project's own StoreKit 2 plugin (ios/plugins/LiShiStoreKit, sources in
## native/storekit/ios/). The native side reports every result as one JSON string through the
## `store_event(json: String)` signal of the "LiShiStoreKit" singleton; event shapes are listed
## at the top of native/storekit/ios/pod/Sources/LiShiStoreKit.swift.
##
## Why not the official godot-ios-plugins "inappstore": it is StoreKit 1, finishes transactions
## by product id, and has no silent way to list current entitlements (only
## restoreCompletedTransactions, which can prompt for sign-in), so startup sync and refund
## revocation could not be done safely.
##
## Transactions are never finished natively on their own: consumables are finished in consume(),
## non-consumables in acknowledge(), both after IAPService saved the grant. Unfinished
## transactions are replayed by the next query_owned (startup or Restore).
##
## STATUS: written against the StoreKit 2 API but NOT yet exercised on a device; only compiled
## by the iOS CI workflow. Validate with a sandbox tester / TestFlight before enabling the shop
## in a release (docs/IOS_BUILD.md).

const SINGLETON := "LiShiStoreKit"

var _native: Object = null
var _startup_synced: bool = false
var _restore_fallback: bool = false


static func is_available() -> bool:
	if not Engine.has_singleton(SINGLETON):
		return false
	var s: Object = Engine.get_singleton(SINGLETON)
	return s != null and bool(s.call("is_supported"))


func source_name() -> String:
	return "app_store"


func connect_store() -> void:
	_native = Engine.get_singleton(SINGLETON) if Engine.has_singleton(SINGLETON) else null
	if _native == null:
		service._on_store_error("storekit_plugin_missing")
		return
	if not _native.is_connected("store_event", _on_event):
		_native.connect("store_event", _on_event)
	_native.call("start")


func query_products(platform_ids: PackedStringArray) -> void:
	if _native:
		_native.call("request_products", JSON.stringify(Array(platform_ids)))


func query_owned() -> void:
	## The first call (startup, from IAPService._on_store_connected) reads the on-device
	## entitlements silently. Later calls come from the Restore button and run AppStore.sync
	## first, which may show the Apple Account sign-in sheet.
	if _native == null:
		return
	var sync := _startup_synced
	_startup_synced = true
	_restore_fallback = sync
	_native.call("query_owned", sync)


func purchase(platform_id: String) -> void:
	if _native == null:
		service._on_purchase_failed(platform_id, "storekit_plugin_missing")
		return
	_native.call("purchase", platform_id)


func acknowledge(transaction: String) -> void:
	## Non-consumables: finishing tells StoreKit the content was delivered.
	if _native and transaction != "":
		_native.call("finish", transaction)


func consume(transaction: String) -> void:
	## Consumables: finishing lets the same product be bought again. If it fails (or the app
	## dies first) the transaction stays unfinished, the next query_owned replays it, IAPService's
	## ledger blocks a second grant and consume is retried.
	if _native and transaction != "":
		_native.call("finish", transaction)


func _on_event(json: String) -> void:
	var ev: Variant = JSON.parse_string(json)
	if typeof(ev) != TYPE_DICTIONARY:
		return
	match str(ev.get("type", "")):
		"connected":
			service._on_store_connected()
		"products":
			var out := {}
			for d in ev.get("products", []):
				var pid := str(d.get("id", ""))
				if pid != "":
					out[pid] = {"price": str(d.get("price", "")), "title": str(d.get("title", ""))}
			service._on_products(out)
		"products_error":
			service._on_store_error("products_error")
		"purchase_update":
			service._on_purchase_update(_normalise(ev.get("purchases", [])))
		"purchase_failed":
			service._on_purchase_failed(str(ev.get("product_id", "")), _short_reason(str(ev.get("reason", ""))))
		"owned":
			_restore_fallback = false
			service._on_owned(_normalise(ev.get("purchases", [])))
		"owned_error":
			# AppStore.sync failed or the sign-in was cancelled: still reconcile from the
			# entitlements already on the device, once.
			if _restore_fallback and _native:
				_restore_fallback = false
				_native.call("query_owned", false)
		"finished":
			# Nothing to do on failure: the next store sync replays an unfinished transaction.
			pass


func _normalise(purchases: Array) -> Array:
	var out: Array = []
	for p in purchases:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var state := str(p.get("state", "unknown"))
		if state not in ["purchased", "pending"]:
			state = "unknown"
		out.append({
			"platform_id": str(p.get("product_id", "")),
			"transaction": str(p.get("transaction", "")),
			"state": state,
			"acknowledged": bool(p.get("finished", false)),
		})
	return out


static func _short_reason(reason: String) -> String:
	## Native reasons can be long error descriptions; keep analytics values short and stable.
	if reason in ["cancelled", "busy", "unknown_product", "unknown_result"]:
		return reason
	if reason.begins_with("unverified"):
		return "unverified"
	return "store_error"
