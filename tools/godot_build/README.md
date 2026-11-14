# Custom iOS export template

`lishi_ios_custom.py` is an SCons profile for building LiShi Mahjong's own Godot 4.7 iOS
export template: 3D, XR, networking and import/editor-only modules are disabled, and the build
is optimised for size.

Why: the stock template is the same engine binary every Godot iOS game ships (including another
Godot game on this developer account). A template built for this game is smaller and its engine
code differs. App Review has flagged "binary similarity" under Guideline 4.3(a) for other engines.

How it runs: `.github/scripts/build-godot-ios-template.sh` (called from
`godot-ios-testflight-run.sh` only when `IOS_CUSTOM_TEMPLATE=1`) builds `template_release` and
`template_debug` for arm64 from the same Godot source the plugins compile against, caches the
result under `~/.cache/lishi-godot/templates/<hash>`, and `ci_patch_export_presets_ios_custom_template`
(`ci-env.sh`) points the iOS preset's `custom_template/*` at it. Without the flag the stock
template is used, exactly as before.

Verify on TestFlight before shipping it: launch, play a level, Play Together, Board Studio, the
daily, music and sound, Hebrew text, purchases (sandbox) and ads. In the device log there must be
no `Cannot get class` or `module ... not found` errors. If a needed module was switched off,
remove it from the list in `lishi_ios_custom.py` and rebuild (the cache key changes with the file).
