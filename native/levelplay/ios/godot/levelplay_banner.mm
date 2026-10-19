#include "levelplay_banner.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "LSLevelPlayBridge.h"

LevelPlayBanner *LevelPlayBanner::singleton = nullptr;

static NSString *to_ns(const String &p_string) {
	NSString *s = [NSString stringWithUTF8String:p_string.utf8().get_data()];
	return s != nil ? s : @"";
}

static Variant to_variant(id p_value) {
	if ([p_value isKindOfClass:[NSString class]]) {
		return Variant(String::utf8([(NSString *)p_value UTF8String]));
	}
	if ([p_value isKindOfClass:[NSNumber class]]) {
		if (CFGetTypeID((__bridge CFTypeRef)p_value) == CFBooleanGetTypeID()) {
			return Variant((bool)[(NSNumber *)p_value boolValue]);
		}
		return Variant((int64_t)[(NSNumber *)p_value longLongValue]);
	}
	return Variant();
}

LevelPlayBanner *LevelPlayBanner::get_singleton() {
	return singleton;
}

void LevelPlayBanner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "app_key", "banner_ad_unit_id", "personalized"), &LevelPlayBanner::start);
	ClassDB::bind_method(D_METHOD("set_personalized", "personalized"), &LevelPlayBanner::set_personalized);
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &LevelPlayBanner::set_enabled);
	ClassDB::bind_method(D_METHOD("on_pause"), &LevelPlayBanner::on_pause);
	ClassDB::bind_method(D_METHOD("on_resume"), &LevelPlayBanner::on_resume);
	ClassDB::bind_method(D_METHOD("init_sdk", "app_key", "personalized"), &LevelPlayBanner::init_sdk);
	ClassDB::bind_method(D_METHOD("load_rewarded", "ad_unit_id"), &LevelPlayBanner::load_rewarded);
	ClassDB::bind_method(D_METHOD("is_rewarded_ready", "ad_unit_id"), &LevelPlayBanner::is_rewarded_ready);
	ClassDB::bind_method(D_METHOD("show_rewarded", "ad_unit_id", "placement_name", "token"), &LevelPlayBanner::show_rewarded);
	ClassDB::bind_method(D_METHOD("load_interstitial", "ad_unit_id"), &LevelPlayBanner::load_interstitial);
	ClassDB::bind_method(D_METHOD("is_interstitial_ready", "ad_unit_id"), &LevelPlayBanner::is_interstitial_ready);
	ClassDB::bind_method(D_METHOD("show_interstitial", "ad_unit_id", "placement_name", "token"), &LevelPlayBanner::show_interstitial);
	ClassDB::bind_method(D_METHOD("set_test_suite_enabled", "enabled"), &LevelPlayBanner::set_test_suite_enabled);
	ClassDB::bind_method(D_METHOD("launch_test_suite"), &LevelPlayBanner::launch_test_suite);
	ClassDB::bind_method(D_METHOD("set_metadata", "key", "value"), &LevelPlayBanner::set_metadata);
	ClassDB::bind_method(D_METHOD("device_time_zone"), &LevelPlayBanner::device_time_zone);
	ClassDB::bind_method(D_METHOD("request_tracking_authorization"), &LevelPlayBanner::request_tracking_authorization);

	ADD_SIGNAL(MethodInfo("banner_visibility", PropertyInfo(Variant::BOOL, "visible"), PropertyInfo(Variant::INT, "height_px")));
	ADD_SIGNAL(MethodInfo("init_failed", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("sdk_ready"));
	ADD_SIGNAL(MethodInfo("rewarded_loaded", PropertyInfo(Variant::STRING, "ad_unit_id")));
	ADD_SIGNAL(MethodInfo("rewarded_load_failed", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::INT, "code")));
	ADD_SIGNAL(MethodInfo("rewarded_closed", PropertyInfo(Variant::INT, "token"), PropertyInfo(Variant::BOOL, "earned"), PropertyInfo(Variant::STRING, "ad_unit_id")));
	ADD_SIGNAL(MethodInfo("rewarded_show_failed", PropertyInfo(Variant::INT, "token"), PropertyInfo(Variant::STRING, "ad_unit_id")));
	ADD_SIGNAL(MethodInfo("interstitial_loaded", PropertyInfo(Variant::STRING, "ad_unit_id")));
	ADD_SIGNAL(MethodInfo("interstitial_load_failed", PropertyInfo(Variant::STRING, "ad_unit_id"), PropertyInfo(Variant::INT, "code")));
	ADD_SIGNAL(MethodInfo("interstitial_closed", PropertyInfo(Variant::INT, "token")));
	ADD_SIGNAL(MethodInfo("interstitial_show_failed", PropertyInfo(Variant::INT, "token"), PropertyInfo(Variant::STRING, "ad_unit_id")));
	ADD_SIGNAL(MethodInfo("tracking_result", PropertyInfo(Variant::STRING, "status")));
}

void LevelPlayBanner::emit_from_native(const StringName &p_signal, const Vector<Variant> &p_args) {
	Vector<const Variant *> ptrs;
	ptrs.resize(p_args.size());
	for (int i = 0; i < p_args.size(); i++) {
		ptrs.write[i] = &p_args[i];
	}
	emit_signalp(p_signal, p_args.is_empty() ? nullptr : ptrs.ptrw(), p_args.size());
}

void LevelPlayBanner::start(const String &p_app_key, const String &p_banner_ad_unit_id, bool p_personalized) {
	[LSLevelPlayBridge.shared startWithAppKey:to_ns(p_app_key) bannerAdUnitId:to_ns(p_banner_ad_unit_id) personalized:p_personalized];
}

void LevelPlayBanner::set_personalized(bool p_personalized) {
	[LSLevelPlayBridge.shared setPersonalized:p_personalized];
}

void LevelPlayBanner::set_enabled(bool p_enabled) {
	[LSLevelPlayBridge.shared setEnabled:p_enabled];
}

void LevelPlayBanner::on_pause() {
	[LSLevelPlayBridge.shared pause];
}

void LevelPlayBanner::on_resume() {
	[LSLevelPlayBridge.shared resume];
}

void LevelPlayBanner::init_sdk(const String &p_app_key, bool p_personalized) {
	[LSLevelPlayBridge.shared initSdkWithAppKey:to_ns(p_app_key) personalized:p_personalized];
}

void LevelPlayBanner::load_rewarded(const String &p_ad_unit_id) {
	[LSLevelPlayBridge.shared loadRewarded:to_ns(p_ad_unit_id)];
}

bool LevelPlayBanner::is_rewarded_ready(const String &p_ad_unit_id) {
	return [LSLevelPlayBridge.shared isRewardedReady:to_ns(p_ad_unit_id)];
}

void LevelPlayBanner::show_rewarded(const String &p_ad_unit_id, const String &p_placement_name, int64_t p_token) {
	[LSLevelPlayBridge.shared showRewarded:to_ns(p_ad_unit_id) placement:to_ns(p_placement_name) token:p_token];
}

void LevelPlayBanner::load_interstitial(const String &p_ad_unit_id) {
	[LSLevelPlayBridge.shared loadInterstitial:to_ns(p_ad_unit_id)];
}

bool LevelPlayBanner::is_interstitial_ready(const String &p_ad_unit_id) {
	return [LSLevelPlayBridge.shared isInterstitialReady:to_ns(p_ad_unit_id)];
}

void LevelPlayBanner::show_interstitial(const String &p_ad_unit_id, const String &p_placement_name, int64_t p_token) {
	[LSLevelPlayBridge.shared showInterstitial:to_ns(p_ad_unit_id) placement:to_ns(p_placement_name) token:p_token];
}

void LevelPlayBanner::set_test_suite_enabled(bool p_enabled) {
	[LSLevelPlayBridge.shared setTestSuiteEnabled:p_enabled];
}

void LevelPlayBanner::launch_test_suite() {
	[LSLevelPlayBridge.shared launchTestSuite];
}

void LevelPlayBanner::set_metadata(const String &p_key, const String &p_value) {
	[LSLevelPlayBridge.shared setMetadataKey:to_ns(p_key) value:to_ns(p_value)];
}

String LevelPlayBanner::device_time_zone() {
	return String::utf8([[LSLevelPlayBridge.shared deviceTimeZone] UTF8String]);
}

void LevelPlayBanner::request_tracking_authorization() {
	[LSLevelPlayBridge.shared requestTrackingAuthorization];
}

LevelPlayBanner::LevelPlayBanner() {
	ERR_FAIL_COND(singleton != nullptr);
	singleton = this;
	// The bridge delivers events asynchronously on the main queue, which is where Godot's main
	// loop runs on iOS (CADisplayLink), so emitting directly is safe.
	LSLevelPlayBridge.shared.eventHandler = ^(NSString *signal, NSArray *args) {
		LevelPlayBanner *self_ptr = LevelPlayBanner::get_singleton();
		if (self_ptr == nullptr) {
			return;
		}
		Vector<Variant> values;
		for (id value in args) {
			values.push_back(to_variant(value));
		}
		self_ptr->emit_from_native(StringName(String::utf8([signal UTF8String])), values);
	};
}

LevelPlayBanner::~LevelPlayBanner() {
	LSLevelPlayBridge.shared.eventHandler = nil;
	if (singleton == this) {
		singleton = nullptr;
	}
}
