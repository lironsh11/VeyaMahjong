# Veya Mahjong — 2D Production-Oriented Asset Pack v1.0

This is an editable, lightweight **game asset kit**, not an executable Godot game.

Folder quick reference: `tiles/` (42 faces × 4 themes × PNG 128/256 + SVG + atlases), `backgrounds/` (3 worlds, maps, gameplay), `ui/` (buttons, panels, icons, HUD, rewards), `branding/`, `app_icons/`, `decorations/` (26), `effects/` (4 12-frame atlases), `audio/` (13 sound effects + 3 loops), `levels/` (150 validated demo stages), `localization/` (EN/HE), `config/` (UI, worlds, bindings), `previews/` (10 design mockups), `marketing/`, `references/`, `tools/`.

Use Godot 4.x with Compatibility Renderer for older phones, runtime PNG textures from `png_128` or `png_256`, and 540px or 1080px backgrounds. SVG sources have text outlined as paths. No fonts are redistributed. The asset names and binding JSON files are intended to simplify the next implementation step.

Sample levels have a proven initial removal sequence; arbitrary player moves can still dead-end. In the engine implement Undo, Hint, a verified-solvable Shuffle/Rescue, pause/resume, save, localization, dynamic safe areas, accessibility, native store and ads, GDPR/consent as applicable and device testing.

Store previews are CONCEPT art until actual gameplay matches. Validate App Store/Google Play compliance, licensing, trademark and marketing details before publishing.
