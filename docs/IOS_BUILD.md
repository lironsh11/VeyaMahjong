# iOS build

## Status (2026-10-19)

| Step | Result |
|---|---|
| iOS preset (`iOS`, Xcode project only) | Configured: bundle id `com.lishimahjong.app`, **min iOS 15.0** (raised from 14.0: StoreKit 2 and the Meta Audience Network adapter need 15), arm64, 1024 px icon, ivory launch background, plugins `LevelPlayBanner` + `LiShiStoreKit` enabled, Info.plist additions (ATT text, SKAdNetwork ids) |
| Ads plugin `LevelPlayBanner` (banner, rewarded, interstitial, test suite, metadata, time zone, ATT) | Source written: `native/levelplay/ios/`. **Not compiled on this Windows machine**; compiled and linked only by the CI workflow `.github/workflows/ios.yml`. The Google UMP removal (2026-10-19) has **not been compiled yet** either: run the CI workflow |
| IAP plugin `LiShiStoreKit` (StoreKit 2) + `scripts/services/iap/AppStoreProvider.gd` | Source written: `native/storekit/ios/`. Same status: compiled by CI only, never run on a device |
| Export with the real (empty) Team ID | **BLOCKED.** Godot refuses: "App Store Team ID not specified". CI sets an obviously fake Team ID in its own checkout only |
| Signing, device run, TestFlight | **NOT POSSIBLE HERE.** Requires macOS, Xcode 26+ (iOS 26 SDK; iOS 27 SDK from April 2027), an Apple Developer account and provisioning |

No iOS binary has been signed. No IPA exists.

## How the native side is put together

Godot's `.gdip` iOS plugins are static libraries compiled against the **engine headers**, and
Godot's iOS export has no CocoaPods support. The ad and store SDKs are only distributed through
CocoaPods, so each plugin is split in two:

| Part | Where | Built by | Contains |
|---|---|---|---|
| Godot glue (`.gdip` + `.debug/.release.xcframework`) | `ios/plugins/LevelPlayBanner/`, `ios/plugins/LiShiStoreKit/` (sources in `native/*/ios/godot/`) | `native/levelplay/ios/build.sh`, `native/storekit/ios/build.sh` | The `LevelPlayBanner` / `LiShiStoreKit` singletons. Only Godot + Foundation, no SDK headers |
| SDK bridge (local CocoaPod) | `native/levelplay/ios/pod` (`LiShiLevelPlay`, Objective-C), `native/storekit/ios/pod` (`LiShiStoreKit`, Swift) | Xcode, after `pod install` | All LevelPlay / ATT / StoreKit 2 calls |

The Podfile in the exported project pulls:
- `IronSourceSDK ~> 9.6` (LevelPlay, `LPM*` API) through `LiShiLevelPlay`
- `IronSourceFacebookAdapter ~> 5.5`, which pulls `FBAudienceNetwork` 6.22 (iOS 15+). Meta is a
  LevelPlay bidder only; its placement ids live in the LevelPlay dashboard.

The `.xcframework` binaries are build outputs: `ios/plugins/.gitignore` keeps them out of git.

## Steps on a Mac (owner)

1. Install Godot 4.7.2 + export templates, Xcode 26 or later, CocoaPods (`brew install cocoapods`)
   and scons (`pip3 install scons`; only needed to generate engine headers once).
2. Build the two plugins. The first run clones Godot 4.7.2 into `~/.cache/lishi-godot` and
   generates its headers (a few minutes). Set `GODOT_TAG` if you use other templates; the
   plugins **must** match the template version.
   ```bash
   bash native/levelplay/ios/build.sh
   bash native/storekit/ios/build.sh
   ```
3. Set `application/app_store_team_id` (Editor → Project → Export → iOS). Keep signing identities
   and profiles out of git.
4. Export the Xcode project, then prepare it (Podfile, `$(inherited)` fixes, localized ATT text,
   shared scheme, `pod install`):
   ```bash
   godot --headless --export-debug "iOS" ~/lishi-ios/LiShiMahjong.ipa
   bash native/levelplay/ios/scripts/prepare_xcode_project.sh ~/lishi-ios
   ```
   Repeat step 4 after every export: the export rewrites the project.
5. Open **`LiShiMahjong.xcworkspace`** (not the `.xcodeproj`), choose the team and run on a
   device.
6. Review `PrivacyInfo.xcprivacy` and the App Privacy answers. With ads, ATT and IAP this build
   is **no longer "Data Not Collected"**. Declare at least Identifiers (device ID / IDFA when ATT
   allows), Usage Data (advertising data, product interaction), Purchases, and Tracking = yes.
   LevelPlay and Meta ship their own privacy manifests; the app's own
   `privacy/*` preset options may also need tracking domains.
7. Archive and upload to App Store Connect, then test via TestFlight (internal, then external).

## CI build check (`.github/workflows/ios.yml`)

On a GitHub macOS runner, the workflow:
1. installs Godot 4.7.2 and its templates;
2. builds both plugins;
3. exports the Xcode project with a dummy Team ID (CI checkout only, never committed; override
   with the repository variable `IOS_DUMMY_TEAM_ID`);
4. runs `prepare_xcode_project.sh` (`pod install`);
5. runs `xcodebuild` for the iOS Simulator with `CODE_SIGNING_ALLOWED=NO`;
6. checks that the app bundle has the plist keys, the 10 `InfoPlist.strings` files and the
   linked plugin symbols.

It catches compile and link errors only. It does not show ads, run consent, ATT or purchases,
and it does not check the Godot ↔ plugin ABI at runtime. That needs a device.

## Info.plist additions

These live in `export_presets.cfg` → `[preset.1.options]` → `application/additional_plist_content`.

| Key | Value / note |
|---|---|
| `NSUserTrackingUsageDescription` | English base text. Localized for en, he, ja, ko, de, fr, es, pt-BR, zh-Hant, ru through `native/levelplay/ios/InfoPlist/<lang>.lproj/InfoPlist.strings`. Godot only writes `InfoPlist.strings` when a project uses Godot translations, and this game uses its own JSON localization, so `prepare_xcode_project.sh` adds them as a localized resource. Godot locale `zh-Hant-TW` maps to Apple's `zh-Hant` |
| `SKAdNetworkItems` | `su67r6k2v3` (ironSource / LevelPlay); `v9wttpbfk9` and `n38lu8286q` (Meta). Add the ids of every other network enabled later in LevelPlay ([SKAdNetwork ID manager](https://docs.unity.com/en-us/grow/levelplay/sdk/ios/skadnetwork-id-manager)) |
| `NSAdvertisingAttributionReportEndpoint` | `https://postbacks-is.com` (ironSource) |

## Consent and ATT order

Follows docs/NATIVE_ADS_API.md, as driven by `PrivacyService`:
1. Consent first: the game's own dialog (`scripts/ui/ConsentDialog.gd`) on Europe/UK devices
   (OS locale region or `device_time_zone()`, see docs/MONETIZATION.md); elsewhere `not_required`
   is recorded without a dialog.
2. After the consent answer, `request_tracking_authorization()`, which shows the system ATT prompt. If the app is not
   active yet, the request waits for `UIApplicationDidBecomeActive`.
3. After the ATT result, the plugin calls Meta's `FBAdSettings setAdvertiserTrackingEnabled:`
   (authorized = YES).
   - It calls it through the Objective-C runtime because the method is deprecated: Meta reads the
     ATT status itself on iOS 17+.
   - It sets the flag again before LevelPlay init.

Personalized ads follow consent: `LPMPrivacySettings setGDPRConsent:` is set from
`set_personalized`. No IAB TCF strings are written (no UMP, no `GADApplicationIdentifier`).

## StoreKit (in-app purchases)

- **Provider:** `AppStoreProvider.gd`, StoreKit 2. It does not use the godot-ios-plugins
  `inappstore`, for three reasons:
  - `inappstore` is StoreKit 1;
  - it finishes transactions by product id;
  - it can only list ownership through `restoreCompletedTransactions`, so startup sync and refund
    revocation would be unsafe.
- **Consumables** (`coins_s/m/l`) are finished only in `consume()`, after IAPService saved the
  grant. Unfinished ones are replayed on the next sync, and the ledger prevents double grants.
- **Non-consumables** (`remove_ads`, `theme_bundle`, `starter_bundle`) are finished in
  `acknowledge()`.
- **Startup sync** reads `Transaction.currentEntitlements` and `Transaction.unfinished` silently.
  Refunded items disappear and are revoked.
- **Restore** runs `AppStore.sync()` first, which may show the Apple Account sign-in sheet.
- **Wiring:** IAPService must select `AppStoreProvider` on iOS:
  `elif OS.has_feature("ios") and AppStoreProvider.is_available(): provider = AppStoreProvider.new()`.
  The main session owns `IAPService.gd`.

## Owner TODOs

1. **Apple Team ID** in the iOS preset (and approve the bundle id `com.lishimahjong.app`).
2. **App Store Connect → In-App Purchases:** create these products and put their ids into
   `data/config/products.json` → `app_store_id`. Empty ids stay hidden in the shop.

   | Product id | Type |
   |---|---|
   | `remove_ads` | Non-Consumable |
   | `theme_bundle` | Non-Consumable |
   | `starter_bundle` | Non-Consumable |
   | `coins_s` | Consumable |
   | `coins_m` | Consumable |
   | `coins_l` | Consumable |

   Also accept the Paid Apps agreement and fill in banking/tax, or StoreKit returns no products.
3. **Sandbox tester:** App Store Connect → Users and Access → Sandbox. On the device, sign in
   under Settings → Developer → Sandbox Apple Account, then test buy, cancel, Ask to Buy
   (pending), restore on a second device, and a refund (revocation).
4. **LevelPlay iOS app** (app key `28d19e725`): the rewarded and interstitial ad units are in
   `data/config/levelplay.json` → `ios`, and Meta bidding is already connected with these placements:

     | Ad unit | Meta placement id |
     |---|---|
     | banner | `2738184516598537_2738184556598533` |
     | rewarded_bonus_coins | `2738184516598537_2739141546502834` |
     | rewarded_bloom_bonus | `2738184516598537_2739141389836183` |
     | interstitial_level_complete | `2738184516598537_2739141229836199` |
5. **App Privacy / privacy manifest answers** (see step 6 above) and the age rating (ads).

## iOS-specific QA to run

- Safe areas (notch, Dynamic Island, home indicator) **with the banner**: it sits above the home
  indicator, and the game's bottom margin grows only after a real fill.
- Full-screen ads: the banner must stay correct after closing; rewarded must grant once.
- ATT prompt text per language, shown after the consent answer.
- In-game consent dialog: set the device region to Germany (Settings → General → Language &
  Region), fresh install: the dialog appears once; Decline still shows (non-personalized) ads;
  Settings → Privacy choices shows the state. Region United States with a non-European time zone:
  no dialog.
- Audio interruption (call, Siri, headphone unplug) and audio after a full-screen ad.
- Background/foreground saving and haptics (`Input.vibrate_handheld` on iPhone).
- CJK and Hebrew rendering with system fonts, VoiceOver behaviour (see QA_MATRIX accessibility
  notes), iPad layout (portrait; banner 320x50 centred on wide screens).
