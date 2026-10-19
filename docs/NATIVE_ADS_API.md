# Native ads / consent API contract (Android + iOS)

One Godot singleton named **`LevelPlayBanner`** on both platforms (the name predates rewarded and
interstitial support and is kept to avoid churn in presets and scripts). GDScript talks to it only
through `scripts/services/AdsService.gd` (banner) and `scripts/services/ads/LevelPlayAdProvider.gd`
(rewarded, interstitial), plus `scripts/services/PrivacyService.gd` (consent, ATT).

Both platforms implement exactly this surface. Types are Godot variant types: String, bool,
int. Every method may be called from Godot's main thread; implementations hop to the platform UI
thread themselves. Signals are emitted on Godot's main thread (Android: GodotPlugin
`emitSignal` is thread-safe; iOS: dispatch to the main queue before emitting).

## Methods

| Method | Notes |
|---|---|
| `start(app_key: String, banner_ad_unit_id: String, personalized: bool)` | Existing. Initialises the SDK if needed, then shows the bottom banner. |
| `set_personalized(personalized: bool)` | Existing. Updates consent for all formats. |
| `set_enabled(enabled: bool)` | Existing. Banner only. |
| `on_pause()` / `on_resume()` | Existing. Banner only. |
| `init_sdk(app_key: String, personalized: bool)` | Initialises the SDK without a banner. Idempotent; shares the init with `start`. Emits `sdk_ready` once init succeeds (also if it had already succeeded), `init_failed(msg)` on failure (retries internally every 30 s like the banner). |
| `load_rewarded(ad_unit_id: String)` | Creates the rewarded ad object for this ad unit on first use and loads it. Before `sdk_ready`, queue it and load after init. |
| `is_rewarded_ready(ad_unit_id: String) -> bool` | Synchronous, from a cached flag updated by the listeners. |
| `show_rewarded(ad_unit_id: String, placement_name: String, token: int)` | Shows if ready, else emits `rewarded_show_failed(token, ad_unit_id)` immediately. `placement_name` is passed to the SDK for reporting only. |
| `load_interstitial(ad_unit_id: String)` | Same as rewarded. |
| `is_interstitial_ready(ad_unit_id: String) -> bool` | Same as rewarded. |
| `show_interstitial(ad_unit_id: String, placement_name: String, token: int)` | Shows if ready, else emits `interstitial_show_failed(token, ad_unit_id)` immediately. |
| `set_test_suite_enabled(enabled: bool)` | Must be called before init (sets the LevelPlay `is_test_suite` metadata). |
| `launch_test_suite()` | Opens the LevelPlay Integration Test Suite (debug builds only call it). |
| `set_metadata(key: String, value: String)` | Thin wrapper over `LevelPlay.setMetaData` (e.g. `do_not_sell`, `is_child_directed`). Call before init where the SDK requires it. |
| `device_time_zone() -> String` | IANA time zone id, e.g. `Europe/Berlin` (Android `TimeZone.getDefault().getID()`, iOS `NSTimeZone.localTimeZone.name`). `PrivacyService` uses it with the OS locale region to decide whether the consent dialog is required. |
| `request_tracking_authorization()` | **iOS only** (Android: emit `tracking_result("unavailable")`). ATT prompt; on iOS < 14 emit `"authorized"`. Also sets Meta `FBAdSettings.setAdvertiserTrackingEnabled(status == authorized)`. |

## Signals

| Signal | Arguments |
|---|---|
| `banner_visibility` | `(visible: bool, height_px: int)` — existing |
| `init_failed` | `(message: String)` — existing |
| `sdk_ready` | `()` |
| `rewarded_loaded` | `(ad_unit_id: String)` |
| `rewarded_load_failed` | `(ad_unit_id: String, code: int)` |
| `rewarded_closed` | `(token: int, earned: bool, ad_unit_id: String)` — emitted **exactly once per token**, ~600 ms after the SDK's close callback so a reward delivered after close is still counted (`earned` = a reward callback arrived for this token). |
| `rewarded_show_failed` | `(token: int, ad_unit_id: String)` — no `rewarded_closed` follows for that token. |
| `interstitial_loaded` | `(ad_unit_id: String)` |
| `interstitial_load_failed` | `(ad_unit_id: String, code: int)` |
| `interstitial_closed` | `(token: int)` — exactly once per token |
| `interstitial_show_failed` | `(token: int, ad_unit_id: String)` — no `interstitial_closed` follows |
| `tracking_result` | `(status: String)` — `authorized`, `denied`, `restricted`, `not_determined`, `unavailable` |

## Behaviour rules

- After a rewarded/interstitial closes or fails to show, the native side does **not** reload on
  its own; GDScript calls `load_*` again (it owns backoff and caps).
- A second `show_*` while one is on screen emits the matching `*_show_failed` for the new token.
- Never grant anything natively; rewards are decided in GDScript from `rewarded_closed.earned`.
- The banner keeps working exactly as before; a full-screen ad must not leave the banner hidden
  or double-inset afterwards (pause/resume around it if the platform needs that).
- Consent: there is no consent SDK on the native side (no Google UMP, no AdMob app id). The
  game's own dialog (`scripts/ui/ConsentDialog.gd`) records the answer in `PrivacyService`, and
  `set_personalized` feeds it to LevelPlay (Android `LevelPlay.setConsent`, iOS
  `LPMPrivacySettings setGDPRConsent:`). Personalized is only `true` when consent is obtained or
  not required.
