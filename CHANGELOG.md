# Changelog

## Unreleased

- Levels 4-50: pack shapes kept, faces re-scattered (the pack placed ~74% of tiles opposite their
  identical twin), ordered by measured difficulty (`levels-4-50-v1`). Levels 1-3 unchanged.
- Levels 51-150 replaced by generated, validated boards; trickiness and score ramp together
  from where level 50 ends (`levels-51-150-v5`).
- Content version `pack-v1(1-3)+levels-4-50-v1+levels-51-150-v5+daily-1`.
- Daily-board fingerprints pinned by a test.
- Fixed (RTL / Hebrew): the selection and hint frames were drawn one tile to the left of the
  tapped tile; match sparkles, Bloom decorations and level checkmarks were affected by the same
  cause (a control positioned before being attached gets mirrored in RTL). Regression test:
  tests/test_ui_rtl.gd.

## 0.1.0 (build 1), 2026-10-18 — first playable

- Content version `pack-v1+gen-1+daily-1`.
- Complete Mahjong Solitaire engine, 150 pack levels, tutorial, all screens, Veya Bloom, themes,
  daily puzzle and tasks, 10 locales (AI translations pending native review), accessibility
  options, crash-safe saves.
- Ads/IAP facades present and disabled; no third-party SDKs.
