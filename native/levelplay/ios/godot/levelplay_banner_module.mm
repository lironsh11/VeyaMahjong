// Entry points named in ios/plugins/LevelPlayBanner/LevelPlayBanner.gdip. Godot's iOS export
// declares them as `extern void levelplay_banner_init();` (C++ linkage) and calls them at startup.

#include "core/config/engine.h"

#include "levelplay_banner.h"

static LevelPlayBanner *levelplay_banner_plugin = nullptr;

void levelplay_banner_init() {
	levelplay_banner_plugin = memnew(LevelPlayBanner);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LevelPlayBanner", levelplay_banner_plugin));
}

void levelplay_banner_deinit() {
	if (levelplay_banner_plugin != nullptr) {
		memdelete(levelplay_banner_plugin);
		levelplay_banner_plugin = nullptr;
	}
}
