# Monetization

**Current state: no ads, no purchases.** Both are integrated as tested *facades* with safe
disabled states. No ad SDK or billing plugin is installed, so nothing could be sold or shown even
if the flags were turned on. The game is fully playable and never asks for money or ad views.

## Principles enforced in code (independent of any SDK)

- Hint, Undo, Shuffle/Rescue, level completion and continued play never require an ad or a purchase.
- No lives, energy, timers, currencies, loot boxes or pay-to-unblock dialogs exist.
- Rewarded ads are optional bonuses only. The single wired placement is `bonus_light` on the Win
  dialog: watching earns one bonus Veya Light, once per newly completed level, capped at
  `rewarded_daily_cap` (3) per day. The button appears **only** when a real ad has actually
  loaded (`AdsService.is_rewarded_ready`), so there are no fake buttons.
- A reward is granted once per `grant_id` (persisted). Duplicate SDK callbacks, restarts mid-ad
  and double taps cannot double-grant (tested).
- Interstitials (flag OFF): only at the natural break after "Next Level", never mid-board, never
  in the tutorial, never within 2 minutes of launch (so not right after a crash/restart), at most
  `interstitial_daily_cap` per day with `interstitial_min_levels_between`, never for players who
  own Remove Ads (tested).
- No banners.
- `AdsService.initialize()` refuses to initialize any provider until `PrivacyService` has recorded
  a CMP consent result (tested).

## Feature flags (`data/config/feature_flags.json`)

| Flag | Default | Meaning |
|---|---|---|
| `ads_enabled` | false | Master switch for any ad provider |
| `rewarded_ads_enabled` | false | Optional rewarded placements |
| `interstitials_enabled` | false | Natural-break interstitials |
| `rewarded_daily_cap` / `interstitial_daily_cap` / `interstitial_min_levels_between` | 3 / 4 / 4 | Caps |
| `shop_enabled` | true | Shows the Shop tab (with an honest "not available" state until products load) |
| `qa_mock_services` | false | Debug builds only: QA mock ad/store providers (clearly labelled, no real money) |

## Ads: integration plan

Recommended provider: **godot-sdk-integrations/godot-admob v7.0** (states Godot 4.7 support; AdMob
+ UMP consent + ATT; Android and iOS). See DEPENDENCY_LOCK.md.

1. Install the plugin (Android v2 plugin requires the Gradle build: use the "Android AAB (Gradle)"
   preset, which this repo has already built successfully).
2. Write `scripts/services/ads/AdMobProvider.gd` extending `AdProviderBase`. Map:
   `initialize()` → plugin initialize; `load_rewarded`/`is_rewarded_loaded`/`show_rewarded`
   → rewarded APIs, calling `on_done(true)` from `rewarded_ad_user_earned_reward` and `on_done(false)`
   on dismiss without reward; interstitial equivalents.
3. Run the UMP flow first and map its result to `PrivacyService.record_ads_consent("obtained"|"not_required"|"denied")`.
   On iOS, request ATT **only** if personalized ads/tracking are actually used.
4. Select the provider in `AdsService.initialize()` when `Engine.has_singleton("AdmobPlugin")`.
5. Ad unit IDs: read from a non-committed config (`config/secrets*.json` is git-ignored). Use
   **Google test ad unit IDs** for all QA builds. Never hard-code publisher IDs.
6. Validate in exported builds on real devices: load, no-fill, 8 s load timeout, close early,
   duplicate callbacks, background during an ad, consent declined, offline. Then enable
   `ads_enabled` + `rewarded_ads_enabled` for a soft launch, and leave interstitials off until
   UX testing shows they're acceptable.

## In-app purchases

Catalogue (`data/config/products.json`): **non-consumables only**.

| id | Grants | google_play_id | app_store_id |
|---|---|---|---|
| `remove_ads` | `remove_ads` | *(empty - owner creates)* | *(empty)* |
| `theme_bundle` | `theme_bundle` (unlocks Sakura, Ocean, Nocturne immediately) | *(empty)* | *(empty)* |

A product is offered only when it has a platform ID **and** the store returned details with a
localized price. Prices are never stored or invented. With empty IDs, the Shop shows
"The shop isn't available in this version", and Restore is disabled with the reason shown.

Entitlement ledger (`GameState.data.entitlements` + `processed_transactions`):
- Purchased → active (once per transaction id; duplicate callbacks report "already owned").
- Pending → nothing granted until the store confirms.
- Cancelled → nothing granted, no error dialog.
- Restore/startup sync reconciles with the store's owned list. Items the store no longer reports
  (refund/chargeback) become `revoked`.
- Local data reset clears the local copy; Restore brings purchases back (tested).
- Earned cosmetics (themes unlocked by play) are derived from progress and are separate from paid
  entitlements.

Providers:
- **Android:** `GooglePlayBillingProvider` targets godot-google-play-billing 3.x (`BillingClient`
  wrapper; query details, purchase, acknowledge, query purchases). It is resolved dynamically and
  selected only if the plugin's singleton and wrapper class exist. **Status: written against the
  documented API; not installed and not device-tested.** Some response field names (product
  details price keys) are not documented by the plugin and are read defensively. Verify them in
  internal testing.
- **iOS:** no adapter yet. Options: StoreKit 1 `InAppStore` (build from source) or StoreKit 2
  plugins (API unstable) — see DEPENDENCY_LOCK.md. Implement `IAPProviderBase` the same way.
- **QA mock:** debug builds with `qa_mock_services`. It shows "TEST 0.00" prices and a red
  "QA MOCK STORE" label and simulates success, cancel, pending→complete, duplicate callbacks,
  refund and restore. Automated tests use it.

**Security caveat:** client-side entitlement checks are not fraud-proof. For server-side
verification, add a backend that validates Google Play purchase tokens (Play Developer API) and
App Store transactions (App Store Server API) and returns signed entitlements. None is configured.

### Store setup (owner)

- Play Console: create the in-app products with IDs matching `products.json`, activate them, add
  license testers, and upload an AAB to the internal testing track. Test purchases are free test
  transactions, not revenue.
- App Store Connect: create the non-consumable IAPs and use Sandbox testers / TestFlight.
- Fill the platform IDs, rebuild, then verify purchase, cancel, pending (Play "slow test card"),
  restore after reinstall, and refund handling.
