#include "lishi_storekit.h"

#include "core/config/engine.h"

// Implemented in Swift (native/storekit/ios/pod/Sources/LiShiStoreKit.swift) via @_cdecl.
extern "C" {
typedef void (*lishi_sk_callback)(const char *json);
bool lishi_sk_is_supported(void);
void lishi_sk_set_callback(lishi_sk_callback cb);
void lishi_sk_start(void);
void lishi_sk_request_products(const char *ids_json);
void lishi_sk_purchase(const char *product_id);
void lishi_sk_query_owned(bool sync);
void lishi_sk_finish(const char *transaction_id);
}

LiShiStoreKit *LiShiStoreKit::singleton = nullptr;

// Called by the Swift side asynchronously on the main queue, where Godot's main loop runs.
static void lishi_storekit_on_event(const char *p_json) {
	LiShiStoreKit *store = LiShiStoreKit::get_singleton();
	if (store == nullptr || p_json == nullptr) {
		return;
	}
	store->emit_signal(SNAME("store_event"), String::utf8(p_json));
}

LiShiStoreKit *LiShiStoreKit::get_singleton() {
	return singleton;
}

void LiShiStoreKit::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &LiShiStoreKit::is_supported);
	ClassDB::bind_method(D_METHOD("start"), &LiShiStoreKit::start);
	ClassDB::bind_method(D_METHOD("request_products", "ids_json"), &LiShiStoreKit::request_products);
	ClassDB::bind_method(D_METHOD("purchase", "product_id"), &LiShiStoreKit::purchase);
	ClassDB::bind_method(D_METHOD("query_owned", "sync"), &LiShiStoreKit::query_owned);
	ClassDB::bind_method(D_METHOD("finish", "transaction_id"), &LiShiStoreKit::finish);

	ADD_SIGNAL(MethodInfo("store_event", PropertyInfo(Variant::STRING, "json")));
}

bool LiShiStoreKit::is_supported() {
	return lishi_sk_is_supported();
}

void LiShiStoreKit::start() {
	lishi_sk_start();
}

void LiShiStoreKit::request_products(const String &p_ids_json) {
	lishi_sk_request_products(p_ids_json.utf8().get_data());
}

void LiShiStoreKit::purchase(const String &p_product_id) {
	lishi_sk_purchase(p_product_id.utf8().get_data());
}

void LiShiStoreKit::query_owned(bool p_sync) {
	lishi_sk_query_owned(p_sync);
}

void LiShiStoreKit::finish(const String &p_transaction_id) {
	lishi_sk_finish(p_transaction_id.utf8().get_data());
}

LiShiStoreKit::LiShiStoreKit() {
	ERR_FAIL_COND(singleton != nullptr);
	singleton = this;
	lishi_sk_set_callback(&lishi_storekit_on_event);
}

LiShiStoreKit::~LiShiStoreKit() {
	lishi_sk_set_callback(nullptr);
	if (singleton == this) {
		singleton = nullptr;
	}
}

// Entry points named in ios/plugins/LiShiStoreKit/LiShiStoreKit.gdip.

static LiShiStoreKit *lishi_storekit_plugin = nullptr;

void lishi_storekit_init() {
	lishi_storekit_plugin = memnew(LiShiStoreKit);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LiShiStoreKit", lishi_storekit_plugin));
}

void lishi_storekit_deinit() {
	if (lishi_storekit_plugin != nullptr) {
		memdelete(lishi_storekit_plugin);
		lishi_storekit_plugin = nullptr;
	}
}
