# Localization

## Launch locales

| # | Code (file) | Godot locale | Native name | Direction | Status |
|---|---|---|---|---|---|
| 1 | `en` | en | English | LTR | Source |
| 2 | `ja` | ja | 日本語 | LTR | AI translation, **needs native review** |
| 3 | `ko` | ko | 한국어 | LTR | AI translation, **needs native review** |
| 4 | `de` | de | Deutsch | LTR | AI translation, **needs native review** |
| 5 | `fr` | fr | Français | LTR | AI translation, **needs native review** |
| 6 | `es` | es | Español (neutral) | LTR | AI translation, **needs native review** |
| 7 | `pt-BR` | pt_BR | Português (Brasil) | LTR | AI translation, **needs native review** |
| 8 | `zh-Hant-TW` | zh_TW | 繁體中文 | LTR | AI translation, **needs native review** |
| 9 | `he` | he | עברית | **RTL** | AI-completed from the pack's 59 strings, **needs native review** |
| 10 | `ru` | ru | Русский | LTR | AI translation, **needs native review** |

Each file has `review_status: "machine_translated_needs_native_review"`. None of the translations
has been certified by a human editor. Each has 302 keys covering every screen, dialog, tutorial
step, accessibility label, Bloom discovery name and story, daily task, shop/purchase message,
privacy/consent entry, error, setting, and the calendar/date format.

Changes to the pack's Hebrew (documented by the translator): `undo` → "ביטול מהלך" (it clashed
with `cancel`), `tile_collections` → plural, `daily_puzzle` → "הפאזל היומי" (to tell it apart
from daily challenges), `bloom_subtitle` aligned to the English source.

## Engineering

- **Format:** `data/localization/<code>.json` with `{locale, rtl, native_name, review_status, strings}`.
  A value can be a plural object such as `{"one": "...", "other": "..."}`.
- **Named placeholders** `{level}`, `{count}`, … may be reordered freely by translators. Integer
  values are formatted with the locale's grouping (`1.234` de, `1 234` fr/ru, Spanish
  leaves 4-digit numbers ungrouped).
- **Plurals** (`LocalizationService.plural_category`): en/de/es one|other; fr/pt-BR treat 0 and 1
  as "one"; he one|two|other; ru one|few|many; ja/ko/zh other.
- **Dates:** each locale has a `date_long` pattern and month names (Russian genitive
  "18 октября 2026 г.", nominative `month_title_N` for "Октябрь 2026"), `week_start`
  (Sunday: en, ja, ko, zh, he, pt-BR; Monday: de, fr, es, ru) and weekday abbreviations. Puzzle
  dates are always local calendar dates.
- **Prices** are never formatted by the game; the store's localized price string is shown as is.
- **First launch** uses the device language (`OS.get_locale()`), mapped as follows: `iw`→he;
  `zh_TW/zh_HK/zh_MO/*Hant*`→zh-Hant-TW; Simplified Chinese → **English** (Simplified is never
  substituted); any `pt_*` → pt-BR (we never ship European Portuguese as Brazilian, but pt-BR is the
  closest choice for pt-PT users). Unsupported languages fall back to English.
- **Settings → Language:** "Automatic (device)" plus the 10 languages in their native names. The
  change applies instantly, because every screen rebuilds on `locale_changed`, and persists.
- Strings are also registered with `TranslationServer`, so Godot's TextServer shapes and line-breaks
  with the right language. `internationalization/locale/include_text_server_data=true` ships ICU
  break data (needed for CJK line breaking in exports).
- No text is baked into images; every label is a live Godot control. Bottom-nav labels shrink to
  fit (down to 12 px) instead of truncating.

## Fonts

| Script | Font | Licence | Shipped? |
|---|---|---|---|
| Latin, Cyrillic, Hebrew | Rubik variable (wght 300-900) | SIL OFL 1.1 (`assets/fonts/Rubik-OFL.txt`) | Yes, 352 KB |
| Japanese / Korean / Traditional Chinese | OS system fonts through `SystemFont` (ordered per active language: JP / KR / TC families first) plus Godot's automatic system fallback | OS-provided | No |

Rationale: bundling Noto CJK (JP + KR + TC) would add roughly 25-60 MB to every download. Android
ships Noto CJK in `/system/fonts` and iOS ships Hiragino / PingFang / Apple SD Gothic. The
fallback list is reordered on language change so Han characters get the regional glyph forms
(e.g. Japanese vs Traditional Chinese 直/骨).

**Verified:** Japanese renders through system fallback on Windows (screenshot
`docs/screenshots/ja/`), and the Android 16 emulator rendered the game's Latin UI and tile art.
**Not yet verified:** CJK and Hebrew rendering on physical Android/iOS devices across OEM font
configurations (QA_MATRIX items L-5..L-8). If an OEM lacks a CJK font, the fallback is to bundle a
subsetted Noto Sans CJK for that language only.

## RTL (Hebrew)

- Every screen root gets `LAYOUT_DIRECTION_RTL`, so containers mirror, labels align to the start,
  progress bars fill right to left, the calendar runs Sunday on the right, and month and back
  arrows are flipped.
- `CheckButton`, `OptionButton` and button styles define their `*_mirrored` theme items, so RTL
  controls keep the same look.
- **Never mirrored:** the Mahjong board (`BoardView` forces LTR), tile symbols, Bloom artwork
  (the stage forces LTR) and tile previews in Collections.
- Mixed content (the Latin "Veya Mahjong" brand, numbers, `{count}` values) is shaped by Godot's
  BiDi (TextServerAdvanced/ICU). The Hebrew translator avoided a leading "+1" in `light_earned`
  so it can't be visually reordered.

## QA

- `tests/test_localization.gd` checks that all 10 files exist and parse, have exactly the English
  key set, keep the same placeholders per string (all plural categories), include the plural
  categories each language needs, leave no English untranslated (strings over 10 characters),
  and have date patterns. It also checks the rules for plurals, OS-locale mapping and group
  separators.
- Visual QA screenshots: `docs/screenshots/{en,ja,de,he,ru}/` (desktop renderer, 540×960). German
  and Russian layouts were checked for text expansion; Hebrew for RTL.

## Adding a language (Arabic is the recommended next one)

1. Copy `en.json` to `ar.json`, set `"rtl": true`, translate all keys, and add plural categories
   (ar: zero|one|two|few|many|other). Extend `plural_category()` accordingly.
2. Add `"ar": "ar"` to `LocalizationService.LOCALES`, to `ORDER`, and to `map_os_locale()`.
3. Add the code to `tests/test_localization.gd` (`CODES`, `PLURALS`).
4. Choose a font with Arabic coverage (e.g. Noto Sans Arabic, OFL) as an added fallback. Rubik
   has no Arabic. RTL mirroring already works.
5. Run the tests and a screenshot tour with `--locale=ar`.
