# SCons build options for LiShi Mahjong's own iOS export template (Godot 4.7, arm64).
# Used by .github/scripts/build-godot-ios-template.sh as `profile=` when IOS_CUSTOM_TEMPLATE=1.
#
# The game is 2D on the Compatibility renderer (OpenGL ES 3). It needs GDScript, complex text
# shaping (Hebrew right-to-left, CJK), FreeType, Ogg Vorbis music, WebP/JPG textures, SVG (the
# default theme's icons) and mbedTLS (core hashing). Everything below is 3D, XR, networking,
# import-only or editor-only, and is switched off. The result is smaller and its engine code
# differs from the stock template every Godot game ships.
#
# Conservative on purpose: modules are disabled one by one (an unknown module stays on), the
# Metal driver and deprecated APIs stay as stock, and nothing is stripped by class list.

optimize = "size"
disable_3d = "yes"
vulkan = "no"            # the project never uses RenderingDevice (gl_compatibility only)
use_volk = "no"
lto = "none"             # full LTO makes the iOS link far slower for little gain

for _m in [
    "csg", "gridmap", "gltf", "fbx", "navigation_3d", "godot_physics_3d", "jolt_physics",
    "openxr", "mobile_vr", "webxr", "lightmapper_rd", "raycast", "vhacd", "xatlas_unwrap",
    "meshoptimizer", "enet", "multiplayer", "upnp", "webrtc", "websocket", "jsonrpc",
    "theora", "minimp3", "noise", "camera", "regex", "tinyexr", "hdr", "ktx", "dds", "bmp", "tga",
    "basis_universal", "astcenc", "etcpak", "cvtt", "betsy", "glslang", "interactive_music",
    "text_server_fb", "zip",
]:
    globals()["module_%s_enabled" % _m] = "no"
