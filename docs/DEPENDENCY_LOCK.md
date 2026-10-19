# Dependency lock

Verified on 2026-10-18. "Installed" = present and used in this repository today.
"Researched" = checked against primary sources (GitHub releases/tags, developer.android.com,
developer.apple.com, docs.godotengine.org), not installed or device-tested here.

## Installed and used

| Component | Version | Notes |
|---|---|---|
| Godot Engine | **4.7.stable.official.5b4e0cb0f** | Editor + export templates 4.7.stable (Windows host). 4.7.2-stable (2026-08-18) exists; upgrading is recommended before release and needs only a re-export and a test run. |
| Renderer | GL Compatibility (OpenGL ES 3 / OpenGL 3.3) | Chosen for low-end Android coverage and no shader-compile stutter. |
| Android export | Godot 4.7 defaults: minSdk 24, targetSdk 36, compileSdk 36 | targetSdk 36 meets Google Play's requirement for new apps/updates from 2026-08-31. |
| Android SDK (host) | build-tools 34-37, platforms 30-37, NDK 25-27 | Godot's non-Gradle APK writer and the Gradle template both used. |
| JDK (host) | Microsoft OpenJDK 17.0.18 | Required by Godot 4.x Android export. |
| Font | Rubik variable (SIL OFL 1.1), from github.com/google/fonts | Latin, Cyrillic, Hebrew. `assets/fonts/Rubik-OFL.txt` ships with it. |
| CJK glyphs | Operating-system fonts via `SystemFont` + Godot system fallback | No CJK font files are redistributed. See LOCALIZATION.md. |
| ICU data | `internationalization/locale/include_text_server_data=true` | Still required in 4.7 for UAX#14 / CJK line breaking in exports (~4 MB). |

No third-party Godot addons/plugins are installed (`addons/` is empty).

## Researched, not installed (monetization)

| Purpose | Candidate | Version / date | Status for this project |
|---|---|---|---|
| Google Play Billing | godot-sdk-integrations/godot-google-play-billing | 3.3.0 (2026-07-27), Billing Library 9.1.0, Android v2 plugin (needs Gradle build), wrapper `class_name BillingClient`, singleton `GodotGooglePlayBilling` | **Installed 2026-10-19** in `addons/GodotGooglePlayBilling/` (release zip from GitHub, unchanged) and enabled in `project.godot` `[editor_plugins]`; it adds `com.android.billingclient:billing-ktx:9.1.0` and the BILLING permission to Gradle builds. The adapter (`scripts/services/iap/GooglePlayBillingProvider.gd`) was checked against its `Utils.kt` field names (one-time price from `one_time_purchase_offer_details_list`). **Not device-tested yet**: needs the Play Console products. The README says Godot 4.2+; it does not state 4.7. |
| iOS IAP (StoreKit 1) | godot-ios-plugins `InAppStore` | No prebuilt 4.x release; build from source. Last fix targets Godot 4.5/4.6 | Not integrated. Event-polling API. |
| iOS IAP (StoreKit 2) | godot-sdk-integrations/godot-storekit2 | v0.2 (2025-09-18), builds for 4.5-4.6.2, README says "API isn't stable" | Not integrated. |
| Cross-platform IAP | hyodotdev/openiap godot-iap | 4.0.3 (2026-10-16); needs iOS 17+, AGP 8.9.1+ (issue #511 reports stock 4.6/4.7 template uses AGP 8.6.1) | Not integrated; would need a template upgrade. |
| Ads (AdMob + UMP + ATT) | godot-sdk-integrations/godot-admob | v7.0 (2026-05-27), "tested against Godot 4.7" (its config file says 4.7 beta1); play-services-ads 24.9.0; iOS GMA 12.14.0 | Recommended candidate. **Not integrated**; `ads_enabled` is false. |
| Ads (alternative) | poingstudios/godot-admob-plugin | v5.1.0 (2026-09-13); minimum 4.5; iOS 15+ | Not integrated. |

## Store and platform requirements (researched)

- **Google Play:** targetSdk 36 is required for new apps/updates from 2026-08-31 (extensions to 2026-11-01). 64-bit ABI is required alongside any 32-bit ABI; this build ships arm64-v8a + armeabi-v7a. Support for 16 KB memory pages is required for apps targeting API 35+. The official page also names 2027-02-01 as the hard cutoff for updates. Godot 4.7 pads uncompressed `.so` files to 16 KB in its APK writer (NDK r29, AGP 8.6.1); verify with `zipalign -c -P 16 -v 4` before release. This is inferred compliance and was not verified on a 16 KB device.
- **Apple:** uploads must be built with Xcode 26+ / iOS 26 SDK (since 2026-04-28); from April 2027 the iOS 27 SDK is required. Godot 4.7's default `min_ios_version` is 14.0. Raise it if a plugin needs more (Poing 15, godot-iap 17).
