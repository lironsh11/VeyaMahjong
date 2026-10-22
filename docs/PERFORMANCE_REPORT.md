# Performance report

**Important:** every on-device number below comes from the **Android emulator** (x86_64,
software-backed GPU path, 2.5 GB RAM, 4 vCPU), running a **debug** build. That is not a
substitute for physical low-end phones; ARM devices with weak GPUs must be measured before launch.
Targets from the brief are listed as *targets*, not achievements.

## Measurements (2026-10-18)

| Metric | Value | Conditions | Target | Status |
|---|---|---|---|---|
| Download size (release, arm64 APK) | **38.1 MB** | unsigned size-check build, 1 ABI | < 100 MB | Met (an AAB split per ABI is similar) |
| Installed/uncompressed size | ~92 MB | of which Godot engine `.so` 71 MB, ICU data 4.8 MB, game assets ~12 MB | — | Recorded |
| Debug AAB (Gradle) | 69 MB | debug engine, 2 ABIs | — | Recorded (release will be smaller) |
| Cold start → first frame (`am start -W`) | **0.64–0.88 s** | emulator, debug build, warm disk | "quick" | Then 0.6 s branded splash minimum |
| Auto graphics profile | Low (30 FPS cap) | 4 cores, 2.5 GB RAM device class | auto-choice works | Verified |
| Frame rate during play | steady **30 FPS** (= Low cap) | 16 shuffle/hint animation cycles on a 20-tile board, perf log every 2 s | 30 FPS low-end | Met on emulator |
| Main-thread process time per frame | 0.1–3.3 ms | same session | — | Large headroom |
| Draw calls | 29–33 | Home and gameplay | small | OK |
| Draw calls, layered board (2026-10-22) | **21** for the whole frame | desktop, 136-tile 4-layer board (faces, right sides, contact shadows), perf log | small | OK. Each tile draws its shadow, sides and face as one canvas item (`TileView.TileBody`) with per-part colours, so the board batches; one TextureRect per part with its own `self_modulate` measured ~520 |
| Node count | 84 (Home) / 147 (gameplay, 20 tiles) | | | Flat during the session (no leak) |
| Object count | ~2,070, flat across 16 cycles | | no growth | No leak seen |
| Engine static memory | 56.7–59.6 MB | `OS.get_static_memory_usage` | | |
| Process PSS | **204–223 MB** | `dumpsys meminfo`, debug build, emulator GPU buffers counted | < 200 MB if practical | **Not met on emulator debug.** Re-measure a release build on ARM hardware |
| Desktop (RTX 5070 laptop) | 60 FPS | all screens, 540×960 | — | Not representative |

Headless engine timings (desktop CPU): validating all 150 levels (witness + full solve) takes
about 0.24 s in total. The worst daily board generation + validation takes a few tens of ms. A
hint (≤ 24 solver runs) is bounded at 700 ms and always runs on a worker thread.

## Built-in optimizations

- GL Compatibility renderer, no 3D, no shaders beyond default canvas, no real-time lights.
- Low-processor mode: no redraws when nothing changes (idle FPS drops to ~0 by design).
- Low profile (auto when RAM < 3 GB, or ≤ 4 CPU cores on mobile; or manual): 30 FPS cap,
  540×960 backgrounds, 256 px decorations, no particle effects.
- Tile faces come from one atlas per theme; the 256 px atlas loads only when tiles render wider
  than 150 physical pixels.
- One world's backgrounds plus one tile theme resident; `release_inactive()` runs on OS memory
  warnings.
- Pure-data solver/generator on worker threads; incremental O(1) freedom checks per tap; no
  allocation-heavy work in the input path.
- UI nine-patch textures are downscaled once at startup (0.5×) and cached.

## How to measure on a device

```bash
adb shell run-as com.lishimahjong.app touch files/perf_log.flag
```
```bash
adb logcat -s godot | grep PERF
```
```bash
adb shell dumpsys meminfo com.lishimahjong.app
```
```bash
adb shell am start -W -n com.lishimahjong.app/com.godot.game.GodotAppLauncher
```

The perf logger exists only in debug builds. For thermal behaviour, play for 15-20 minutes,
compare the first and last 2-minute FPS averages, and record device temperature
(`adb shell dumpsys thermalservice`).

## Still to measure (owner/QA, physical devices)

- 2 GB-class ARM Android phone (e.g. Android Go), mid-range Android, a recent iPhone and an older
  supported iPhone: FPS during Standard/Low, PSS with a **release** build, cold start, 20-minute
  thermal FPS stability, and battery drain per 30 minutes.
