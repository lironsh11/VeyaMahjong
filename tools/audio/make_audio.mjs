// Generates every sound effect and all world music for LiShi Mahjong.
//   node tools/audio/make_audio.mjs
// Deterministic (seeded): re-running reproduces identical audio. Needs ffmpeg (libvorbis) on PATH
// for loudness measurement and OGG encoding. Design notes: docs/AUDIO.md.
//
// Sonic identity: every tonal sound uses D major pentatonic (D E F# A B), which is also B minor
// pentatonic, so effects stay consonant over all three worlds' music:
//   Aurora Garden = D major / B minor, Pearl Coast = G major / E minor (shares D E A B),
//   Crystal Nocturne = B minor / D major.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  SR, Track, rng, hz, midi, partials, kalimba, harp, marimba, bell, glass, padNote, bass,
  noise, lowpass, highpass, bandpass, scale, envelope, reverb, normalizePeak, edgeFades,
  dcBlock, trimTail, wavBuffer, gain,
} from './dsp.mjs';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..', '..');
const AUDIO = path.join(ROOT, 'assets', 'veya', 'audio');
const WORK = path.join(ROOT, 'tools', 'audio', 'out');
fs.mkdirSync(path.join(AUDIO, 'sfx'), { recursive: true });
fs.mkdirSync(path.join(AUDIO, 'music'), { recursive: true });
fs.mkdirSync(WORK, { recursive: true });

const MUSIC_LUFS = -20;     // background bed (research: mobile target ~-18 LUFS; music sits below SFX)
const TRUE_PEAK_MAX = -1.5; // dBTP

// ---------------------------------------------------------------------------------
// Sound effects
// ---------------------------------------------------------------------------------

/** Dry porcelain/wood tile clack: energy at 300 Hz-2.2 kHz, nothing harsh above ~3 kHz. */
function clack(seed, bright = 1, len = 0.09) {
  const r = rng(seed);
  const n = Math.ceil(len * SR);
  const out = new Float32Array(n);
  // excitation: very short noise burst
  const ex = noise(0.004, seed);
  envelope(ex, (t) => Math.exp(-t / 0.0009));
  const exb = bandpass(ex, 1500 * bright, 0.9);
  for (let i = 0; i < exb.length && i < n; i++) out[i] += exb[i] * 1.2;
  // body modes
  const modes = [
    { f: 300, a: 0.45, d: 0.022 },
    { f: 820, a: 1.0, d: 0.015 },
    { f: 1430, a: 0.55, d: 0.010 },
    { f: 2150, a: 0.22, d: 0.006 },
  ];
  for (const m of modes) {
    const v = partials(m.f * bright * (0.985 + r() * 0.03), len, [{ ratio: 1, amp: m.a, decay: m.d }], { attack: 0.0004, release: 0.005, phaseSeed: seed + m.f });
    for (let i = 0; i < n; i++) out[i] += v[i] * 0.5;
  }
  return highpass(lowpass(out, 3200), 140);
}

function sfxTrack(seconds, stereo = true) { return new Track(seconds, stereo ? 2 : 1); }

function finish(t, peakDb, { verb = null } = {}) {
  if (verb) reverb(t, verb);
  dcBlock(t);
  trimTail(t);
  normalizePeak(t, peakDb);
  edgeFades(t, 0.0015, 0.02);
  return t;
}

const NOTE = (n) => hz(n);

const SFX = {};

// tap: lightest touch (deselect, generic). 4 round-robin variants.
for (let v = 1; v <= 4; v++) {
  SFX[`tap_${v}`] = () => {
    const t = sfxTrack(0.12, false);
    t.add(clack(100 + v, 1.08 + (v - 2.5) * 0.03, 0.08), 0, 1);
    return finish(t, -11);
  };
}

// select: lifting a tile, a fuller clack (two micro-impacts), no tonal ring. 4 variants.
for (let v = 1; v <= 4; v++) {
  SFX[`select_${v}`] = () => {
    const t = sfxTrack(0.14, false);
    t.add(clack(200 + v, 0.96 + (v - 2.5) * 0.025, 0.1), 0, 1);
    t.add(clack(210 + v, 1.12, 0.06), 0.011, 0.35);
    return finish(t, -8);
  };
}

// button: soft UI tock, 3 variants.
for (let v = 1; v <= 3; v++) {
  SFX[`button_${v}`] = () => {
    const t = sfxTrack(0.1, false);
    t.add(clack(300 + v, 0.78 + (v - 2) * 0.03, 0.07), 0, 1);
    t.add(partials(NOTE('A4') * (1 + (v - 2) * 0.002), 0.09, [{ ratio: 1, amp: 0.25, decay: 0.025 }], { attack: 0.002 }), 0, 1);
    return finish(t, -12);
  };
}

// match: two tiles meet (clack) + tuned soft mallet note D5 (+octave shimmer) + short airy tail.
// Combo streaks raise this sample in pentatonic steps at runtime (AudioService).
SFX.match = () => {
  const t = sfxTrack(1.1);
  t.add(clack(400, 1.0, 0.09), 0, 0.55, -0.15);
  t.add(clack(401, 1.06, 0.07), 0.013, 0.4, 0.15);
  const f = NOTE('D5');
  const tone = partials(f, 1.0, [
    { ratio: 1, amp: 1, decay: 0.42 },
    { ratio: 2, amp: 0.22, decay: 0.30 },
    { ratio: 4, amp: 0.06, decay: 0.08 },   // soft-mallet bite
    { ratio: 3, amp: 0.05, decay: 0.12 },
  ], { attack: 0.005, release: 0.08 });
  t.add(tone, 0.008, 0.8);
  const air = lowpass(highpass(noise(0.3, 401), 900), 2600);
  envelope(air, (x) => Math.sin(Math.PI * Math.min(1, x / 0.28)) * Math.exp(-x / 0.12));
  t.add(air, 0.02, 0.05, 0.2);
  return finish(t, -7, { verb: { wet: 0.16, size: 0.55, damp: 0.5 } });
};

// invalid: gentle falling two-note muted wood (A3 -> F#3), in key, quieter than a match.
SFX.invalid = () => {
  const t = sfxTrack(0.4, false);
  const mute = (f) => partials(f, 0.25, [
    { ratio: 1, amp: 1, decay: 0.06 },
    { ratio: 2.9, amp: 0.2, decay: 0.015 },
  ], { attack: 0.003, release: 0.03 });
  t.add(mute(NOTE('A3')), 0, 0.9);
  t.add(mute(NOTE('F#3')), 0.085, 0.75);
  t.add(clack(500, 0.7, 0.05), 0, 0.2);
  return finish(t, -13);
};

// undo: soft backward breath + descending kalimba E5 -> B4.
SFX.undo = () => {
  const t = sfxTrack(0.7);
  const sw = lowpass(highpass(noise(0.32, 600), 500), 1800);
  envelope(sw, (x) => Math.pow(Math.sin(Math.PI * Math.min(1, x / 0.32)), 2));
  t.add(sw, 0, 0.12, -0.3);
  t.add(kalimba(NOTE('E5'), 0.7, 0.6), 0.04, 0.55, 0.1);
  t.add(kalimba(NOTE('B4'), 0.7, 0.6), 0.13, 0.55, -0.1);
  return finish(t, -14, { verb: { wet: 0.14, size: 0.5, damp: 0.5 } });
};

// hint: quiet three-note twinkle (A5, B5, E6), soft bells.
SFX.hint = () => {
  const t = sfxTrack(1.2);
  ['A5', 'B5', 'E6'].forEach((n, i) => t.add(bell(NOTE(n), 0.8 - i * 0.12, 1.0), i * 0.075, 0.5, -0.3 + i * 0.3));
  return finish(lowpassTrack(t, 5500), -12, { verb: { wet: 0.22, size: 0.6, damp: 0.55 } });
};

// shuffle: tiles rattling (10 quick clacks, panned) + low swish, ending on a soft D5.
SFX.shuffle = () => {
  const t = sfxTrack(1.1);
  const r = rng(700);
  for (let k = 0; k < 11; k++) {
    const at = 0.02 + k * 0.038 + r() * 0.015;
    t.add(clack(700 + k, 0.85 + r() * 0.3, 0.06), at, 0.35 + r() * 0.25, r() * 1.4 - 0.7);
  }
  const sw = lowpass(highpass(noise(0.5, 701), 250), 1400);
  envelope(sw, (x) => Math.sin(Math.PI * Math.min(1, x / 0.5)));
  t.add(sw, 0.0, 0.08);
  t.add(marimba(NOTE('D5'), 0.6, 0.8), 0.47, 0.4);
  return finish(t, -9, { verb: { wet: 0.12, size: 0.45, damp: 0.5 } });
};

// coin (currently unused by the game): two-note chime B5 -> E6.
SFX.coin = () => {
  const t = sfxTrack(1.0);
  t.add(bell(NOTE('B5'), 0.8, 0.8), 0, 0.5, -0.2);
  t.add(bell(NOTE('E6'), 0.8, 0.8), 0.09, 0.5, 0.2);
  return finish(lowpassTrack(t, 6000), -11, { verb: { wet: 0.15, size: 0.5, damp: 0.5 } });
};

// reward (a Light earned): warm harp arpeggio D5 F#5 A5 D6.
SFX.reward = () => {
  const t = sfxTrack(2.2);
  ['D5', 'F#5', 'A5', 'D6'].forEach((n, i) => t.add(harp(NOTE(n), 0.85, 1.8), i * 0.085, 0.6, -0.35 + i * 0.23));
  t.add(padNote(NOTE('D4'), 0.4, { attack: 0.15, release: 1.0 }), 0.05, 0.12);
  return finish(t, -8, { verb: { wet: 0.25, size: 0.7, damp: 0.45 } });
};

// victory (level complete, ~2.5 s): kalimba phrase A5 B5 D6 -> resolved D major bell chord + pad.
SFX.victory = () => {
  const t = sfxTrack(3.6);
  const phrase = [['A5', 0], ['B5', 0.14], ['D6', 0.28], ['E6', 0.42]];
  phrase.forEach(([n, at], i) => t.add(kalimba(NOTE(n), 0.85, 1.6), at, 0.55, -0.3 + i * 0.2));
  ['D5', 'F#5', 'A5', 'D6'].forEach((n, i) => t.add(bell(NOTE(n), 0.7, 2.6), 0.62 + i * 0.012, 0.32, -0.3 + i * 0.2));
  t.add(harp(NOTE('D4'), 0.7, 2.6), 0.62, 0.35);
  for (const n of ['D3', 'A3', 'F#4']) t.add(padNote(NOTE(n), 1.0, { attack: 0.3, release: 1.6 }), 0.55, 0.12);
  return finish(lowpassTrack(t, 7000), -6, { verb: { wet: 0.28, size: 0.75, damp: 0.45 } });
};

// world_unlock (~4.5 s): harp glissando up two octaves of D pentatonic + pad swell + bell.
SFX.world_unlock = () => {
  const t = sfxTrack(6.0);
  const pent = ['D4', 'E4', 'F#4', 'A4', 'B4', 'D5', 'E5', 'F#5', 'A5', 'B5', 'D6'];
  pent.forEach((n, i) => t.add(harp(NOTE(n), 0.75, 2.4), i * 0.07, 0.42, -0.6 + i * 0.12));
  for (const n of ['D3', 'A3', 'E4', 'F#4']) t.add(padNote(NOTE(n), 2.0, { attack: 0.6, release: 2.0 }), 0.2, 0.12);
  t.add(bell(NOTE('A5'), 0.8, 3.0), 0.85, 0.35, 0.2);
  t.add(bell(NOTE('D6'), 0.8, 3.0), 0.87, 0.3, -0.2);
  return finish(lowpassTrack(t, 7000), -6, { verb: { wet: 0.32, size: 0.8, damp: 0.45 } });
};

// soft_pop: water droplet for Bloom decorations.
SFX.soft_pop = () => {
  const t = sfxTrack(0.25, false);
  const n = Math.ceil(0.16 * SR);
  const v = new Float32Array(n);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const x = i / SR;
    const f = 520 + 650 * (1 - Math.exp(-x / 0.02));
    ph += 2 * Math.PI * f / SR;
    v[i] = Math.sin(ph) * Math.exp(-x / 0.035) * Math.min(1, x / 0.002);
  }
  t.add(v, 0, 1);
  return finish(t, -10);
};

function lowpassTrack(t, cutoff) { t.ch = t.ch.map((c) => lowpass(c, cutoff)); return t; }

// ---------------------------------------------------------------------------------
// Music
// ---------------------------------------------------------------------------------

const PENTA = {
  D: [2, 4, 6, 9, 11],  // D major pent = B minor pent
  G: [7, 9, 11, 2, 4],  // G major pent = E minor pent
};

const SECTIONS = [
  { name: 'intro', segs: 2, density: 0, bells: true },
  { name: 'A', segs: 4, density: 1 },
  { name: 'B', segs: 4, density: 2, arp: true },
  { name: 'A2', segs: 4, density: 1, repeat: true },
  { name: 'break', segs: 2, density: 0, bells: true },
  { name: 'B2', segs: 4, density: 2, arp: true, repeat: true },
  { name: 'outro', segs: 2, density: -1 },
];

const RHYTHMS = {
  1: [[0, 6, 10], [2, 8, 12], [0, 3, 8], [0, 4, 10, 12], [2, 6, 11]],
  2: [[0, 2, 4, 7, 10, 12], [0, 3, 6, 8, 11, 14], [1, 4, 6, 9, 12], [0, 2, 6, 8, 10, 14]],
};

const TRACKS = {
  aurora_garden_a: {
    world: 'aurora_garden', bpm: 72, seed: 11, penta: 'D', lead: kalimba, leadRange: ['D4', 'D6'],
    arp: harp, sparkle: bell, padBright: 0.55, verb: { wet: 0.28, size: 0.8, damp: 0.45 },
    chords: [
      ['D2', 'D3 A3 C#4 E4 F#4'], ['B1', 'B2 F#3 A3 D4 E4'], ['G1', 'G2 D3 F#3 A3 B3'], ['A1', 'A2 E3 A3 D4 E4'],
      ['F#2', 'D3 A3 C#4 E4'], ['G1', 'G2 D3 A3 B3'], ['E2', 'E3 B3 D4 F#4 G4'], ['A1', 'A2 E3 F#3 B3 D4'],
    ],
  },
  aurora_garden_b: {
    world: 'aurora_garden', bpm: 66, seed: 12, penta: 'D', lead: harp, leadRange: ['A3', 'B5'],
    arp: kalimba, sparkle: bell, padBright: 0.5, verb: { wet: 0.3, size: 0.82, damp: 0.45 },
    chords: [
      ['B1', 'B2 F#3 A3 C#4 D4'], ['G1', 'G2 D3 F#3 A3 B3'], ['D2', 'D3 A3 E4 F#4'], ['A1', 'A2 E3 A3 C#4 E4'],
      ['E2', 'E3 B3 D4 F#4'], ['G1', 'G2 B2 D3 F#3 A3'], ['B1', 'B2 F#3 A3 D4'], ['A1', 'A2 E3 A3 D4 E4'],
    ],
  },
  pearl_coast_a: {
    world: 'pearl_coast', bpm: 78, seed: 21, penta: 'G', lead: marimba, leadRange: ['G4', 'E6'],
    arp: harp, sparkle: bell, padBright: 0.6, waves: true, verb: { wet: 0.3, size: 0.82, damp: 0.4 },
    chords: [
      ['G1', 'G2 D3 F#3 A3 B3'], ['E2', 'E3 B3 D4 F#4 G4'], ['C2', 'C3 G3 B3 D4 E4'], ['D2', 'D3 A3 D4 E4'],
      ['B1', 'B2 F#3 A3 D4'], ['E2', 'E3 B3 D4 G4'], ['C2', 'C3 G3 B3 E4'], ['D2', 'D3 A3 C4 E4'],
    ],
  },
  pearl_coast_b: {
    world: 'pearl_coast', bpm: 70, seed: 22, penta: 'G', lead: harp, leadRange: ['D4', 'D6'],
    arp: marimba, sparkle: bell, padBright: 0.55, waves: true, verb: { wet: 0.32, size: 0.84, damp: 0.42 },
    chords: [
      ['E2', 'E3 B3 D4 F#4 G4'], ['C2', 'C3 G3 B3 D4 E4'], ['G1', 'G2 D3 F#3 B3'], ['D2', 'D3 A3 D4 F#4'],
      ['A1', 'A2 E3 G3 B3 C4'], ['C2', 'C3 G3 B3 E4'], ['E2', 'E3 B3 D4 G4'], ['D2', 'D3 A3 D4 E4'],
    ],
  },
  crystal_nocturne_a: {
    world: 'crystal_nocturne', bpm: 62, seed: 31, penta: 'D', lead: glass, leadRange: ['B4', 'D6'],
    arp: kalimba, sparkle: glass, padBright: 0.42, verb: { wet: 0.38, size: 0.9, damp: 0.5 },
    chords: [
      ['B1', 'B2 F#3 A3 C#4 D4'], ['G1', 'G2 D3 F#3 B3'], ['E2', 'E3 B3 D4 F#4 G4'], ['F#2', 'F#2 C#3 E3 A3 B3'],
      ['D2', 'D3 A3 C#4 F#4'], ['G1', 'G2 D3 A3 B3'], ['E2', 'E3 B3 D4 G4'], ['F#2', 'F#2 C#3 E3 A3'],
    ],
  },
  crystal_nocturne_b: {
    world: 'crystal_nocturne', bpm: 58, seed: 32, penta: 'D', lead: kalimba, leadRange: ['F#4', 'B5'],
    arp: glass, sparkle: glass, padBright: 0.4, verb: { wet: 0.4, size: 0.92, damp: 0.5 },
    chords: [
      ['D2', 'D3 A3 C#4 E4 F#4'], ['B1', 'B2 F#3 A3 D4'], ['G1', 'G2 D3 F#3 A3 B3'], ['A1', 'A2 E3 A3 C#4'],
      ['E2', 'E3 B3 D4 F#4'], ['B1', 'B2 F#3 A3 C#4 D4'], ['G1', 'G2 D3 F#3 B3'], ['A1', 'A2 E3 A3 D4 E4'],
    ],
  },
};

function scaleNotes(pcs, lo, hi) {
  const out = [];
  for (let m = midi(lo); m <= midi(hi); m++) if (pcs.includes(((m % 12) + 12) % 12)) out.push(m);
  return out;
}

function composeTrack(name, spec) {
  const r = rng(spec.seed * 7919);
  const beat = 60 / spec.bpm, bar = 4 * beat, seg = 2 * bar, eighth = beat / 2;
  const totalSegs = SECTIONS.reduce((a, s) => a + s.segs, 0);
  const tail = 9;
  const length = totalSegs * seg + tail;
  const t = new Track(length, 2);
  const pcs = PENTA[spec.penta];
  const lead = scaleNotes(pcs, spec.leadRange[0], spec.leadRange[1]);
  const center = Math.floor(lead.length / 2);
  let idx = center;
  let segIndex = 0;
  const memory = []; // per segment: {rhythm, intervals}
  const human = () => (r() - 0.5) * 0.02;

  for (const sec of SECTIONS) {
    for (let s = 0; s < sec.segs; s++, segIndex++) {
      const t0 = segIndex * seg;
      const outro = sec.density === -1;
      const chord = outro ? spec.chords[0] : spec.chords[segIndex % spec.chords.length];
      const padNotes = chord[1].split(' ');
      const chordPcs = padNotes.map((n) => midi(n) % 12);
      const fadeOut = outro && s === sec.segs - 1;
      // pad
      const padDur = outro ? seg * (s === sec.segs - 1 ? 0.6 : 1.0) : seg;
      for (const n of padNotes) {
        t.add(padNote(hz(n), padDur, { attack: segIndex === 0 ? 3.0 : 1.4, release: fadeOut ? 5.0 : 2.0, bright: spec.padBright }), t0, 0.065, (midi(n) % 7) / 7 - 0.4);
      }
      // bass (fundamental + harmonics so it survives phone speakers)
      // one octave above the written root: phone speakers can't reproduce < ~100 Hz
      if (sec.name !== 'intro' || s > 0) t.add(bass(hz(midi(chord[0]) + 12), seg - 0.15), t0, outro ? 0.08 : 0.11, 0);
      // melody
      if (sec.density > 0) {
        let rhythm, intervals = null;
        const prev = memory[segIndex - 2];
        if (sec.repeat && prev && s % 2 === 0) {
          rhythm = prev.rhythm; intervals = prev.intervals;
        } else {
          const lib = RHYTHMS[sec.density];
          rhythm = lib[Math.floor(r() * lib.length)];
        }
        const used = [];
        rhythm.forEach((pos, k) => {
          if (k === 0 || pos === 0 || pos === 8) {
            // land near a chord tone on strong beats
            let best = idx, bestD = 99;
            for (let j = Math.max(0, idx - 3); j <= Math.min(lead.length - 1, idx + 3); j++) {
              if (chordPcs.includes(lead[j] % 12) && Math.abs(j - idx) < bestD) { best = j; bestD = Math.abs(j - idx); }
            }
            idx = intervals ? Math.max(0, Math.min(lead.length - 1, idx + intervals[k])) : best;
          } else {
            const step = intervals ? intervals[k] : [-2, -1, -1, 1, 1, 2, 0][Math.floor(r() * 7)];
            idx = Math.max(0, Math.min(lead.length - 1, idx + step + (idx > center + 4 ? -1 : idx < center - 4 ? 1 : 0)));
          }
          used.push(idx);
          const vel = (pos % 8 === 0 ? 0.82 : 0.62) * (0.92 + r() * 0.16);
          t.add(spec.lead(hz(lead[idx]), vel, 3.0), t0 + pos * eighth + human(), 0.33, -0.15);
        });
        memory[segIndex] = { rhythm, intervals: used.map((v, k) => (k === 0 ? 0 : v - used[k - 1])) };
      }
      // arpeggio layer (broken chord an octave up)
      if (sec.arp) {
        const arpNotes = padNotes.map((n) => midi(n) + 12).sort((a, b) => a - b);
        const steps = s % 2 === 0 ? [0, 1, 2, 3, 4, 5, 6, 7] : [0, 2, 4, 6];
        steps.forEach((st, k) => {
          const m = arpNotes[k % arpNotes.length];
          t.add(spec.arp(hz(m), 0.38 * (0.9 + r() * 0.2), 2.2), t0 + st * beat + human(), 0.15, -0.6 + (k % 5) * 0.3);
        });
      }
      // sparkle bells
      if (sec.bells || (sec.density >= 1 && segIndex % 4 === 3)) {
        const hiNotes = scaleNotes(pcs, 'D6', 'B6');
        const at = t0 + (4 + Math.floor(r() * 8)) * eighth;
        const count = 2 + Math.floor(r() * 2);
        let j = Math.floor(r() * (hiNotes.length - count));
        for (let k = 0; k < count; k++) {
          t.add(spec.sparkle(hz(hiNotes[j + k]), 0.5, 3.0), at + k * eighth * 0.75, 0.09, 0.45);
        }
      }
      // final tonic note in the outro
      if (outro && s === 0) {
        const tonic = lead.find((m) => m % 12 === midi(spec.chords[0][0]) % 12 && m >= midi(spec.leadRange[0]) + 5) ?? lead[center];
        t.add(spec.lead(hz(tonic), 0.7, 4.0), t0 + 0.05, 0.3, 0);
      }
    }
  }
  // ocean wash for Pearl Coast
  if (spec.waves) {
    for (const [c, sd] of [[0, 91], [1, 92]]) {
      const w = lowpass(highpass(noise(length, sd), 160), 800);
      envelope(w, (x) => 0.25 + 0.75 * Math.pow(0.5 + 0.5 * Math.sin(2 * Math.PI * x / (8.3 + c * 0.9) + c), 2));
      for (let i = 0; i < t.n; i++) t.ch[c][i] += w[i] * 0.045;
    }
  }
  reverb(t, spec.verb);
  t.ch = t.ch.map((c) => highpass(highpass(lowpass(c, 9000), 70), 70));
  dcBlock(t);
  // gentle global fade-in (first 2 s) and natural end
  const fi = 2 * SR;
  for (const c of t.ch) for (let i = 0; i < fi; i++) c[i] *= i / fi;
  trimTail(t, 0.2);
  edgeFades(t, 0.01, 1.5);
  return t;
}

// ---------------------------------------------------------------------------------
// Loudness (ffmpeg ebur128) and file output
// ---------------------------------------------------------------------------------

function ffmpegStderr(args) {
  const p = spawnSync('ffmpeg', args, { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  return (p.stdout || '') + (p.stderr || '');
}

function stats(file, { pad = false } = {}) {
  // Short effects are shorter than the 400 ms momentary window, so they are measured inside
  // 0.5 s of silence; the max momentary value is then a fair "event loudness" for comparison.
  const af = (pad ? 'adelay=500:all=1,apad=pad_dur=0.6,' : '') + 'ebur128=peak=true:framelog=verbose';
  const txt = ffmpegStderr(['-hide_banner', '-nostats', '-v', 'verbose', '-i', file, '-af', af, '-f', 'null', '-']);
  const sumIdx = txt.lastIndexOf('Summary:');
  const summary = sumIdx >= 0 ? txt.slice(sumIdx) : '';
  const I = /I:\s+(-?[\d.]+) LUFS/.exec(summary);
  const P = /Peak:\s+(-?[\d.]+) dBFS/.exec(summary);
  let mMax = -Infinity;
  for (const m of txt.slice(0, sumIdx).matchAll(/ M:\s*(-?[\d.]+)/g)) mMax = Math.max(mMax, Number(m[1]));
  return { I: I ? Number(I[1]) : null, truePeak: P ? Number(P[1]) : null, momentaryMax: Number.isFinite(mMax) ? mMax : null };
}

/** Share of signal energy in the ear's most sensitive/fatiguing band (2.5-4.5 kHz), in dB. */
function harshness(file) {
  const rms = (af) => {
    const txt = ffmpegStderr(['-hide_banner', '-nostats', '-i', file, '-af', af + 'astats=metadata=0:measure_overall=RMS_level', '-f', 'null', '-']);
    const m = [...txt.matchAll(/RMS level dB:\s*(-?[\d.]+|-inf)/g)].pop();
    return m && m[1] !== '-inf' ? Number(m[1]) : -120;
  };
  return +(rms('highpass=f=2500:poles=2,highpass=f=2500:poles=2,lowpass=f=4500:poles=2,lowpass=f=4500:poles=2,') - rms('')).toFixed(1);
}

const report = { sfx: {}, music: {} };

function writeWav(track, file) { fs.writeFileSync(file, wavBuffer(track)); }

// --- SFX ---
for (const [name, make] of Object.entries(SFX)) {
  const t = make();
  const file = path.join(AUDIO, 'sfx', `${name}.wav`);
  writeWav(t, file);
  const st = stats(file, { pad: true });
  const harsh = harshness(file);
  report.sfx[name] = { seconds: +(t.n / SR).toFixed(3), channels: t.ch.length, eventLoudness: st.momentaryMax, truePeak: st.truePeak, harsh2_5to4_5kHz_dB: harsh };
  console.log(`sfx ${name.padEnd(14)} ${(t.n / SR).toFixed(2)}s  event ${st.momentaryMax?.toFixed(1)} LUFS  peak ${st.truePeak?.toFixed(1)} dBTP  2.5-4.5k ${harsh} dB`);
}

// --- music ---
for (const [name, spec] of Object.entries(TRACKS)) {
  const t = composeTrack(name, spec);
  const raw = path.join(WORK, `${name}.wav`);
  writeWav(t, raw);
  let st = stats(raw);
  if (st.I === null || st.truePeak === null) throw new Error(`loudness measurement failed for ${name}`);
  let g = MUSIC_LUFS - st.I;
  if (st.truePeak + g > TRUE_PEAK_MAX) g = TRUE_PEAK_MAX - st.truePeak;
  gain(t, Math.pow(10, g / 20));
  writeWav(t, raw);
  const ogg = path.join(AUDIO, 'music', `${name}.ogg`);
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-i', raw, '-c:a', 'libvorbis', '-q:a', '3', ogg]);
  st = stats(ogg);
  const harsh = harshness(ogg);
  report.music[name] = { world: spec.world, bpm: spec.bpm, seconds: +(t.n / SR).toFixed(1), kbytes: Math.round(fs.statSync(ogg).size / 1024), integrated: st.I, truePeak: st.truePeak, harsh2_5to4_5kHz_dB: harsh };
  console.log(`music ${name.padEnd(20)} ${(t.n / SR).toFixed(0)}s  I ${st.I} LUFS  peak ${st.truePeak} dBTP  2.5-4.5k ${harsh} dB  ${report.music[name].kbytes} KB`);
}

fs.writeFileSync(path.join(WORK, 'report.json'), JSON.stringify(report, null, 2));
console.log('AUDIO DONE');
