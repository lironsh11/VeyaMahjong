# Godot implementation handoff

**Import root:** `res://assets/veya/` (copy these folders beneath it). Recommended 2D Compatibility renderer. Example tile path: `res://assets/veya/tiles/classic/png_128/character_5.png`.

**Gameplay screen:** Base canvas reference 1080×1920 (responsive aspect; no hard-coded positions); tile art aspect 256:328; logical coordinates from `levels/levels_001_150_verified.json`. Source sprite has small padding and shadow. Keep visual tile sprites distinct from logical hitboxes, so tile selection feels reliable.

**Tiles:** `tiles/atlases/classic_128_atlas.png` and matching `.json` let a Texture2D atlas be subdivided accurately. Each tile uses `face`, `x`, `y`, `z` and separate match-group semantics for Flowers/Seasons. The provided step-by-step solution is a verified witness, not a forced autoplay path.

**UI:** Render button labels with Godot FontFile or DynamicFont chosen/licensed by developer. Source vector icons have no embedded font dependencies. PNG buttons are label-free to enable translation. Separate state PNGs exist. Nineslice panels should be evaluated with `NinePatchRect` and tuned corner margins around 30-45 logical pixels, adapting from the 512/640px SVG sources.

**Performance:** Load one world background/theme at a time. Use the 540×960 variants on low-end Android, 128×164 tiles, sprite atlases, 30 FPS low-end fallback, ≤12 particles visible per match, stop particle emissions on reduced motion. Disable filtering at very small glyph sizes only after device evaluation. Target memory usage and FPS must be benchmarked with real phones.

**World system:** Each world has `worlds/...` a full background, `gameplay/...` subdued background, `maps/...` path art, `audio/music/...` loop. Place world decoration sprites in game as editable separate nodes.

**Audio:** `audio/AUDIO_MAP.json` maps event names to WAV files and 24-second OGG loops. Set loops to loop playback; actual cross-fade may be required on target devices.

**Accessibility:** large tappable hitboxes, Reduce Motion, High Contrast, one-hand portrait handling, left-to-right and right-to-left layouts, hint controls without paywalls, accessibility labels.

**Not implemented:** No actual Godot project, scenes, SFX event playback, persistence, backend, IAP/Ads, privacy flows or Play Store/App Store signing are included. The next coding prompt should explicitly request those systems and validate their status separately.
