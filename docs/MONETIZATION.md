# Monetization

**Model (owner-approved 2026-10-19): booster economy + ads + purchases, like commercial
mahjong / tile-match games.** Hint, Shuffle and Undo are boosters the player owns and spends;
coins are earned by playing (or bought) and buy more boosters; rewarded videos give boosters,
coins, double level coins or a bonus LiShi Light; interstitials run between levels; Remove Ads,
coin packs and a starter bundle are sold.

**Current state:**
- Economy: on (`economy_enabled`), fully implemented and tested on desktop with QA mocks.
- Banner: on, Android (LevelPlay + Meta bidding).
- Rewarded ads and interstitials: flags ON. LevelPlay ad units `rewarded_bonus_coins`, `rewarded_bloom_bonus`
  and `interstitial_level_complete` exist on Android and iOS (ids in `data/config/levelplay.json`).
  Each of those groups, plus the banners, has a live Meta Audience Network bidder (placement ids in
  `tools/setup_levelplay.mjs`) and the ironSource bidder. The publisher Instances API still returns
  ERR-1401 for new Meta instances; these six were added in the LevelPlay dashboard.
- Consent: the game's own dialog, Europe/UK only (see Consent). No Google UMP, no AdMob app id.
- Purchases: catalogue and consumable flow done; the billing plugin and the store product ids are
  still owner/engineering TODOs (see below).

## Economy (`data/config/economy.json`, `EconomyService`, `AssistPolicy`)

| | Value |
|---|---|
| Start pack (new players) | 300 coins, 3 Hints, 3 Shuffles, 5 Undos (`start_v1`) |
| Welcome pack (players from before the economy) | 500 coins, 5 / 5 / 10 (`welcome_existing_v1`) + one-time explanation on Home |
| First clear of a level | 20 coins (1-50), 30 (51-100), 40 (101-150); replays 0 |
| World complete | 250 |
| Daily puzzle / daily tasks | 50 / 75 |
| Prices | Hint 120 (5 for 480) · Shuffle 150 (5 for 600) · Undo 60 (5 for 240) · Extra Slot 200 (5 for 800) |
| Continue after a full tray ("send 3 tiles back") | 1st per board free, then 100, then 200 coins (`continue_costs`; the last price repeats) |
| Extra Slot intro gift (everyone, once) | 2 Extra Slots (`intro_grants`: `extra_slot_intro_v1`) |
| Win streak gifts (once per streak) | streak 5: 1 Hint · streak 7: 1 Shuffle (ledger id `streak:<run>:<n>`); streak 3+: new levels start with a free extra slot |

**Full tray:** the dialog always offers Undo (normal Undo rules), Try again and Home next to the
continue, with no countdown and no ad gate. When coins are short, the continue button opens the
Shop instead of failing silently. If the player owns an Extra Slot it is offered first (the
tiles stay where they are).

**Engagement guardrails:**
- Every streak reward is fixed and shown in advance. There are no paid random rewards, so no
  odds disclosure is needed.
- Losing a streak costs nothing but the streak: there is no "pay to save your streak" offer.
- The level-start dialog appears only when there is something to offer; "Play" without a
  booster is the default.

**Free ways forward (never a paywall soft-lock):** restart; rewinding to the last proven-solvable
point; one free rescue Shuffle per board when the board is proven stuck; the first continue
after a full tray; the first 2 Undos of each board; a
Shuffle that fails costs nothing; a Hint is charged only when a useful pair is shown (not for "no
pairs", a dead-end pair, or re-showing the same hint). The tutorial is free.

**Safety:**
- `EconomyService.grant(id, contents)` is the only way to add coins or boosters. Every grant id
  is recorded in a ledger before saving, so retries, duplicate SDK callbacks, IAP replays and
  double taps never pay twice.
- Balances never go negative and are clamped to the configured limits.
- Ad grant ids use a lifetime sequence; daily caps use a high-water day, so turning the clock
  back neither resets a cap nor replays a grant.
- Per-board allowances (`GameSession.assists`) are saved with the board, so quitting can't refill
  them.
- A local reset re-grants the start pack. Restore brings back Remove Ads, the theme bundle and the
  starter bundle's contents; **bought coins can't be restored** (there is no server record). The
  reset dialog says so.
- `economy_enabled=false` is a kill switch: helpers become free and unlimited again.

**Tuning:** change numbers in `economy.json` (it needs a new build; there is no remote config).
Log `currency_earned`, `currency_spent`, `booster_used` and `booster_out` so tuning can use real
data once analytics is enabled.

## Rewarded placements

| App placement | Reward | Daily cap | LevelPlay ad unit (Meta placement behind it) |
|---|---|---|---|
| `win_double` | Doubles the level's coins (Win dialog) | 6 | `rewarded_bonus_coins` |
| `booster` | +1 of the missing booster ("Out of …" dialog) | 5 | `rewarded_bonus_coins` |
| `shop_coins` | +60 coins (Shop) | 3 | `rewarded_bonus_coins` |
| `bloom_bonus` | +1 LiShi Light (Bloom) | 1 | `rewarded_bloom_bonus` |

The global cap is `rewarded_daily_cap` (12). A button appears **only** when a real ad has loaded,
so there are no fake buttons. A reward is granted once per grant id (tested).

## Interstitials ("balanced")

Interstitials appear only when the player taps "Next level" after a win, and only when all of
these hold:
- From level 6 (`interstitial_first_level`).
- At least 2 levels since the last one (`interstitial_min_levels_between`).
- At least 90 s after any full-screen ad, rewarded included (`fullscreen_min_seconds_between`).
  App start counts as one.
- Not right after a rewarded ad in the same level.
- Not in the tutorial, not for Remove Ads owners, and within the daily cap
  (`interstitial_daily_cap`, 6).

Progress and coins are saved before the ad. "Continue" always runs exactly once, guarded by a
watchdog.

## Banner

Shown at the bottom of every screen **except gameplay and the tutorial** (owner decision
2026-10-19: the board gets the whole screen; `AdsService.set_banner_suppressed`, counted so a
gameplay screen replacing another never flashes it). The slot stays collapsed until a real ad
loads; then the safe area grows. Hidden for Remove Ads owners, and while a Europe/UK device has
not answered the consent dialog yet. After a decline it runs non-personalized.

## Consent

The game's own dialog (`scripts/ui/ConsentDialog.gd`, logic in `PrivacyService`); no Google UMP
and no AdMob app id. At launch, when ads are on, `PrivacyService.resolve_ads_consent_region()`
decides whether consent is required:
- **Required** when the device region (from `OS.get_locale()`) is in the EEA, the UK or
  Switzerland, **or** the time zone starts with `Europe/` (plus `Atlantic/Canary`, `Madeira`,
  `Azores`, `Reykjavik`, `Faroe`, `Arctic/Longyearbyen`, `Asia/Nicosia`, `Asia/Famagusta`; the
  native `device_time_zone()` gives the IANA id). BootScreen then shows the dialog once:
  non-dismissible, Accept and Decline equally prominent, privacy policy link.
- **Elsewhere** consent is recorded as `not_required` (personalized ads, no dialog). A device
  that later moves into Europe/UK after `not_required` is asked again; dialog answers
  (`obtained` / `denied`) are kept.

Settings → "Privacy choices" reopens the dialog for everyone (when ads are on) and shows the
current state. Decline = non-personalized ads; banner, rewarded and interstitials still run.
Rewarded ads and interstitials never start before an answer is recorded. On iOS, the ATT prompt
follows the consent answer. Each dialog answer logs `ads_consent {status}`.
`ads_allow_unset_consent` exists for internal test builds only.

## Feature flags (`data/config/feature_flags.json`)

| Flag | Default | Meaning |
|---|---|---|
| `economy_enabled` | true | Booster economy (false = free unlimited helpers) |
| `ads_enabled` | true | Master switch for rewarded/interstitial providers |
| `banner_ads_enabled` | true | Bottom LevelPlay banner |
| `rewarded_ads_enabled` | true | Rewarded placements |
| `interstitials_enabled` | true | Interstitials |
| `rewarded_daily_cap` | 12 | Global rewarded cap per day |
| `interstitial_first_level` / `interstitial_min_levels_between` / `fullscreen_min_seconds_between` / `interstitial_daily_cap` | 6 / 2 / 90 / 6 | Interstitial pacing |
| `ads_allow_unset_consent` | false | Internal test builds only |
| `shop_enabled` | true | Shop tab |
| `qa_mock_services` | false | Debug builds only: QA mock ad/store providers |

## Ads: native integration (LevelPlay, Android + iOS)

The contract is in docs/NATIVE_ADS_API.md. The GDScript side is done: `LevelPlayAdProvider` is
selected when the plugin exposes `init_sdk` and `data/config/levelplay.json` has ad unit ids.

Remaining steps:
1. Done: the rewarded and interstitial ad units (`rewarded_bonus_coins`, `rewarded_bloom_bonus`,
   `interstitial_level_complete`) exist on both platforms and their ids are in `levelplay.json`;
   `ads_enabled`, `rewarded_ads_enabled` and `interstitials_enabled` are on.
2. Done: Meta bidding instances for both rewarded units and the interstitial are live on Android
   and iOS, each only in that ad unit's All Countries group (alongside the ironSource bidder).
   `node tools/setup_levelplay.mjs --dry-run` finds them by placement id.
3. Verify on the Android emulator or a device with the LevelPlay Integration Test Suite. Register
   the device as a test device in LevelPlay and in Meta Monetization Manager. Check exactly one
   grant per reward, interstitial pacing, the banner after full-screen ads, and the consent
   dialog with the device region set to Germany.

## In-app purchases

Catalogue (`data/config/products.json`):

| id | Type | Grants | Suggested price |
|---|---|---|---|
| `remove_ads` | non-consumable | `remove_ads` | ~$3.99 |
| `theme_bundle` | non-consumable | `theme_bundle` (Sakura, Ocean, Nocturne themes) | - |
| `coins_s` / `coins_m` / `coins_l` | consumable | 1,200 / 3,500 / 8,000 coins | $1.99 / $4.99 / $9.99 |
| `starter_bundle` | non-consumable, one-time | `remove_ads` + 1,500 coins, 5 Hints, 5 Shuffles, 10 Undos | $4.99 |

The starter bundle is offered from level 5 and hidden once Remove Ads is owned. Platform ids are
empty until the owner creates the products (empty = hidden). Prices come only from the store.

**Ledger:**
- Non-consumables use `GameState.data.entitlements` plus `processed_transactions`.
- Consumables and bundle contents use `EconomyService` grants with id `iap:<transaction>`. They
  are saved **before** the store is told to consume. If the app dies in between, the next store
  sync replays the purchase: the ledger blocks a second grant, and the consume is retried
  (tested).
- Pending purchases grant nothing until completed.
- Refunds of non-consumables are revoked on the next sync. Consumable refunds can't be detected
  without a server, and balances never go negative.

**Providers:**
- **Android:** `GooglePlayBillingProvider` targets godot-google-play-billing 3.x, now with
  `consume()`. **Not installed and not device-tested.** Install the plugin and verify the method
  and signal names in internal testing.
- **iOS:** `AppStoreProvider` over the project's StoreKit 2 plugin `LiShiStoreKit` (native/storekit/ios), selected when the plugin is present. Minimum iOS 15. **Only compiled by the iOS CI workflow; not device-tested** (docs/IOS_BUILD.md).
- **QA mock:** debug builds with `qa_mock_services`. It simulates success, cancel,
  pending→complete, duplicate callbacks, lost consumes, refunds and restores. Automated tests use
  it.

**Security caveat:** client-side checks are not fraud-proof. Server-side verification needs a
backend (Play Developer API / App Store Server API); none is configured.

### Store setup (owner)

- Play Console: create the in-app products (remove_ads, theme_bundle, coins_s, coins_m, coins_l, starter_bundle; whether one is consumable is decided in app code), activate them, add
  license testers, and upload an AAB to the internal testing track. Test purchases are free test
  transactions, not revenue.
- App Store Connect: create the same ids (coin packs as consumables, the rest non-consumable) and use Sandbox testers / TestFlight.
- Fill the platform IDs, rebuild, then verify purchase, cancel, pending (Play "slow test card"),
  restore after reinstall, and refund handling.

## After the package ID change (com.veyamahjong.app → com.lishimahjong.app, 2026-10-18)

Nothing external was changed; these are owner actions.

**Not bound to the package ID (no action needed):**
- LevelPlay app keys `28d197415` (Android) / `28d19e725` (iOS) and their banner ad units. The
  setup script created them with only a name, a platform and a COPPA flag (no package or store
  URL). Verified on the emulator: with the new ID, `LevelPlay.init(28d197415)` downloads the app's
  banner configuration. `data/config/levelplay.json` is unchanged.

**To update / check (external dashboards):**
1. **Meta Monetization Manager** (app ID `2738184516598537`, placements in `tools/setup_levelplay.mjs`):
   open the property's platform settings and check which Android package name and iOS bundle ID
   are registered. If they say `com.veyamahjong.app`, change them to `com.lishimahjong.app`
   (add the platforms if none are set). Meta matches bid requests against the registered app, so a
   mismatch usually means no fill in production. This could not be checked from the repo: the Meta
   setup was done outside this script.
2. **LevelPlay dashboard**: after publishing, link each app to its store listing (Play URL
   `…?id=com.lishimahjong.app`; App Store ID of bundle `com.lishimahjong.app`). Optional now: rename
   the dashboard apps "Veya Mahjong" → "LiShi Mahjong". If you do, change `appName` in
   `tools/setup_levelplay.mjs` in the same step, or the script will create duplicate apps.
3. **Local secrets file** `~/.cursor/secrets/monetization.env` still has
   `VEYA_ANDROID_PACKAGE`/`VEYA_IOS_BUNDLE` = the old ID (not edited here). Edit those two lines by
   hand, or rerun `node tools/setup_levelplay.mjs`. The rerun calls the LevelPlay API; it reuses the
   existing apps by name, so the keys stay the same.
4. **app-ads.txt**: publish it on the developer website listed in the store pages (LevelPlay and
   Meta entries). It is tied to the store listing, which must use the new ID.
5. **Play Console / App Store Connect**: create the apps with `com.lishimahjong.app` (neither exists yet).

**Devices:** builds with the old ID are a separate app (on the emulator and any phone). Their
progress does not carry over; uninstall the old "LiShi Mahjong" copy to avoid duplicates.

