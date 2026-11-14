# App Review reply: Guideline 4.3(a)/(b) and 4.2.6 (LiShi Mahjong)

Rejected submission: version 0.1.0, build 11, submitted 2026-10-21. App Store Connect app id
6824438042, bundle `com.lishimahjong.app`.

This file holds the exact text for the App Store Connect Resolution Center. The owner pastes it by
hand (the API doesn't expose the Resolution Center). Nothing in here is sent automatically.

**Before sending, check every bracketed `[…]` and every fact against the build and the account.**
Apple treats inaccurate answers as dishonesty (Guideline 2.3.1(b), 5.6), and that puts the whole
developer account at risk, not only this app.

## Status (2026-11-14)

Done:
- Build 1.0.0 (1) uploaded to TestFlight by GitHub Actions (run 43589768991), VALID, attached to version 1.0.0.
- Store page in 10 languages, 160 real screenshots (iPhone 6.9", iPad 13"), App Preview videos (en, he); the
  0.1.0 AI screenshot sets and the header/search images were removed.
- Review notes = what changed + how to test + short answers to the 9 questions (lishi-mahjong-site/submit-1.0.0.mjs).
- The 6 in-app purchases got real review screenshots of the shop (ScreenshotTour --iap-review).
- mahjong.bylishi.com redeployed (privacy and terms mention Play Together names and share codes).

Submitted 2026-11-14 12:01 UTC: version 1.0.0 (build 1) and the 6 in-app purchases are WAITING_FOR_REVIEW
(the first in-app purchases were added on the website: the API refuses them with a 409).
Optional: paste message 2 (below) in the Resolution Center; the review notes already carry the same answers.

Two messages:

1. **Message 1 (now):** answers to the 9 questions, a short note that a substantially changed
   version is in progress, and a question about which finding applies.
2. **Message 2 (with build 1.0.0):** what changed since build 11, and how to reach the new
   features. The same text goes into the App Review notes.

---

## Message 1 (send now)

```text
Hello App Review team,

Thank you for the detailed feedback. We take it seriously, and we are not resubmitting the same build. Our answers to your questions are below. We are also preparing a substantially changed version, described at the end.

1. What the app does and the problem it solves
LiShi Mahjong is a calm Mahjong tile puzzle. Players tap free tiles from a layered Mahjong board into a small tray, and identical tiles clear. Mahjong is a social game at heart, but on phones it is played alone or as an online race against strangers. The new version adds two things we could not find in any Mahjong game on the App Store: Play Together, where two people share one phone and one board and win or lose as a team (offline, no accounts), and Board Studio, where players build their own board, our solver proves it can be cleared before anyone plays it, and they share it with a short code. Every one of the 300 levels is also checked by the same solver, so no board is unwinnable.

2. Target users
Adults and families who enjoy relaxed puzzles: couples, parents and children, and grandparents and grandchildren who want something to play together on one device, plus puzzle fans who like to create and share boards. The game has 10 languages including right-to-left Hebrew, and accessibility options (Large Tiles, High Contrast, Reduce Motion, Dim Blocked Tiles), with no timers, lives or energy.

3. Market gap
Mahjong games on the App Store fall into three groups: classic solo Mahjong Solitaire, solo tile-matching with a tray, and online versus modes against other players. None of them lets two people cooperate on the same board on one device, and none lets players build a board that is proven solvable and share it as a code. Those two features are the centre of LiShi Mahjong 1.0.0.

4. Beta testing and user feedback
We ran a closed test on Google Play from October 19, 2026, with family and friends and a community testing group recruited through a testing service. Testers sent feedback through the testing service and directly to us, and we also played every test build daily on our own phones. Testers' feedback and our own sessions pointed to the same problems, and we updated the test build several times to fix them:
- Tiles were too small and not sharp enough on tall phones: boards now fill the screen and tiles are drawn larger from a sharper texture set.
- It was not always clear which tiles could be picked: we applied the standard left/right blocking rule and rebuilt the boards as real layered stacks with half-tile offsets, so a tile that looks covered is covered.
- After returning to a level, tiles already in the tray could be lost: a board now resumes exactly as it was left.
- The screen shake on long combos felt unpleasant: it was removed.
- Later levels felt repetitive: boards now grow through the journey, and 150 more levels in three new worlds were added.
Version 1.0.0 adds Play Together and Board Studio; both go to a TestFlight beta before we submit it.

5. Standalone or part of a suite
LiShi Mahjong is a standalone app. It is not part of a suite and does not link to or depend on any other app.

6. Could it be an in-app purchase or expansion of another of your apps
No. Our other apps are a shopping-list app, a recipe app, a baby-care tracker, a screenshot organizer, a fitness app, a focus companion, an SMS phishing checker, a price tracker, a temporary-photo camera, a party dilemma game, a space shooter and a garden survival game. None of them is a puzzle or tile game, so this game cannot be added to any of them.

7. Code and assets shared with your other apps
No gameplay code, levels, art, music or sound effects are shared with any of our other apps. What they share is the developer account, our publisher brand ("by LiShi") and support email, our ad-mediation publisher account (Unity LevelPlay, with separate app keys per app), and some CI build scripts. One other app of ours, Riftstrike (a space shooter), also uses the open-source Godot engine, but the two games share no project code.

8. Codebase or SDKs shared with third-party apps
The app is built with the open-source Godot 4.7 engine (MIT license). Third-party SDKs: Unity LevelPlay with ironSource and Meta Audience Network for ads, and Apple StoreKit 2 through a small bridge we wrote. No commercial template, white-label product or app-generation service was used. I wrote the game myself (about 12,000 lines of GDScript: rules, solver, level generator, UI), using AI-assisted coding tools. The art was created for this game with AI-assisted tools under my direction. Every level is generated and verified by our own tools.

9. Created for a client or partner
No. I am the developer and the owner of all of the app's content, and I submit it myself.

The changed version
We are building version 1.0.0 with Play Together and Board Studio as the core of the game, visible on the first screen. We will replace the store screenshots with real captures from the app (the previous screenshots were promotional images, and we will not use them again), correct the description so every claim matches the build, and submit the in-app purchases with that version.

Could you tell us which concern applies most: similarity of the binary (4.3(a)), similarity of the concept and design (4.3(b)), or the template concern (4.2.6)? That will help us focus the changes.

Thank you,
Liron Shiryon
```

### Facts behind each answer (owner checklist)

| # | Claim | Source |
|---|---|---|
| 1 | Layered board, 4-slot tray, identical tiles clear | `scripts/core/TrayRules.gd`, `GameSession.gd` |
| 1, 3 | No iOS Mahjong game with on-device co-op or shareable solver-checked boards | Web and App Store search, 2026-11-14. Re-check before sending. |
| 1 | 300/300 levels solver-checked | `godot --headless --path . -s res://tools/validate_content.gd` |
| 2 | 10 languages, accessibility options, no timers/lives/energy | `LocalizationService.gd`, Settings screen |
| 4 | Closed test from 2026-10-19 | Play Console → Testing → Closed testing (no tester count is claimed). |
| 4 | Feedback examples | Owner confirmed (2026-11-14) that testers sent feedback. Each fix is real and recorded in CHANGELOG.md: bigger/sharper tiles and screen-filling boards (0.1.3), stacked tiles drawn correctly + exact tray resume (0.1.4), left/right rule + no combo shake (0.1.6), 150 more levels in 3 worlds (0.1.7), boards grow with the journey (0.1.9), real layered boards (0.1.10). No tester is quoted and no count is given. **Owner: open the TestFlight beta before sending (the answer says it happens).** |
| 6 | Other apps' categories | App Store Connect, read 2026-11-14:<br>• ריח של בית: Food & Drink<br>• חסרלי: Lifestyle<br>• Keepsi: Productivity<br>• אריאה: Lifestyle/Health<br>• Catchi: Games, party dilemmas<br>• PusherZ: Health & Fitness<br>• Riftstrike: Games, space survivor<br>• שולי: Productivity<br>• ORIGO: Utilities<br>• PEND: Lifestyle<br>• PoofCam: Photo & Video<br>• Garden Guardians: Games, survival |
| 7 | No shared game code with Riftstrike | File hash comparison: the only identical file is `.github/scripts/setup-codemagic-cli.sh` |
| 8 | ~12,000 lines of GDScript | `find scripts -name "*.gd" \| xargs cat \| wc -l` → 12,258 (2026-11-14) |
| 8 | Art origin | `VeyaMahjong_AssetPack_v1/LICENSE_AND_ORIGINS.md`, `docs/BRANDING.md`. **Confirm commercial rights for the v2 and worlds packs and `match_pop.wav` (`docs/RELEASE_CHECKLIST.md` Gate 1).** |

**Do not send message 1 until rows 4 and 8 are confirmed.**

---

## Message 2 (with build 1.0.0, also used as the App Review notes)

Fill in once 1.0.0 is on TestFlight and the button labels are final.

```text
Hello App Review team,

We have submitted LiShi Mahjong 1.0.0 (build [B]) with substantial changes since build 11:

- Play Together (new): two players share one phone and one board, take turns placing tiles into a shared tray, and win or lose together. A pair finished on a partner's tile counts as a Team-up. It works offline and needs no accounts.
- Board Studio (new): build a board from 10 shapes, choose its size and layers, and our solver proves it can be cleared before you play. Every board gets a short code (for example LS-5VSW-11BK) that a friend can enter to play the same board. Codes contain only board settings, never personal data or user text.
- Store page: all screenshots are now real captures from this build, with a short caption. The description was rewritten so every claim matches the app.
- In-app purchases: the 6 products are submitted with this version.
- Polish: [list].

How to see the new features in under 30 seconds:
1. Launch and tap Skip on the tutorial.
2. Home → Play Together → Start. After each pick, the turn passes to the other player.
3. Home → Board Studio → Enter code → type LS-5VSW-11BK → Play. Or Create → Check & Play → the board's code appears.

No account is needed. Everything works offline except ads.

Ads: Unity LevelPlay with Meta Audience Network and ironSource. Banner at the bottom, optional rewarded videos, full-screen ads only after a win from level 6, and never in Play Together or Board Studio. In the EEA, UK and Switzerland a consent dialog appears first. On iOS, App Tracking Transparency follows it.

In-app purchases: coin packs (3), Remove Ads, Tile Themes and a Starter Bundle. Every level can be finished without paying.

Support: support@bylishi.com
Privacy: https://mahjong.bylishi.com/privacy/

Thank you,
Liron Shiryon
```
