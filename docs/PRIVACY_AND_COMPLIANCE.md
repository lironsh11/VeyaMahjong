# Privacy and compliance (for owner/legal review)

This document describes the **actual** data behaviour of the current build (1.0.0, checked against
the code on 2026-11-14). It is not legal advice and does not by itself make the app compliant with
GDPR/UK GDPR, CCPA/CPRA, COPPA, LGPD, APPI, PIPA, Israeli privacy law or store policies.

The published policies must match this document. They live in the website repo
`C:\Users\liron\lishi-mahjong-site` (`site/legal/*.html`, see its README) and are live at
mahjong.bylishi.com. **When the code changes how data is stored, sent or shared, update this file,
the four policy pages (privacy and terms, English and Hebrew) and redeploy the site.**

## What the current build does

| Area | Behaviour |
|---|---|
| Network | Only the ad SDKs (LevelPlay, Meta) and the store billing. The game's own code makes no network calls (no HTTP client anywhere in `scripts/`). At every launch `IAPService` asks Google Play / the App Store for prices and for the items the player owns. The Privacy, Terms and Support rows in Settings open mahjong.bylishi.com in the browser (`PrivacyService.open`). |
| Accounts | None. No login, no cloud save. On iOS, Restore Purchases runs `AppStore.sync`, which can show Apple's own sign-in sheet. |
| Device identifiers | The game reads none. The ad SDKs use the advertising ID (Android `AD_ID`; IDFA on iOS only after ATT allows it) and, on Android, the app set ID (`play-services-appset` in `android/plugins/LevelPlayBanner.gdap`). iOS also declares SKAdNetwork ids, and `NSAdvertisingAttributionReportEndpoint` (`https://postbacks-is.com`) sends copies of the SKAdNetwork postbacks to ironSource. |
| Permissions | Android: `INTERNET`, `ACCESS_NETWORK_STATE`, `AD_ID` (ads), `VIBRATE` (optional haptics), `BILLING` (added by the Play Billing Library). iOS: the ATT prompt (`NSUserTrackingUsageDescription`). No camera, microphone, photos, contacts or location. |
| Local storage | `user://save/veya_save.json` plus `.tmp`, `.bak` and `.corrupt-<time>` copies (`SaveService`): progress with dates, settings, daily records, economy and grant ledger, cosmetics, Play Together names/colours/results, Studio boards (codes), entitlements and store transaction ids, ad counters, privacy choices, install time, play counts. Stays on the device. **Android:** cloud backup is disabled (`user_data_backup/allow=false`); whether Android 12+ device-to-device transfer copies it was not checked (needs the merged manifest). **iOS:** nothing excludes the save from iCloud / computer backups, so it is backed up like other app data. |
| Analytics | An event schema and consent gate exist, but **no provider is integrated and `analytics_enabled` is false**. In debug builds only, a local in-memory ring buffer shows recent events; it is never transmitted. |
| Ads | LevelPlay banner, rewarded and interstitial (Android + iOS). Demand: the ironSource bidder and Meta Audience Network only (Android: `facebook-adapter` + `audience-network-sdk`; iOS: `IronSourceFacebookAdapter` pod). No Unity Ads adapter, no AdMob. Remove Ads (or the Starter Bundle) turns off the banner and interstitials; rewarded videos stay available. Consent through the game's own dialog (below). |
| Purchases | **Live.** Google Play: the six one-time products are active. App Store: the same six products were submitted with 1.0.0 on 2026-11-14 (waiting for review). Products in `data/config/products.json`: `remove_ads`, `theme_bundle`, `starter_bundle` (non-consumable) and `coins_s/m/l` (consumable). No receipt-validation server. |
| Crash reporting | None integrated. |
| Notifications | None (no local or push notifications). |
| Clipboard | Written only on a tap: Daily "Share" (app name, date, "solved"), Board Studio / Free Play "Copy code" (a share sentence with the board code). Read only when the player taps "Paste" under Enter code (`StudioScreen.gd`). |

The only launch consent prompt is the ads consent dialog, and only on devices that count as
Europe/UK (below). Declining or never seeing consent cannot affect gameplay.

## Purchases and restore

- On every store connection (`IAPService._on_store_connected`) the game queries products and
  owned purchases. Owned non-consumables are re-applied silently, so they come back after a reset
  or reinstall without tapping Restore. Restore Purchases is in the Shop and in Settings.
- **The Starter Bundle's contents (1,500 coins, 5 Hints, 5 Shuffles, 10 Undos) are granted again
  whenever the store reports the bundle as owned and the grant ledger has no record of it.** The
  ledger lives in the save, so after Reset Local Progress or a reinstall the contents are paid out
  again. This matches the design note in MONETIZATION.md ("Restore brings back … the starter
  bundle's contents") and is stated in the published policy and terms, but it also means a player
  can reset to get the bundle's coins again. Decide whether to keep it.
- Coins from coin packs are consumed after the grant is saved and cannot be restored.
- Refunds of non-consumables are revoked on the next sync; consumable refunds can't be detected
  without a server.

## Consent architecture

- `PrivacyService.needs_launch_prompt()` (analytics) becomes true only when a data-collecting
  feature is enabled.
- Analytics queue only if: flag on **and** consent `granted` **and** a provider is attached.
  Withdrawing consent clears queued events.
- Ads: the game's own dialog (`scripts/ui/ConsentDialog.gd`, logic in `PrivacyService`). Google
  UMP and any AdMob app id were removed from the game and both native plugins.
  - At launch `PrivacyService.resolve_ads_consent_region()` treats consent as **required** when
    the device region (OS locale) is in the EEA, the UK or Switzerland, **or** the time zone
    starts with `Europe/` (plus Atlantic/Canary, Madeira, Azores, Reykjavik, Faroe,
    Arctic/Longyearbyen, Asia/Nicosia, Asia/Famagusta). The `Europe/` prefix also covers
    non-EU countries (for example Russia, Ukraine, Turkey, Serbia), and a phone set to an EU
    locale gets the dialog anywhere. BootScreen then shows the dialog once: non-dismissible,
    Accept and Decline (Hebrew "לא, תודה") equally prominent, privacy policy link.
  - **Gap:** EU outermost regions are not detected (Réunion, Guadeloupe, Martinique, French
    Guiana, Mayotte, Saint-Martin): their locale codes and `Indian/…` / `America/…` time zones are
    not in the lists, so they get no dialog.
  - Elsewhere consent is recorded as `not_required` (personalized ads, no dialog). A device that
    later moves into Europe/UK after `not_required` is asked again; dialog answers (`obtained` /
    `denied`) are kept.
  - Settings → Privacy choices reopens the dialog for everyone and shows the current state.
  - Decline = non-personalized ads: only LevelPlay's GDPR flag is sent
    (`LevelPlay.setConsent(false)` / `LPMPrivacySettings setGDPRConsent:NO`); banner, rewarded and
    interstitials still run. **No US state-law signal (`do_not_sell`) is sent**, so the policy
    points US players to the device's ad-ID settings. The banner is hidden only while a Europe/UK
    device has not answered yet; `AdsService.initialize()` waits for an answer.
  - iOS: the ATT prompt is requested once, after the consent answer (or right away when the answer
    is `not_required`). Meta's `FBAdSettings.setAdvertiserTrackingEnabled` follows the ATT answer
    only (`LSLevelPlayBridge.m`), not the consent dialog.
  - Reset Local Progress clears the consent answer (the save is recreated with defaults; only
    settings are kept), so a Europe/UK device is asked again.
- **Not an IAB TCF certified CMP.** No TC string is written. This is acceptable only because no
  Google demand (AdMob / Ad Manager) is in the LevelPlay waterfall: today it is the ironSource
  bidder and Meta only, which take consent through the LevelPlay consent API. **If Google demand
  is ever added, a Google-certified CMP (IAB TCF v2.2) is required first.** Counsel should
  confirm the dialog text (`consent_body`, 10 languages) and the region detection.
- Settings → Privacy shows the analytics choice; it is disabled with "This version doesn't collect
  any usage statistics" while no provider exists.

## Legal links

`data/config/privacy_config.json` points at the published pages:

| Key | URL |
|---|---|
| `privacy_policy_url` | https://mahjong.bylishi.com/privacy/ |
| `terms_url` | https://mahjong.bylishi.com/terms/ |
| `support_url` | https://mahjong.bylishi.com/contact/ |
| `data_deletion_url` | https://mahjong.bylishi.com/privacy/#delete |
| `support_email` | support@bylishi.com |

Store metadata uses the same pages: App Store Connect privacy URL `/privacy/` (Hebrew locale
`/he/privacy/`), support URL `/contact/`, marketing URL `/` (`publish-asc.mjs` in the site repo);
Google Play privacy policy `/privacy/` and data deletion `/privacy/#delete`. **Never move or rename
these URLs or the `id="delete"` anchors.** Hebrew versions: `/he/privacy/`, `/he/terms/`,
`/he/contact/`. Legal pages never auto-redirect by language; only the home page sends visitors in
Israel to `/he/`.

## Store disclosures (based on this build)

- **Google Play Data safety (with ads, LevelPlay + Meta):** declare **Contains ads** and
  **In-app purchases**. The ad SDKs collect and share device or other IDs (advertising ID, app set
  ID), approximate location (IP) and app interactions / diagnostics for advertising, fraud
  prevention and analytics; data is encrypted in transit; users can request deletion through the
  SDK providers. Purchase history is handled by Google Play. Re-check against the current LevelPlay
  and Meta SDK data-safety guidance when SDK versions change.
- **Apple App Privacy (with ads):** Identifiers (device ID / IDFA after ATT consent), Usage
  Data and Diagnostics, used for third-party advertising and analytics; tracking is declared
  because the ATT prompt is shown. Purchases go through StoreKit (Apple). `PrivacyInfo.xcprivacy`
  is generated by Godot's iOS export. Review its required-reason API declarations (e.g. file
  timestamps, UserDefaults) in Xcode.
- **Age rating:** a tile puzzle with no violence, chat, user-generated content or gambling
  mechanics (no loot boxes or randomized paid rewards). It has an in-game currency (coins), in-app
  purchases of known items and ads; the App Store answers are all "none" with advertising = yes
  (`publish-asc.mjs`). The game is **not** child-directed (LevelPlay apps were created with
  `coppa: 0`); do not opt into Google Play Families unless all family-policy requirements are met.

## Data deletion

All data is local: uninstalling the app deletes it from the device, and Settings → "Reset Local
Progress" (confirmation required) deletes the save and its copies and starts a new one with only
the settings kept. Store purchases come back from the store (see Purchases and restore); bought
coin packs do not. On iOS, older copies can remain in iCloud / computer backups. No server-side data
exists to delete. If analytics or another data-collecting feature is added, the policy must
describe its data and opt-outs.

## Trademark and originality

- All art, audio and levels come from the supplied pack, whose LICENSE_AND_ORIGINS states they
  are original. No competitor branding, art, sound or level sequences are used.
- The Rubik font (SIL OFL 1.1) is redistributed with its licence. CJK uses OS fonts, which are not
  redistributed.
- The app icon (v4) was supplied by the owner and is not covered by the pack's licence note;
  the owner must confirm commercial rights to it (docs/BRANDING.md).
- **Owner action:** trademark clearance for "LiShi Mahjong" in target markets (not performed).
