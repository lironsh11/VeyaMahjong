# Release checklist (owner actions and acceptance gates)

Nothing below has been submitted, purchased or published. Store submission, account creation,
production ad serving and any spending need explicit owner approval.

## Gate 1 — Product decisions
- [ ] Approve the application/bundle ID (placeholder `com.lishimahjong.app`; it can't change after the first Play upload).
- [x] Re-scatter levels 4-50 (pack shapes kept) and rebuild 51-150; all ordered by measured difficulty.
- [ ] Playtest levels 4-150 (especially ~100-150) with real players; retune the build tools if needed.
- [ ] Decide on ads (provider, placements) and IAP (Remove Ads, Theme Bundle) for launch, or ship without.
- [ ] Trademark clearance for "LiShi Mahjong".
- [ ] Confirm commercial rights to the new app icon artwork (docs/BRANDING.md).

## Gate 2 — Legal and links
- [ ] Publish the privacy policy, terms, support page/email and a data-deletion page; fill `data/config/privacy_config.json` (https only).
- [ ] Review PRIVACY_AND_COMPLIANCE.md with counsel; complete Play Data safety and Apple App Privacy from the *final* SDK list.
- [ ] Age-rating questionnaires (IARC / Apple).

## Gate 3 — Localization
- [ ] Native-speaker review of ja, ko, de, fr, es, pt-BR, zh-Hant-TW, he, ru (`review_status` → `reviewed` once done).
- [ ] Review store listing drafts (`docs/STORE_LISTINGS/`); map to store locales (es-419/es-ES, fr-CA/fr-FR, etc.).
- [ ] Re-run `tests/run_tests.gd` after any string edit.

## Gate 4 — Builds
- [ ] Upgrade to the latest Godot 4.7.x patch (4.7.2+), re-export, re-run all tests.
- [ ] Create the upload keystore (kept out of git); configure it via Editor Settings or environment variables.
- [ ] `--export-release "Android AAB (Gradle)"` → Play internal testing.
- [ ] Create the App Store Connect app `com.lishimahjong.app`, add the three API secrets, run **iOS — Godot TestFlight** (`.github/GITHUB_ACTIONS_SETUP.md`).
- [ ] Verify 16 KB alignment of the release AAB/APK (`zipalign -c -P 16 -v 4`, bundletool).
- [ ] Increment `version/code` on every upload; update CHANGELOG.md.

## Gate 5 — Device QA (see QA_MATRIX.md)
- [ ] 2 GB-class Android, mid-range Android, tablet, foldable, notch phone; current and older iPhone; iPad.
- [ ] All 10 locales visually (CJK fonts, Hebrew RTL, German/Russian expansion) on Android **and** iOS.
- [ ] Interruptions: calls, background, rotation attempts, low memory, airplane mode, clock and timezone changes.
- [ ] TalkBack / VoiceOver pass; document limitations.
- [ ] Release-build performance: FPS, PSS, cold start, 20-minute thermal run, battery drain.
- [ ] Capture real store screenshots from the running game on each required device class.

## Gate 6 — Monetization (only if enabled)
- [ ] Install and verify the ad plugin; in-game consent dialog on a Europe/UK device (region Germany) and no dialog elsewhere; ATT after the consent answer; test ad unit IDs in QA; no-fill/timeout/duplicate-callback checks on device.
- [ ] Rebuild and compile the iOS LevelPlay plugin after the UMP removal (CI workflow `.github/workflows/ios.yml`).
- [ ] Keep Google demand (AdMob / Ad Manager) out of the LevelPlay waterfall, or add a certified IAB TCF CMP first (PRIVACY_AND_COMPLIANCE.md).
- [ ] Billing: create products, fill IDs in `products.json`, test purchase/cancel/pending/restore/refund in Play internal testing and App Store Sandbox.
- [ ] Consider server-side receipt validation (needs a backend).
- [ ] Update the Data safety / App Privacy forms and the "contains ads" declaration.

## Gate 7 — Submit (explicit owner approval required)
- [ ] Play closed testing → production rollout (staged).
- [ ] App Store review submission.
