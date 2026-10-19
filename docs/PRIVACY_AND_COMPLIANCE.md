# Privacy and compliance (draft for owner/legal review)

This document describes the **actual** data behaviour of the current build. It is not legal
advice and does not by itself make the app compliant with GDPR/UK GDPR, CCPA/CPRA, COPPA, LGPD,
APPI, PIPA, Israeli privacy law or store policies.

## What the current build does

| Area | Behaviour |
|---|---|
| Network | Only the ad SDKs (LevelPlay, Meta) and the store billing. The game itself makes no network calls. |
| Accounts | None. No login, no cloud save. |
| Device identifiers | The game reads none. The ad SDKs use the advertising ID (Android `AD_ID`; IDFA on iOS only after ATT allows it). |
| Permissions | Android: `VIBRATE` (optional haptics), `INTERNET`, `ACCESS_NETWORK_STATE`, `AD_ID` (ads). iOS: ATT prompt. |
| Local storage | `user://save/veya_save.json` (+ `.bak`/`.tmp`): progress, settings, daily records, cosmetic choices, entitlement records. Stays on the device. Android backup is disabled (`user_data_backup/allow=false`). |
| Analytics | An event schema and consent gate exist, but **no provider is integrated and `analytics_enabled` is false**. In debug builds only, a local in-memory ring buffer shows recent events; it is never transmitted. |
| Ads | LevelPlay banner, rewarded and interstitial (Android + iOS); demand: ironSource bidder and Meta Audience Network only. Consent through the game's own dialog (below). |
| Purchases | Not live (no product IDs, no billing plugin). |
| Crash reporting | None integrated. |
| Clipboard | "Share" on the Daily screen copies a short text (app name, date, "solved") only when the player taps it. |

The only launch consent prompt is the ads consent dialog, and only on Europe/UK devices (below).
Declining or never seeing consent cannot affect gameplay.

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
    Arctic/Longyearbyen, Asia/Nicosia, Asia/Famagusta). BootScreen then shows the dialog once:
    non-dismissible, Accept and Decline equally prominent, privacy policy link.
  - Elsewhere consent is recorded as `not_required` (personalized ads, no dialog). A device that
    later moves into Europe/UK after `not_required` is asked again; dialog answers (`obtained` /
    `denied`) are kept.
  - Settings → Privacy choices reopens the dialog for everyone and shows the current state.
  - Decline = non-personalized ads (`LevelPlay.setConsent(false)` / `LPMPrivacySettings
    setGDPRConsent:NO`); banner, rewarded and interstitials still run. The banner is hidden only
    while a Europe/UK device has not answered yet; `AdsService.initialize()` waits for an answer.
  - iOS: the ATT prompt is requested after the consent answer.
- **Not an IAB TCF certified CMP.** No TC string is written. This is acceptable only because no
  Google demand (AdMob / Ad Manager) is in the LevelPlay waterfall: today it is the ironSource
  bidder and Meta only, which take consent through the LevelPlay consent API. **If Google demand
  is ever added, a Google-certified CMP (IAB TCF v2.2) is required first.** Counsel should
  confirm the dialog text (`consent_body`, 10 languages) and the region detection.
- Settings → Privacy shows the analytics choice; it is disabled with "This version doesn't collect
  any usage statistics" while no provider exists.

## Legal links

`data/config/privacy_config.json` contains **empty** `privacy_policy_url`, `terms_url`,
`support_url`, `support_email` and `data_deletion_url`. Empty or non-https values disable the
Settings rows with the visible note "This link will be added before release". No links were
invented. **Owner action:** publish the policies and fill these values before submission.

## Store disclosures (based on this build)

- **Google Play Data safety (with ads, LevelPlay + Meta):** declare **Contains ads** and
  **In-app purchases**. The ad SDKs collect and share device or other IDs (advertising ID),
  approximate location (IP) and app interactions / diagnostics for advertising, fraud prevention
  and analytics; data is encrypted in transit; users can request deletion through the SDK
  providers. Re-check against the current LevelPlay and Meta SDK data-safety guidance before
  submission.
- **Apple App Privacy (with ads):** Identifiers (device ID / IDFA after ATT consent), Usage
  Data and Diagnostics, used for third-party advertising and analytics; tracking is declared
  because the ATT prompt is shown. `PrivacyInfo.xcprivacy` is generated by
  Godot's iOS export. Review its required-reason API declarations (e.g. file timestamps,
  UserDefaults) in Xcode before submission.
- **Age rating:** content is a tile puzzle with no violence, chat, user-generated content or
  gambling mechanics (no loot boxes or randomized paid rewards). It has an in-game currency
  (coins) and in-app purchases of known items; answer "in-app purchases: yes". Expect the lowest ratings (e.g. IARC 3+/PEGI 3,
  Apple 4+). Confirm with the actual questionnaires. The game is **not** designed as
  child-directed. If ads are added, configure non-personalized/age-appropriate treatment as
  required, and do not opt into Google Play Families unless all family-policy requirements are met.

## Data deletion

All data is local: uninstalling the app deletes it, as does Settings → "Reset Local Progress"
(confirmation required; store purchases are restorable). No server-side data exists to delete.
If analytics or ads are added, the policy must describe their data and opt-outs, and a deletion
URL must be provided (Play requires a deletion link for apps that collect data).

## Trademark and originality

- All art, audio and levels come from the supplied pack, whose LICENSE_AND_ORIGINS states they
  are original. No competitor branding, art, sound or level sequences are used.
- The Rubik font (SIL OFL 1.1) is redistributed with its licence. CJK uses OS fonts, which are not
  redistributed.
- The app icon (v2) was supplied by the owner and is not covered by the pack's licence note;
  the owner must confirm commercial rights to it (docs/BRANDING.md).
- **Owner action:** trademark clearance for "LiShi Mahjong" in target markets (not performed).
