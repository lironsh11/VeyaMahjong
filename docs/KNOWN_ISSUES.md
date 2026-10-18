# Known issues and blocked dependencies

## Product / content

1. **Resolved: level pacing and mirrored tiles.** Levels 4-50 keep the pack shapes but have
   re-scattered faces (the pack placed ~74% of tiles opposite their twin), and 51-150 are generated.
   All are validated and ordered by measured difficulty (see MAHJONG_RULES_AND_SOLVER.md).
   Remaining caveat: the metrics are heuristics based on random play. Playtesting should confirm
   that levels ~130-150 feel fair; both build tools can be retuned and rerun deterministically.
   Any rebuild after release must bump the tool's `BUILD_ID`, because in-progress saves on
   changed boards are discarded (completions are kept).
2. Difficulty bands are stored per level but not displayed.
3. Bloom: 26 unique sprites fill 30 discovery slots, so 4 sprites (pond, rocks, butterfly, grass
   patch) appear in two worlds. Positions were tuned on 16:9-20:9 screens only.
4. Only the `match_sparkle` and `gold_twinkle` effects are used; `petal_pop`/`ripple` are reserved.

## Platform / integrations

5. **Ads:** no SDK integrated; flags OFF. **BLOCKED** on choosing and installing a plugin plus
   AdMob account and ad unit IDs. See MONETIZATION.md.
6. **IAP:** Google Play adapter written but not installed or device-tested; no iOS adapter.
   Product IDs are empty. **BLOCKED** on the plugin plus Play Console/App Store Connect setup.
7. **iOS:** no build or signing possible here (needs macOS, Xcode 26+, Team ID).
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
20. The git repository is initialised but nothing has been committed.

## Legal / owner

21. Privacy policy, terms, support URL/email and deletion URL are empty (`data/config/privacy_config.json`).
22. "Veya Mahjong" trademark clearance has not been performed. The application/bundle ID
    `com.veyamahjong.app` is a placeholder.
