# LiShi Mahjong – Store listing drafts

**Status: AI-drafted. Not reviewed. Not submitted anywhere.**

Every file in this folder is a first draft written by an AI assistant. Before anything is pasted into Google Play Console or App Store Connect:

1. **A native speaker must review each language.** Each locale file ends with a "Notes for native reviewer" section listing the phrases the draft is least sure about. Machine-drafted text can be grammatical and still sound unnatural, use the wrong register, or pick a search term that nobody uses.
2. **The owner must check every claim against the build being shipped.** The drafts only describe features confirmed as implemented when they were written (October 2026). If the game changes, the listings must change too.

## Files

| File | Language | Suggested Google Play locale | Suggested Apple locale |
|---|---|---|---|
| `en.md` | English (source text) | en-US (optionally en-GB, en-AU, en-CA) | English (U.S.) (optionally U.K., Australia, Canada) |
| `ja.md` | Japanese | ja-JP | Japanese |
| `ko.md` | Korean | ko-KR | Korean |
| `de.md` | German | de-DE | German |
| `fr.md` | French (France) | fr-FR (fr-CA needs its own review) | French (French (Canada) needs its own review) |
| `es.md` | Spanish (neutral, "tú") | es-ES and/or es-419, review for each | Spanish (Spain) and/or Spanish (Mexico), review for each |
| `pt-BR.md` | Brazilian Portuguese | pt-BR | Portuguese (Brazil) |
| `zh-Hant-TW.md` | Traditional Chinese (Taiwan) | zh-TW | Chinese (Traditional) – zh-Hant |
| `he.md` | Hebrew (RTL) | iw-IL | Hebrew – he |
| `ru.md` | Russian | ru-RU | Russian |

Each locale file contains:

- **Google Play:** App name (max 30), Short description (max 80), Full description (max 4000)
- **Apple App Store:** Name (max 30), Subtitle (max 30), Promotional text (max 170), Description (max 4000), Keywords (max 100 bytes)
- **Notes for native reviewer** (in English)

The text inside each ```` ```text ```` block is the exact text to paste. Headings, notes and code fences are not part of the store text. The Apple description is the same as the Google Play full description in every language. Edit them separately if one store needs something different.

## Locale availability differs per platform

Google Play and Apple support different locales, use different codes, and split some languages differently. Check the current lists in each console before you upload. For example:

- **Google Play** has separate listings for **es-419** (Latin America) and **es-ES** (Spain), **fr-CA** and **fr-FR**, **en-US / en-GB / en-AU / en-CA**, and **pt-BR / pt-PT**. Hebrew uses the legacy code **iw-IL**, and Traditional Chinese is **zh-TW**.
- **Apple App Store Connect** uses **zh-Hant** (Chinese, Traditional), **he** (Hebrew), **pt-BR** (Portuguese, Brazil), and separate Spanish (Spain / Mexico), French (France / Canada) and English variants.
- Do not copy a listing to a sibling locale (for example fr-FR to fr-CA, or es to both es-ES and es-419) without checking that the wording suits that market.
- Russian: check whether the app will actually be distributed and payable in the target countries before you spend review effort on that locale.

## Screenshots and other graphics

- **Screenshots must be captured from the real running game** (a release-candidate build on real devices or simulators), with the UI in the matching language. **Do not use concept art, asset-pack mock-ups or edited composites** as store screenshots. Both stores require screenshots that show the actual app experience.
- Only show features that exist in the submitted build. Do not show shop screens, prices, or ad prompts while the shop is not live.
- For Hebrew, capture screenshots with the RTL layout as it really appears in the game.

## What the drafts claim, and what they deliberately do not

**Claimed (verified as implemented):** traditional Mahjong Solitaire rules (match pairs of identical free tiles; every tile, including Flowers and Seasons, matches only an identical tile); 150 handcrafted levels in 3 illustrated worlds (Aurora Garden, Pearl Coast, Crystal Nocturne); a free Daily Puzzle every day, playable offline, with the last 30 days still playable and no streaks; optional daily tasks; LiShi Bloom (a LiShi Light for each new level solved, a decoration or discovery every 5 Lights, 30 discoveries); 4 tile themes unlocked through play; Hint, unlimited Undo and Shuffle always free; when stuck, a free Shuffle of the remaining tiles or a free rewind to the last solvable point; no timers, lives or energy; fully playable offline, no account needed; Large Tiles, High Contrast, Reduce Motion, Dim Blocked Tiles, adjustable sound, vibration can be turned off; 10 languages; an interactive tutorial.

**Not claimed, on purpose:** that any Flower matches any Flower or any Season any Season (no longer true: every tile matches only an identical tile); level counts beyond 150; awards, rankings or superlatives; cloud save; multiplayer; anything about ads (no "no ads" or "ad-free" claim, because ads may be added later); "Shuffle always solvable" (it is not true in rare stacked end-states); prices, "free to play" business-model wording, or any specific in-app purchase (the shop is not live); health or cognitive benefits; child-directed positioning; competitor names.

**Re-check before each release:**

- If ads or in-app purchases are added, update the descriptions where needed. Also update Google Play's Data safety form, Apple's privacy labels, and the "Contains ads" / "In-app purchases" flags. Those forms are separate from these drafts.
- Shuffle claim (RESOLVED): earlier drafts said "Shuffle always gives you a solvable layout", which is false in rare stacked end-states. All 10 locales now say instead: "Stuck? Shuffle the remaining tiles for free, or go back to your last solvable point", with each language using its in-game "rewind" term. If the rewind or restart behaviour changes, update this bullet.
- Matching rule: every tile, including Flowers and Seasons, matches only an identical tile. The drafts no longer mention Flower/Season matching. The in-game tutorial (`tut_step_bonus`, all 10 languages) already teaches the identical-tiles rule.
- "Free Daily Puzzle" describes a feature, not the app's price. Since 2026-10-19 helpers are boosters: the listings say "Earn coins as you play - use Hint, Undo and Shuffle whenever you need them" and "Stuck? One free Shuffle when no moves are left, and going back to the last solvable point is always free". Keep both true if the economy changes.

## Terminology

In-game terms come from the shipped localisation files in `data/localization/*.json`: tagline, Daily Puzzle, daily tasks/challenges, Hint/Undo/Shuffle, accessibility option names, theme names, world names, and the LiShi Light term (LiShiの光, LiShi의 빛, LiShi之光, LiShi-Licht, Lumière LiShi, Luz de LiShi, אור LiShi, огонёк LiShi). The brand **LiShi Mahjong** and the feature name **LiShi Bloom** stay in Latin letters in every language. If the in-game text changes, update the listings to match.

**Rename (October 2026):** the game was renamed to **LiShi Mahjong**. The feature names are now **LiShi Bloom** and **LiShi Light(s)**. In Japanese, Korean and Traditional Chinese the Light term now uses the Latin brand (LiShiの光, LiShi의 빛, LiShi之光). The in-game translations (`data/localization/*.json`) use the same names, so game and listings match.

## Character counts

The counts in parentheses after each field heading were computed with a Node.js script, not by eye:

- Every field except Apple keywords: Unicode characters (code points) of the text inside the code block.
- Apple keywords: **UTF-8 bytes**. CJK characters take 3 bytes and Hebrew and Cyrillic letters take 2, so those keyword fields hold far fewer words.

The counts are only valid for the current text. **Recount after any edit.** For example:

```sh
node -e "const s=require('fs').readFileSync(0,'utf8').replace(/\r?\n$/,'');console.log([...s].length+' chars, '+Buffer.byteLength(s)+' bytes')" < field.txt
```

Store consoles may count slightly differently (for example, line breaks in long descriptions). Treat the console's own counter as the final authority.

CJK descriptions (Japanese, Korean, Chinese) are much shorter in characters than the European ones while saying the same thing. That is expected.

Apple keyword rules followed: comma-separated, no spaces after commas, no duplicates, and no repeats of the words "LiShi" or "Mahjong" from the app name. Native-script spellings of the genre (マージャン, 마장, маджонг, מהג'ונג) were kept as separate search terms. Reviewers may swap keywords freely, but must stay within 100 bytes.
