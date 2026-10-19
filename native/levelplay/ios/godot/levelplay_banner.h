// Godot glue for the `LevelPlayBanner` singleton on iOS (docs/NATIVE_ADS_API.md).
// Compiled against Godot engine headers into ios/plugins/LevelPlayBanner/*.xcframework by
// native/levelplay/ios/build.sh. All SDK work lives in the LiShiLevelPlay pod
// (native/levelplay/ios/pod), so this file only needs Godot + Foundation.

#pragma once

#include "core/object/class_db.h"
#include "core/object/object.h"

class LevelPlayBanner : public Object {
	GDCLASS(LevelPlayBanner, Object);

	static LevelPlayBanner *singleton;

protected:
	static void _bind_methods();

public:
	static LevelPlayBanner *get_singleton();

	void emit_from_native(const StringName &p_signal, const Vector<Variant> &p_args);

	// Banner (existing API).
	void start(const String &p_app_key, const String &p_banner_ad_unit_id, bool p_personalized);
	void set_personalized(bool p_personalized);
	void set_enabled(bool p_enabled);
	void on_pause();
	void on_resume();

	// Shared init, rewarded, interstitial.
	void init_sdk(const String &p_app_key, bool p_personalized);
	void load_rewarded(const String &p_ad_unit_id);
	bool is_rewarded_ready(const String &p_ad_unit_id);
	void show_rewarded(const String &p_ad_unit_id, const String &p_placement_name, int64_t p_token);
	void load_interstitial(const String &p_ad_unit_id);
	bool is_interstitial_ready(const String &p_ad_unit_id);
	void show_interstitial(const String &p_ad_unit_id, const String &p_placement_name, int64_t p_token);

	// Test suite, metadata, privacy helpers, ATT.
	void set_test_suite_enabled(bool p_enabled);
	void launch_test_suite();
	void set_metadata(const String &p_key, const String &p_value);
	String device_time_zone();
	void request_tracking_authorization();

	LevelPlayBanner();
	~LevelPlayBanner();
};
