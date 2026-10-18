// Small deterministic DSP toolkit for generating the game's audio offline.
// Everything is seeded, so re-running the generator reproduces identical files.

export const SR = 44100;
const TAU = Math.PI * 2;

export function rng(seed) {
  let s = (seed >>> 0) || 0x9e3779b9;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 4294967296;
  };
}

const PCS = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
/** "F#4" / "Bb3" / "D5" -> MIDI number */
export function midi(name) {
  const m = /^([A-G])([#b]?)(-?\d)$/.exec(name);
  if (!m) throw new Error(`bad note ${name}`);
  return PCS[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0) + (Number(m[3]) + 1) * 12;
}
export const hz = (m) => 440 * Math.pow(2, ((typeof m === 'string' ? midi(m) : m) - 69) / 12);

/** Stereo (or mono) float buffer with mixing helpers. */
export class Track {
  constructor(seconds, channels = 2) {
    this.n = Math.ceil(seconds * SR);
    this.ch = Array.from({ length: channels }, () => new Float32Array(this.n));
  }
  /** Mix a mono voice at time t (s) with gain and equal-power pan (-1..1). */
  add(voice, t, gain = 1, pan = 0) {
    const start = Math.round(t * SR);
    const nch = this.ch.length;
    const a = (pan + 1) * Math.PI / 4;
    const gl = nch === 1 ? gain : gain * Math.cos(a) * Math.SQRT2;
    const gr = nch === 1 ? gain : gain * Math.sin(a) * Math.SQRT2;
    const L = this.ch[0];
    const R = this.ch[nch - 1];
    for (let i = 0; i < voice.length; i++) {
      const j = start + i;
      if (j < 0) continue;
      if (j >= this.n) break;
      L[j] += voice[i] * gl;
      if (nch > 1) R[j] += voice[i] * gr;
    }
  }
}

/** Raised-cosine attack, exponential decay per partial, optional release fade. */
export function partials(freq, dur, parts, { attack = 0.004, release = 0.03, phaseSeed = 1 } = {}) {
  const n = Math.ceil(dur * SR);
  const out = new Float32Array(n);
  const r = rng(phaseSeed);
  const na = Math.max(1, Math.round(attack * SR));
  const nr = Math.max(1, Math.round(release * SR));
  for (const p of parts) {
    const f = freq * p.ratio;
    if (f >= SR / 2 - 200) continue; // never alias
    const w = TAU * f / SR;
    const k = p.decay > 0 ? Math.exp(-1 / (p.decay * SR)) : 1;
    let env = p.amp;
    let ph = r() * TAU * (p.randomPhase ? 1 : 0);
    // recursive oscillator for speed (sin/cos rotation)
    const c = Math.cos(w), s = Math.sin(w);
    let x = Math.cos(ph), y = Math.sin(ph);
    for (let i = 0; i < n; i++) {
      out[i] += y * env;
      env *= k;
      const nx = x * c - y * s;
      y = x * s + y * c;
      x = nx;
    }
  }
  for (let i = 0; i < na && i < n; i++) out[i] *= 0.5 - 0.5 * Math.cos(Math.PI * i / na);
  for (let i = 0; i < nr && i < n; i++) out[n - 1 - i] *= 0.5 - 0.5 * Math.cos(Math.PI * i / nr);
  return out;
}

// ---- instruments (all mono voices) ------------------------------------------------

/** Kalimba / thumb piano: warm fundamental, quick metallic tine ping. */
export function kalimba(freq, vel = 1, len = 2.2) {
  const d = Math.min(2.4, 1.5 * Math.sqrt(440 / freq));
  return scale(partials(freq, len, [
    { ratio: 1, amp: 1, decay: d },
    { ratio: 2, amp: 0.10, decay: d * 0.35 },
    { ratio: 3, amp: 0.04, decay: d * 0.2 },
    { ratio: 5.93, amp: 0.10, decay: 0.05 },
  ], { attack: 0.003, release: 0.08 }), vel);
}

/** Harp: bright harmonic pluck with a soft attack. */
export function harp(freq, vel = 1, len = 2.6) {
  const d = Math.min(3.0, 1.9 * Math.sqrt(330 / freq));
  const parts = [];
  for (let k = 1; k <= 7; k++) parts.push({ ratio: k, amp: 1 / Math.pow(k, 1.45), decay: d / Math.pow(k, 0.7) });
  return scale(partials(freq, len, parts, { attack: 0.005, release: 0.1 }), vel * 0.7);
}

/** Soft-mallet marimba (tuned 1 : 4 : 9.9). */
export function marimba(freq, vel = 1, len = 1.8) {
  const d = Math.min(1.4, 0.9 * Math.pow(440 / freq, 0.6));
  return scale(partials(freq, len, [
    { ratio: 1, amp: 1, decay: d },
    { ratio: 4, amp: 0.14, decay: d * 0.22 },
    { ratio: 9.9, amp: 0.04, decay: d * 0.07 },
  ], { attack: 0.004, release: 0.08 }), vel);
}

/** Celesta-like bell: mostly harmonic, gentle shimmer. */
export function bell(freq, vel = 1, len = 2.5) {
  return scale(partials(freq, len, [
    { ratio: 1, amp: 1, decay: 1.3 },
    { ratio: 2, amp: 0.32, decay: 0.8 },
    { ratio: 3, amp: 0.10, decay: 0.45 },
    { ratio: 4.07, amp: 0.07, decay: 0.3 },
  ], { attack: 0.003, release: 0.15 }), vel);
}

/** Glass bell for the night world: softly inharmonic. */
export function glass(freq, vel = 1, len = 3.2) {
  return scale(partials(freq, len, [
    { ratio: 1, amp: 1, decay: 1.8 },
    { ratio: 2.76, amp: 0.16, decay: 0.9 },
    { ratio: 5.4, amp: 0.05, decay: 0.4 },
  ], { attack: 0.006, release: 0.2 }), vel);
}

/** Warm sustained pad note: three slightly detuned voices, soft harmonics, slow envelope. */
export function padNote(freq, dur, { attack = 1.6, release = 1.8, bright = 1 } = {}) {
  const total = dur + release;
  const n = Math.ceil(total * SR);
  const out = new Float32Array(n);
  for (const det of [-0.0042, 0, 0.0047]) {
    const parts = [];
    for (let k = 1; k <= 5; k++) parts.push({ ratio: k * (1 + det), amp: Math.pow(bright, k - 1) / Math.pow(k, 1.9), decay: 0 });
    const v = partials(freq, total, parts, { attack: 0.01, release: 0.01, phaseSeed: Math.round(freq * 1000 + det * 1e6) });
    for (let i = 0; i < n; i++) out[i] += v[i] / 3;
  }
  const na = Math.round(attack * SR), ns = Math.round(dur * SR);
  for (let i = 0; i < n; i++) {
    let e;
    if (i < na) e = 0.5 - 0.5 * Math.cos(Math.PI * i / na);
    else if (i < ns) e = 1;
    else e = 0.5 + 0.5 * Math.cos(Math.PI * Math.min(1, (i - ns) / (n - ns)));
    out[i] *= e;
  }
  return out;
}

/** Soft sine bass with a little 2nd harmonic. */
export function bass(freq, dur) {
  return partials(freq, dur + 1.2, [
    { ratio: 1, amp: 1, decay: 0 },
    { ratio: 2, amp: 0.12, decay: 0 },
  ], { attack: 0.08, release: 1.2 });
}

// ---- noise & filters ----------------------------------------------------------------

export function noise(seconds, seed) {
  const r = rng(seed);
  const out = new Float32Array(Math.ceil(seconds * SR));
  for (let i = 0; i < out.length; i++) out[i] = r() * 2 - 1;
  return out;
}

export function lowpass(x, cutoff) {
  const a = 1 - Math.exp(-TAU * cutoff / SR);
  let y = 0;
  const out = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) { y += a * (x[i] - y); out[i] = y; }
  return out;
}

export function highpass(x, cutoff) {
  const lp = lowpass(x, cutoff);
  const out = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) out[i] = x[i] - lp[i];
  return out;
}

/** RBJ band-pass (constant 0 dB peak gain). */
export function bandpass(x, f0, q) {
  const w = TAU * f0 / SR, al = Math.sin(w) / (2 * q), c = Math.cos(w);
  const b0 = al, b2 = -al, a0 = 1 + al, a1 = -2 * c, a2 = 1 - al;
  const out = new Float32Array(x.length);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < x.length; i++) {
    const y = (b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2) / a0;
    x2 = x1; x1 = x[i]; y2 = y1; y1 = y; out[i] = y;
  }
  return out;
}

export function scale(x, g) { for (let i = 0; i < x.length; i++) x[i] *= g; return x; }

/** Multiply by an envelope function env(tSeconds) -> gain. */
export function envelope(x, env) { for (let i = 0; i < x.length; i++) x[i] *= env(i / SR); return x; }

// ---- reverb (Freeverb) ---------------------------------------------------------------

const COMBS = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
const ALLPASS = [556, 441, 341, 225];

function freeverbChannel(input, spread, room, damp) {
  const n = input.length;
  const out = new Float32Array(n);
  for (const len0 of COMBS) {
    const len = len0 + spread;
    const buf = new Float32Array(len);
    let idx = 0, store = 0;
    for (let i = 0; i < n; i++) {
      const y = buf[idx];
      store = y * (1 - damp) + store * damp;
      buf[idx] = input[i] + store * room;
      out[i] += y;
      if (++idx >= len) idx = 0;
    }
  }
  for (const len0 of ALLPASS) {
    const len = len0 + spread;
    const buf = new Float32Array(len);
    let idx = 0;
    for (let i = 0; i < n; i++) {
      const b = buf[idx];
      const y = -out[i] + b;
      buf[idx] = out[i] + b * 0.5;
      out[i] = y;
      if (++idx >= len) idx = 0;
    }
  }
  return out;
}

/** In-place stereo reverb; wet in 0..1, size 0..1, damp 0..1. */
export function reverb(track, { wet = 0.25, size = 0.8, damp = 0.4, predelay = 0.012 } = {}) {
  const n = track.n;
  const L = track.ch[0], R = track.ch[track.ch.length - 1];
  const pd = Math.round(predelay * SR);
  const mono = new Float32Array(n);
  for (let i = pd; i < n; i++) mono[i] = (L[i - pd] + R[i - pd]) * 0.015;
  const room = 0.7 + 0.28 * size;
  const wl = freeverbChannel(mono, 0, room, damp);
  const wr = track.ch.length > 1 ? freeverbChannel(mono, 23, room, damp) : wl;
  // darken the tail a little more so it never hisses
  const dl = lowpass(wl, 5200), dr = track.ch.length > 1 ? lowpass(wr, 5200) : dl;
  for (let i = 0; i < n; i++) {
    L[i] = L[i] * (1 - wet * 0.5) + dl[i] * wet;
    if (track.ch.length > 1) R[i] = R[i] * (1 - wet * 0.5) + dr[i] * wet;
  }
}

// ---- mastering helpers -----------------------------------------------------------------

export function peak(track) {
  let p = 0;
  for (const c of track.ch) for (let i = 0; i < c.length; i++) p = Math.max(p, Math.abs(c[i]));
  return p;
}

export function gain(track, g) { for (const c of track.ch) scale(c, g); }

export function normalizePeak(track, dbfs) {
  const p = peak(track);
  if (p > 0) gain(track, Math.pow(10, dbfs / 20) / p);
}

/** Short fades so files never start/stop with a click. */
export function edgeFades(track, inS = 0.002, outS = 0.03) {
  const ni = Math.round(inS * SR), no = Math.round(outS * SR);
  for (const c of track.ch) {
    for (let i = 0; i < ni && i < c.length; i++) c[i] *= i / ni;
    for (let i = 0; i < no && i < c.length; i++) c[c.length - 1 - i] *= i / no;
  }
}

/** Removes DC offset per channel. */
export function dcBlock(track) {
  for (const c of track.ch) {
    let x1 = 0, y1 = 0;
    for (let i = 0; i < c.length; i++) { const y = c[i] - x1 + 0.9995 * y1; x1 = c[i]; y1 = y; c[i] = y; }
  }
}

/** Trims trailing near-silence (below -70 dBFS) leaving a short margin. */
export function trimTail(track, margin = 0.05) {
  const thr = Math.pow(10, -70 / 20);
  let last = 0;
  for (const c of track.ch) for (let i = c.length - 1; i > last; i--) if (Math.abs(c[i]) > thr) { last = i; break; }
  const n = Math.min(track.n, last + Math.round(margin * SR));
  track.ch = track.ch.map((c) => c.slice(0, n));
  track.n = n;
}

export function wavBuffer(track) {
  const nch = track.ch.length, n = track.n;
  const buf = Buffer.alloc(44 + n * nch * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * nch * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(nch, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * nch * 2, 28); buf.writeUInt16LE(nch * 2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * nch * 2, 40);
  let o = 44;
  for (let i = 0; i < n; i++) {
    for (let c = 0; c < nch; c++) {
      const v = Math.max(-1, Math.min(1, track.ch[c][i]));
      buf.writeInt16LE(Math.round(v * 32767), o); o += 2;
    }
  }
  return buf;
}
