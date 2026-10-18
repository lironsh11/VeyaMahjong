class_name MockIAPProvider
extends IAPProviderBase
## QA-ONLY store simulator (debug builds + qa_mock_services flag). Prices are clearly marked
## as test values. Exercises success, cancel, pending->complete, duplicate callbacks,
## restore and refund/revocation paths without any real money or store account.

enum Outcome { SUCCESS, CANCEL, PENDING, FAIL, DUPLICATE }

static var next_outcome: int = Outcome.SUCCESS
var owned: Dictionary = {}     # platform id -> transaction
var _counter: int = 0


func source_name() -> String:
	return "qa_mock"


func connect_store() -> void:
	service._on_store_connected()


func query_products(platform_ids: PackedStringArray) -> void:
	var out := {}
	for pid in platform_ids:
		out[pid] = {"price": "TEST 0.00", "title": pid}
	service._on_products(out)


func query_owned() -> void:
	var list: Array = []
	for pid in owned:
		list.append({"platform_id": pid, "transaction": owned[pid], "state": "purchased", "acknowledged": true})
	service._on_owned(list)


func purchase(platform_id: String) -> void:
	_counter += 1
	var tx := "QA-%s-%d" % [platform_id, _counter]
	match next_outcome:
		Outcome.CANCEL:
			service._on_purchase_failed(platform_id, "cancelled")
		Outcome.FAIL:
			service._on_purchase_failed(platform_id, "qa_failure")
		Outcome.PENDING:
			service._on_purchase_update([{"platform_id": platform_id, "transaction": tx, "state": "pending", "acknowledged": false}])
		Outcome.DUPLICATE:
			owned[platform_id] = tx
			var p := {"platform_id": platform_id, "transaction": tx, "state": "purchased", "acknowledged": false}
			service._on_purchase_update([p])
			service._on_purchase_update([p])
		_:
			owned[platform_id] = tx
			service._on_purchase_update([{"platform_id": platform_id, "transaction": tx, "state": "purchased", "acknowledged": false}])


func complete_pending(platform_id: String) -> void:
	_counter += 1
	var tx := "QA-%s-%d" % [platform_id, _counter]
	owned[platform_id] = tx
	service._on_purchase_update([{"platform_id": platform_id, "transaction": tx, "state": "purchased", "acknowledged": true}])


func refund(platform_id: String) -> void:
	owned.erase(platform_id)


func acknowledge(_transaction: String) -> void:
	pass
