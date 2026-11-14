# Known issues and blocked dependencies

## Product / content

1. **Resolved: level pacing and mirrored tiles.** Levels 4-50 keep the pack shapes but have
   re-scattered faces (the pack placed ~74% of tiles opposite their twin), and 51-300 are generated.
   All are validated and ordered by measured difficulty (see MAHJONG_RULES_AND_SOLVER.md).
   Remaining caveat: the metrics are heuristics based on random play. Playtesting should confirm
   that levels ~130-150 and the hardest of 151-300 (~250-300) feel fair; both build tools can be retuned and rerun deterministically.
   Any rebuild after release must bump the tool's `BUILD_ID`, because in-progress saves on
   changed boards are discarded (completions are kept). Rerunning 51-150 today would reselect 14
   boards (it was built before the left/right rule), so it stays as shipped.
   Since 1.1.0 each world has 100 levels (`LevelCatalog`): its 50 1.0 levels, then 50 new ones
   that start at the world's level-50 difficulty and end a little harder, so the first levels of
   the next world are a breather. From world 3 on, random play is stuck on almost every board, so
   those worlds ramp on the careful-player measure (`DifficultyAnalyzer.skilled_fail_rate`) and the
   score. Like the other metrics it is a model, not a player: playtest the end of each world.
   Level numbers must never move again after 1.1.0 without a save migration like schema 6.
2. Difficulty bands are stored per level but not displayed.
3. Bloom: 60 discovery slots across 6 worlds; some sprites (pond, rocks, butterfly, grass
   patch) appear in two worlds. Positions were tuned on 16:9-20:9 screens only.
4. Only the `match_sparkle` and `gold_twinkle` effects are used; `petal_pop`/`ripple` are reserved.

## Platform / integrations

5. **Ads:** LevelPlay plugin integrated (banner, rewarded, interstitial), flags ON, consent from
   the in-game dialog (Europe/UK only). Meta bidding is connected for the banner, both rewarded
   units and the interstitial on Android and iOS. Device verification (test suite, one grant per
   reward) is still open. See MONETIZATION.md.
6. **IAP:** Google Play Billing (addons/GodotGooglePlayBilling) and a StoreKit 2 bridge
   (native/storekit/ios) are integrated; the 6 App Store products must be submitted with a version
   and tested in the sandbox. The shop hides real-money products when the store has none.
7. **iOS:** built and signed in the cloud (Codemagic or GitHub Actions, docs/IOS_BUILD.md); not yet
   tested on a physical iPhone or iPad.
8. **Release signing:** no upload keystore; release AAB not produced.
9. **Physical device QA** not performed (see QA_MATRIX). Emulator memory (PSS 204-223 MB, debug)
   is above the 200 MB aim; it must be re-measured with a release build on ARM hardware.
10. **Screen readers:** accessibility names are set (Godot 4.7 AccessKit properties), but
    TalkBack/VoiceOver behaviour on mobile is unverified; individual tiles are not exposed to
    screen readers.
11. **CJK fonts** rely on OS fonts. Verified on Windows (ja); unverified on Android OEM skins and iOS.
12. **Native share sheet** not implemented. "Share" copies a text card to the clipboard. A
    platform plugin is needed for the system share sheet / image cards.
13. **Haptics on iOS** use `Input.vibrate_handheld`; strength control is limited.
14. **Orientation:** portrait only on all devices, including tablets. Landscape tablet layouts are
    not implemented (the portrait 4:3 layout is verified).

## Localization

15. All 9 non-English locales are AI translations flagged `machine_translated_needs_native_review`;
    per-language reviewer notes are in the translators' reports summarised in LOCALIZATION.md and
    STORE_LISTINGS/*.md. Known review points: ko `rewind_checkpoint` is long for a button;
    fr `undo` and `cancel` are both "Annuler"; he `daily_archive_note.two` uses the dual form without
    the number; zh-TW uses 您 (formal).
16. CJK text uses the system font at regular weight; the bold UI weight applies only to Rubik
    scripts.

## Engineering

17. Rare edge: if the remaining tiles can't be cleared in any arrangement (e.g. two tiles stacked
    with nothing else), Shuffle reports it and offers rewind/restart. The pack levels and
    generated boards never start in that state, but player choices could reach it.
18. The solvability check after each pair is bounded (40k nodes / 600 ms); on very large future
    boards it may return "unknown", in which case no "stuck" banner is shown (by design).
19. Headless tools print exit-time leak warnings from autoload resources; not runtime leaks.
20. Board Studio codes must rebuild the same board forever: `StudioBoard` pins its seeds, area
    and generator settings, and `tests/test_studio_code.gd` pins 5 fingerprints. Changing a shared
    algorithm (LayoutTemplates, BoardGenerator, face order, SeededRng) needs a new code version.

## Legal / owner

21. Privacy policy, terms and support are live at mahjong.bylishi.com (`data/config/privacy_config.json`).
22. "LiShi Mahjong" trademark clearance has not been performed. The application/bundle ID
    `com.lishimahjong.app` is final (it cannot change after the first store upload).
