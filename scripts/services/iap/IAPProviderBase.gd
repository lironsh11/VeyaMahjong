class_name IAPProviderBase
extends RefCounted
## Adapter interface between IAPService and a native store plugin. Adapters normalise the
## plugin's callbacks into IAPService._on_* calls with platform-neutral dictionaries.

var service: Node = null


func attach(p_service: Node) -> void:
	service = p_service


func source_name() -> String:
	return "base"


func connect_store() -> void:
	service._on_store_error("not_implemented")


func query_products(_platform_ids: PackedStringArray) -> void:
	pass


func query_owned() -> void:
	pass


func purchase(_platform_id: String) -> void:
	pass


func acknowledge(_transaction: String) -> void:
	pass
