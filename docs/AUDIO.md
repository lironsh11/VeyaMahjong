# Audio

All sound effects and music are **original**. They are synthesized by
`tools/audio/make_audio.mjs` (DSP in `tools/audio/dsp.mjs`) with no samples and no third-party
material. The generator is seeded, so re-running it reproduces identical files. The asset pack's
original 13 WAV effects and three 24-second loops are no longer shipped; the pack folder itself
is unchanged.

```bash
node tools/audio/make_audio.mjs
```
```bash
node tools/audio/serve.mjs
```
The second command serves a listening page at `http://localhost:8765/tools/audio/preview.html`
with every effect and track, a match-streak demo and a click-variation demo. The generator
needs `ffmpeg` with libvorbis on PATH for loudness measurement and OGG encoding.

## Design decisions (and the research behind them)

A research pass on relaxing casual puzzle audio (sources in the commit history / session notes;
summary below) shaped these choices:

| Topic | Guidance found | What the game does |
|---|---|---|
| Harsh band | The ear is most sensitive around 2–5 kHz; avoid peaks there; keep the body of sounds around 300 Hz–2 kHz | Clacks are tuned to 300–2150 Hz modes and low-passed at 3.2 kHz; reverb tails are darkened at 5.2 kHz. Measured 2.5–4.5 kHz energy: effects −18 to −62 dB relative to total, music −28 to −38 dB |
| Repetition fatigue | Round-robin samples, small random pitch/volume spread, never the same sample twice; don't detune tonal sounds | tap ×4, select ×4, button ×3 variants; ±40 cents and ±1.5 dB on those only; never the same variant twice (tested) |
| Consonance | Tune tonal effects to the music's key; pentatonic sets fit any chord | Every tonal effect uses D-major pentatonic (D E F# A B). The worlds are in D major/B minor, G major/E minor (sharing D E A B) and B minor/D major |
| Streak rewards | Step up the scale (Peggle), cap or wrap at about an octave | `AudioService.play_match(combo)` climbs D E F# A B D (0, 2, 4, 7, 9, 12 semitones), then stays at the octave (tested) |
| Negative feedback | Not a buzzer: short, soft, low-mid, falling, in key, quieter than success | `invalid` is a muted two-note A3→F#3 wood figure, about 12 dB quieter than a match |
| Select vs match | Select: dry tap without tonal ring. Match: clack plus one tuned soft mallet note and a short airy tail | Exactly that; the match is the most prominent recurring sound |
| Win jingle | About 2–4 s (level), longer for milestones; duck the music under it | `victory` 2.5 s of notes (3.6 s with tail), `world_unlock` about 4.5 s; music ducks 9 dB (5 dB for `reward`) |
| Loudness | Mobile target about −18 LUFS integrated, true peak ≤ −1 dBTP; music sits as a bed under the effects | Music normalized to **−20 LUFS**, true peak ≤ −5.9 dBTP. The match effect is about 6 dB above the music, about 9 dB with the default 70% music volume |
| Music length | Short loops cause fatigue; prefer several 2–4 min pieces, never the same twice in a row, with silence between | **Two pieces per world (2:24–3:06)**. Each plays once, then 12–28 s of silence, then the other piece |
| Phone speakers | Little useful content below about 100 Hz | Bass voiced at 82–147 Hz with harmonics; high-pass at 70 Hz |
| Older players | High-frequency hearing loss; strong fundamentals in the mid range; always a visual cue too; separate volume controls | All cues have mid-range fundamentals; every sound duplicates on-screen feedback; Music / Effects volumes and mutes already exist in Settings |

## Effects

| Event (file) | Sound | Length (s) | Event loudness* (LUFS) | True peak (dBTP) | 2.5–4.5 kHz share (dB) |
|---|---|---|---|---|---|
| match (`match_select.wav`) | **The owner's asset-pack select sound** (VeyaMahjong_AssetPack_v1/audio/sfx/select.wav, copied unchanged; owner request 2026-10-20, replacing the pack's match.wav, which stays as `match_pack.wav`). Every match sounds the same (no pitch climb on streaks, owner request 2026-10-20). The synthesized `match.wav` is kept but unused | — | — | — | — |
| select_1..4 | Fuller dry clack, no tone | 0.14 | −28.7 to −29.8 | −8.0 | −26 |
| tap_1..4 | Light clack | 0.12 | −32.4 to −33.8 | −11 | −24 to −26 |
| button_1..3 | Soft UI tock | 0.10 | −34.2 to −35.0 | −12 | −32 to −35 |
| invalid | Muted wood A3 → F#3 | 0.38 | −26.1 | −13.0 | −61.6 |
| undo | Soft breath + kalimba E5 → B4 | 0.70 | −19.7 | −14.0 | −35.2 |
| hint | Bells A5, B5, E6 | 1.20 | −18.4 | −12.0 | −21.1 |
| shuffle | 11 panned tile clacks + swish + marimba D5 | 1.10 | −20.1 | −9.0 | −27.0 |
| reward | Harp D5 F#5 A5 D6 | 2.20 | −14.8 | −8.0 | −19.6 |
| victory | Kalimba A5 B5 D6 E6 → D major bells + pad | 3.60 | −14.1 | −6.0 | −26.4 |
| world_unlock | Two-octave harp glissando + pad swell + bells | 5.68 | −14.6 | −6.0 | −24.7 |
| soft_pop | Water droplet (Bloom decorations) | 0.21 | −26.6 | −10.0 | −34.5 |
| burst | Not played since 2026-10-19 (the owner preferred the pack match sound alone); kept mapped for a possible later use | 0.90 | −16.2 | −10.9 | −17.8 |
| tray_alert | One tray slot left: soft marimba E4 → D4 | 0.60 | −24.8 | −16.0 | −40.3 |
| fail | Tray full: kalimba B4 A4 F#4 D4 over a muted low thud | 1.40 | −19.1 | −12.0 | −40.2 |
| coin | Two-note chime (not used by the game yet) | 1.00 | −15.3 | −11.0 | −18.5 |

\*Max momentary loudness measured with 0.5 s of silence around the effect. Effects shorter than
the 400 ms window read about 5–6 dB lower than they sound.

## Music

| Piece | Instruments / key | BPM | Length (s) | Integrated (LUFS) | True peak (dBTP) | Size (KB) |
|---|---|---|---|---|---|---|
| aurora_garden_a | Kalimba lead, harp arpeggios, bells, pad; D major | 72 | 150 | −20 | −6.8 | 927 |
| aurora_garden_b | Harp lead, kalimba, bells; B minor | 66 | 163 | −20 | −6.6 | 1,088 |
| pearl_coast_a | Marimba lead, harp, ocean wash; G major | 78 | 144 | −20 | −7.7 | 1,783 |
| pearl_coast_b | Harp lead, marimba, ocean wash; E minor | 70 | 160 | −20 | −7.6 | 1,986 |
| crystal_nocturne_a | Glass bells, kalimba, deep reverb; B minor | 62 | 174 | −20 | −6.8 | 1,084 |
| crystal_nocturne_b | Kalimba lead, glass, slow; D major | 58 | 186 | −20 | −7.3 | 1,097 |

Structure of each piece (2-bar segments): intro (pad + bells) → A (sparse melody) → B (fuller,
with arpeggios) → A′ (motif repeats with variation) → breathing break → B′ → outro on the tonic
chord with a natural decay. Melodies are generated from pentatonic step-wise motifs that land on
chord tones, are kept sparse on purpose (no hooky tune to tire of), and are lightly humanised
(±10 ms, small velocity variation).

Total music is 7.8 MB of OGG Vorbis (q3), versus 0.3 MB before; effects are 3.1 MB of WAV
source, which Godot imports as QOA-compressed.

## Verified / not verified

- **Verified:** all files load in Godot and have the expected lengths (`tests/test_audio.gd`);
  streak pitches stay on the scale and variants never repeat (tests); loudness, peaks and
  harsh-band energy measured with ffmpeg (tables above); spectrograms inspected; the listening
  page plays every file.
- **Not verified:** how it actually *sounds*. The sounds were designed and measured, not
  listened to by the author. The owner should listen on the preview page and on a phone speaker
  and headphones; every parameter can be tuned in `make_audio.mjs` and regenerated in seconds.
- iOS silent switch: Apple's guidance is to mute non-essential effects in silent mode. Godot's
  default iOS audio session behaviour should be checked on a device.
