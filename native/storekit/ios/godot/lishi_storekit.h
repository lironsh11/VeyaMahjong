// Godot glue for the `LiShiStoreKit` singleton (StoreKit 2 in-app purchases).
// The StoreKit code is Swift in the LiShiStoreKit pod (native/storekit/ios/pod), exposed as C
// functions; every result comes back as one JSON string through the `store_event` signal and is
// interpreted by scripts/services/iap/AppStoreProvider.gd.

#pragma once

#include "core/object/class_db.h"
#include "core/object/object.h"

class LiShiStoreKit : public Object {
	GDCLASS(LiShiStoreKit, Object);

	static LiShiStoreKit *singleton;

protected:
	static void _bind_methods();

public:
	static LiShiStoreKit *get_singleton();

	bool is_supported();
	void start();
	void request_products(const String &p_ids_json);
	void purchase(const String &p_product_id);
	void query_owned(bool p_sync);
	void finish(const String &p_transaction_id);

	LiShiStoreKit();
	~LiShiStoreKit();
};
