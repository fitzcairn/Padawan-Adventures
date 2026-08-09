/**
 * Minimal take cleanup: tonal hum notching, keyboard click removal,
 * leading/trailing silence trim, tiny edge fades, WAV encode.
 *
 * Deliberately does NOT EQ, broadband-denoise, compress, or otherwise process
 * the spoken word — tone adjustments will be layered back in later. The only
 * spectral work is a handful of very narrow notches at measured steady tones,
 * which leaves speech essentially untouched.
 */

import { transform } from "./fft.js";

/** Welch frame size for profiling the room tone (8192 @ 48k ≈ 5.9 Hz bins). */
const TONE_FFT_SIZE = 8192;
/** Below this the bins are too coarse to place a narrow notch — skip instead. */
const TONE_MIN_FFT_SIZE = 2048;
const TONE_MIN_HZ = 40;
/** Search right up the band — coil whine and flyback sit far above mains hum. */
const TONE_MAX_FRAC = 0.45;
/** A bin must stand this far above the local spectral floor to count as tonal. */
const TONE_PROMINENCE_DB = 9;
/** Half-width, in bins, of the neighbourhood used to estimate that floor. */
const TONE_FLOOR_HALF_BINS = 40;
/** Bins either side of a peak excluded from its own floor estimate. */
const TONE_GUARD_BINS = 3;
const MAX_NOTCHES = 12;
/**
 * Target notch width, and the main tradeoff here. Narrow protects the voice —
 * a mains harmonic can sit a few Hz from a voice harmonic — but a notch rings
 * for roughly 1/(pi * BW) seconds, so 3 Hz would ring for ~100 ms, a big chunk
 * of a word. 6 Hz halves the ring while still costing a neighbouring harmonic
 * only ~0.3 dB. Q is clamped below, widening the notch up high where there is
 * no voice content to protect.
 */
const NOTCH_BW_HZ = 6;
const NOTCH_MIN_Q = 4;
const NOTCH_MAX_Q = 500;
/** Samples used to pin a tone's exact centre — a 3 Hz notch has to land on it. */
const REFINE_MAX_SAMPLES = 16384;
const REFINE_ITERATIONS = 25;
/** Mirror padding so zero-phase filtering doesn't ring at the take edges. */
const NOTCH_PAD = 4096;

const TRIM_WINDOW_MS = 8;
/** Little pad before speech so plosives aren't clipped. */
const LEAD_PAD_MS = 8;
/** Extra tail so word endings aren't clipped by silence trim / release guard. */
const TRAIL_PAD_MS = 55;
/** Loud gate: locates the voiced core of the word. */
const TRIM_PEAK_FRAC = 0.07;
const TRIM_NOISE_MULT = 5.5;
/**
 * Soft gate for unvoiced consonants. A final /t/, /k/, /p/ or /s/ sits at only
 * 1-3% of the vowel peak, so the loud gate above would shear it off.
 */
const SOFT_PEAK_FRAC = 0.012;
const SOFT_NOISE_MULT = 2.2;
/** High-frequency energy over room noise that marks a stop burst or fricative. */
const SOFT_HF_MULT = 5;
/** How far past the voiced core to hunt for a trailing consonant. */
const TAIL_HANGOVER_MS = 200;
/** Silent stop closure allowed between vowel and burst (the gap in "cat"). */
const TAIL_GAP_MS = 110;
/** Same, ahead of the voiced core (the burst in "tap"). */
const HEAD_HANGOVER_MS = 140;
const HEAD_GAP_MS = 60;
/** Fixed discard at hold edges — Space key travel / bounce. */
const PRESS_GUARD_MS = 60;
const RELEASE_GUARD_MS = 40;
/** Speech this close to a transient marks it as a consonant, not a key click. */
const CLICK_LOOKBACK_MS = 260;
const CLICK_LOOKAHEAD_MS = 120;
const FADE_MS = 8;
const QUIET_PEAK = 1e-4;

/**
 * @param {Float32Array} samples
 * @param {Float32Array} noiseSamples pre-press room noise (tone profile + silence gate)
 * @param {number} sampleRate
 * @returns {{ samples: Float32Array, tooQuiet: boolean, notches: number[] }}
 */
export function cleanup(samples, noiseSamples, sampleRate) {
  let out = Float32Array.from(samples);

  // 1) Notch out steady tones measured in the pre-press room noise. Done first
  //    so the gates below see the real broadband floor, not the hum.
  const notches = findTones(noiseSamples, sampleRate);
  const noiseRef = noiseSamples ? Float32Array.from(noiseSamples) : new Float32Array(0);
  for (const freq of notches) {
    const coeffs = makeNotch(sampleRate, freq, notchQ(freq));
    applyBiquadZeroPhase(out, coeffs);
    applyBiquadZeroPhase(noiseRef, coeffs);
  }

  const noiseRms = Math.max(rmsOf(noiseRef), 1e-5);
  const noiseHf = Math.max(hfEnergy(noiseRef, 0, noiseRef.length), 1e-12);

  // 2) Hard edge guards — most reliable against Space down/up clicks.
  out = dropEdgeGuards(out, sampleRate, PRESS_GUARD_MS, RELEASE_GUARD_MS);

  // 3) Smart pass for leftover click spikes (bounce, late key noise).
  out = trimPressClick(out, sampleRate, noiseRms, noiseHf);
  out = trimReleaseClick(out, sampleRate, noiseRms, noiseHf);

  // 4) Trim blank time using the real pre-press noise floor.
  out = trimSilence(out, sampleRate, noiseRms, noiseHf);

  applyFades(out, sampleRate, FADE_MS);

  const peak = peakOf(out);
  return { samples: out, tooQuiet: peak < QUIET_PEAK, notches };
}

// ---------------------------------------------------------------------------
// Tonal hum removal
// ---------------------------------------------------------------------------

/**
 * Averaged (Welch) power spectrum of the room noise, in dB per bin.
 * @returns {{ db: Float64Array, binHz: number } | null}
 */
function noiseSpectrumDb(noiseSamples, sampleRate) {
  if (!noiseSamples) return null;
  let size = TONE_FFT_SIZE;
  while (size > noiseSamples.length) size >>= 1;
  if (size < TONE_MIN_FFT_SIZE) return null;
  const hop = size >> 2;
  const bins = size >> 1;
  const window = new Float64Array(size);
  for (let i = 0; i < size; i++) {
    window[i] = 0.5 * (1 - Math.cos((2 * Math.PI * i) / (size - 1)));
  }

  const power = new Float64Array(bins);
  const re = new Float64Array(size);
  const im = new Float64Array(size);
  let frames = 0;
  for (let start = 0; start + size <= noiseSamples.length; start += hop) {
    for (let i = 0; i < size; i++) {
      re[i] = noiseSamples[start + i] * window[i];
      im[i] = 0;
    }
    transform(re, im, false);
    for (let k = 0; k < bins; k++) {
      power[k] += re[k] * re[k] + im[k] * im[k];
    }
    frames += 1;
  }
  if (frames === 0) return null;

  const db = new Float64Array(bins);
  for (let k = 0; k < bins; k++) {
    db[k] = 10 * Math.log10(power[k] / frames + 1e-20);
  }
  return { db, binHz: sampleRate / size };
}

function medianExcluding(db, center, halfWidth, guard) {
  const from = Math.max(0, center - halfWidth);
  const to = Math.min(db.length, center + halfWidth + 1);
  const pool = [];
  for (let k = from; k < to; k++) {
    if (Math.abs(k - center) <= guard) continue;
    pool.push(db[k]);
  }
  if (pool.length === 0) return db[center];
  pool.sort((a, b) => a - b);
  return pool[pool.length >> 1];
}

/**
 * Steady tones in the room noise: narrow spectral peaks standing well clear of
 * their local floor. Broadband hiss has no such peaks, so a quiet room yields
 * an empty list and nothing is filtered.
 * @returns {number[]} centre frequencies in Hz, strongest first
 */
function findTones(noiseSamples, sampleRate) {
  const spectrum = noiseSpectrumDb(noiseSamples, sampleRate);
  if (!spectrum) return [];
  const { db, binHz } = spectrum;
  const minBin = Math.max(1, Math.round(TONE_MIN_HZ / binHz));
  const maxBin = Math.min(db.length - 2, Math.round((sampleRate * TONE_MAX_FRAC) / binHz));

  const found = [];
  for (let k = minBin; k <= maxBin; k++) {
    if (db[k] < db[k - 1] || db[k] < db[k + 1]) continue;
    const floor = medianExcluding(db, k, TONE_FLOOR_HALF_BINS, TONE_GUARD_BINS);
    const prominence = db[k] - floor;
    if (prominence < TONE_PROMINENCE_DB) continue;

    found.push({ freq: k * binHz, prominence });
  }

  found.sort((a, b) => b.prominence - a.prominence);
  // One tone smears across the Hann main lobe, so keep rivals a lobe apart.
  const minSpacing = 4 * binHz;
  const picked = [];
  for (const tone of found) {
    if (picked.length >= MAX_NOTCHES) break;
    if (picked.some((f) => Math.abs(f - tone.freq) < minSpacing)) continue;
    picked.push(refineTone(noiseSamples, sampleRate, tone.freq, binHz));
  }
  return picked;
}

/**
 * Pin a tone's centre by maximising the windowed DFT magnitude around the
 * coarse bin. FFT bins are ~6 Hz apart, far too coarse to aim a 3 Hz notch.
 */
function refineTone(noiseSamples, sampleRate, coarseHz, binHz) {
  const n = Math.min(noiseSamples.length, REFINE_MAX_SAMPLES);
  const window = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    window[i] = 0.5 * (1 - Math.cos((2 * Math.PI * i) / (n - 1)));
  }
  const magAt = (freq) => {
    const w = (2 * Math.PI * freq) / sampleRate;
    const cw = Math.cos(w);
    const sw = Math.sin(w);
    let pr = 1;
    let pi = 0;
    let re = 0;
    let im = 0;
    for (let i = 0; i < n; i++) {
      const x = noiseSamples[i] * window[i];
      re += x * pr;
      im += x * pi;
      const nr = pr * cw - pi * sw;
      pi = pr * sw + pi * cw;
      pr = nr;
    }
    return Math.hypot(re, im);
  };

  let lo = Math.max(1, coarseHz - binHz);
  let hi = Math.min(sampleRate / 2, coarseHz + binHz);
  for (let it = 0; it < REFINE_ITERATIONS; it++) {
    const m1 = lo + (hi - lo) / 3;
    const m2 = hi - (hi - lo) / 3;
    if (magAt(m1) < magAt(m2)) lo = m1;
    else hi = m2;
  }
  return (lo + hi) / 2;
}

function notchQ(freq) {
  return Math.max(NOTCH_MIN_Q, Math.min(NOTCH_MAX_Q, freq / NOTCH_BW_HZ));
}

/** RBJ band-reject biquad, normalised by a0. */
function makeNotch(sampleRate, freq, q) {
  const w0 = (2 * Math.PI * freq) / sampleRate;
  const cosw = Math.cos(w0);
  const alpha = Math.sin(w0) / (2 * q);
  const a0 = 1 + alpha;
  return {
    b0: 1 / a0,
    b1: (-2 * cosw) / a0,
    b2: 1 / a0,
    a1: (-2 * cosw) / a0,
    a2: (1 - alpha) / a0,
  };
}

/** Forward + reverse pass: no phase smearing, at the cost of doubled depth. */
function applyBiquadZeroPhase(samples, c) {
  const n = samples.length;
  if (n < 8) return;
  const pad = Math.min(NOTCH_PAD, n - 2);
  const buf = new Float64Array(n + 2 * pad);
  for (let i = 0; i < pad; i++) buf[i] = samples[pad - i];
  for (let i = 0; i < n; i++) buf[pad + i] = samples[i];
  for (let i = 0; i < pad; i++) buf[pad + n + i] = samples[n - 2 - i];

  biquadPass(buf, c, false);
  biquadPass(buf, c, true);

  for (let i = 0; i < n; i++) samples[i] = buf[pad + i];
}

function biquadPass(buf, c, reverse) {
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  const n = buf.length;
  for (let step = 0; step < n; step++) {
    const i = reverse ? n - 1 - step : step;
    const x = buf[i];
    const y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    buf[i] = y;
  }
}

/**
 * @param {Float32Array} samples
 * @param {number} sampleRate
 * @returns {Blob}
 */
export function encodeWav(samples, sampleRate) {
  const numSamples = samples.length;
  const bytesPerSample = 2;
  const blockAlign = bytesPerSample; // mono
  const byteRate = sampleRate * blockAlign;
  const dataSize = numSamples * bytesPerSample;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);

  writeString(view, 0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  writeString(view, 8, "WAVE");
  writeString(view, 12, "fmt ");
  view.setUint32(16, 16, true); // PCM chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, 16, true); // bits per sample
  writeString(view, 36, "data");
  view.setUint32(40, dataSize, true);

  let offset = 44;
  for (let i = 0; i < numSamples; i++) {
    let s = samples[i];
    if (s > 0.999969482421875) s = 0.999969482421875;
    if (s < -1) s = -1;
    view.setInt16(offset, (s * 32767) | 0, true);
    offset += 2;
  }
  return new Blob([buffer], { type: "audio/wav" });
}

function writeString(view, offset, str) {
  for (let i = 0; i < str.length; i++) {
    view.setUint8(offset + i, str.charCodeAt(i));
  }
}

function peakOf(samples) {
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > peak) peak = a;
  }
  return peak;
}

function rmsOf(samples) {
  if (!samples || samples.length === 0) return 0;
  let sum = 0;
  for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
  return Math.sqrt(sum / samples.length);
}

function dropEdgeGuards(samples, sampleRate, headMs, tailMs) {
  const head = Math.round((sampleRate * headMs) / 1000);
  const tail = Math.round((sampleRate * tailMs) / 1000);
  if (samples.length <= head + tail + 64) return samples;
  return samples.slice(head, samples.length - tail);
}

/** Crude high-pass energy — keyboard clicks are short and bright. */
function hfEnergy(samples, from, to) {
  if (to - from < 2) return 0;
  let prev = samples[from];
  let sum = 0;
  for (let i = from + 1; i < to; i++) {
    const hp = samples[i] - prev;
    prev = samples[i];
    sum += hp * hp;
  }
  return sum / (to - from - 1);
}

/**
 * Find a short bright transient in [from, to) — a key click or a stop burst.
 * Callers decide which by looking at the speech around it.
 * @returns {number} sample index of the onset, or -1
 */
function findTransient(samples, from, to, sampleRate, noiseRms, noiseHf, peak) {
  if (to - from < 64) return -1;
  const win = Math.max(1, Math.round(sampleRate * 0.003));
  const ampGate = Math.max(noiseRms * 5, peak * 0.05);
  const hfGate = noiseHf * 10;

  for (let i = from; i + win < to; i += win) {
    let localPeak = 0;
    for (let j = i; j < i + win; j++) {
      const a = Math.abs(samples[j]);
      if (a > localPeak) localPeak = a;
    }
    if (localPeak >= ampGate) return i;
    const hf = hfEnergy(samples, i, Math.min(to, i + win * 3));
    if (hf >= hfGate && localPeak >= noiseRms * 3) return i;
  }
  return -1;
}

/** True when any 5 ms slice within `spanMs` on the given side clears `level`. */
function hasSpeechNear(samples, index, sampleRate, spanMs, level, side) {
  const span = Math.round((sampleRate * spanMs) / 1000);
  const from = side === "before" ? Math.max(0, index - span) : Math.min(samples.length, index);
  const to = side === "before" ? index : Math.min(samples.length, index + span);
  const step = Math.max(1, Math.round(sampleRate * 0.005));
  for (let i = from; i < to; i += step) {
    const end = Math.min(to, i + step);
    let sum = 0;
    for (let j = i; j < end; j++) sum += samples[j] * samples[j];
    if (Math.sqrt(sum / Math.max(1, end - i)) >= level) return true;
  }
  return false;
}

function speechLevelOf(peak, noiseRms) {
  return Math.max(noiseRms * TRIM_NOISE_MULT, peak * TRIM_PEAK_FRAC);
}

function trimPressClick(samples, sampleRate, noiseRms, noiseHf) {
  if (samples.length === 0) return samples;
  const peak = peakOf(samples);
  const guard = Math.min(samples.length, Math.round((sampleRate * 160) / 1000));
  const onset = findTransient(samples, 0, guard, sampleRate, noiseRms, noiseHf, peak);
  if (onset < 0) return samples;
  // A word-initial /t/ is followed almost at once by the vowel; a key-down
  // click is followed by the speaker's pause.
  const level = speechLevelOf(peak, noiseRms);
  if (hasSpeechNear(samples, onset, sampleRate, CLICK_LOOKAHEAD_MS, level, "after")) {
    return samples;
  }
  const cut = Math.min(samples.length - 1, onset + Math.round(sampleRate * 0.035));
  return samples.slice(cut);
}

function trimReleaseClick(samples, sampleRate, noiseRms, noiseHf) {
  if (samples.length === 0) return samples;
  const peak = peakOf(samples);
  const guard = Math.min(samples.length, Math.round((sampleRate * 160) / 1000));
  const from = samples.length - guard;
  const onset = findTransient(samples, from, samples.length, sampleRate, noiseRms, noiseHf, peak);
  if (onset < 0) return samples;
  // A final /t/ burst has the vowel right behind it, only a stop closure away;
  // a key-up click lands after the speaker has already gone quiet.
  const level = speechLevelOf(peak, noiseRms);
  if (hasSpeechNear(samples, onset, sampleRate, CLICK_LOOKBACK_MS, level, "before")) {
    return samples;
  }
  const cut = Math.max(0, onset - Math.round(sampleRate * 0.008));
  return samples.slice(0, Math.max(1, cut));
}

function analyzeWindows(samples, sampleRate, windowMs) {
  const win = Math.max(1, Math.round((sampleRate * windowMs) / 1000));
  const count = Math.ceil(samples.length / win);
  const rms = new Float32Array(count);
  const hf = new Float32Array(count);
  for (let w = 0; w < count; w++) {
    const from = w * win;
    const to = Math.min(samples.length, from + win);
    let sum = 0;
    for (let i = from; i < to; i++) sum += samples[i] * samples[i];
    rms[w] = Math.sqrt(sum / Math.max(1, to - from));
    hf[w] = hfEnergy(samples, from, to);
  }
  return { win, count, rms, hf };
}

/**
 * Remove leading and trailing blank time using the pre-press noise floor.
 *
 * The loud gate finds the voiced core, then the edges walk outward on a much
 * softer gate so unvoiced consonants survive — a final /t/ is a faint burst
 * sitting behind up to 100 ms of dead-silent stop closure.
 */
function trimSilence(samples, sampleRate, noiseRms, noiseHf) {
  if (samples.length === 0) return samples;
  const { win, count, rms, hf } = analyzeWindows(samples, sampleRate, TRIM_WINDOW_MS);
  const peak = peakOf(samples);
  const loud = Math.max(noiseRms * TRIM_NOISE_MULT, peak * TRIM_PEAK_FRAC, 1e-4);
  const soft = Math.max(noiseRms * SOFT_NOISE_MULT, peak * SOFT_PEAK_FRAC, 1e-5);
  const hfGate = noiseHf * SOFT_HF_MULT;

  let firstWin = -1;
  let lastWin = -1;
  for (let w = 0; w < count; w++) {
    if (rms[w] >= loud) {
      if (firstWin < 0) firstWin = w;
      lastWin = w;
    }
  }
  if (firstWin < 0) return samples.slice(0, Math.min(samples.length, win));

  const active = (w) => rms[w] >= soft || (hf[w] >= hfGate && rms[w] >= noiseRms * 1.5);

  let startWin = firstWin;
  const maxBack = Math.ceil(HEAD_HANGOVER_MS / TRIM_WINDOW_MS);
  const headGap = Math.ceil(HEAD_GAP_MS / TRIM_WINDOW_MS);
  let gap = 0;
  for (let w = firstWin - 1; w >= 0 && firstWin - w <= maxBack; w--) {
    if (active(w)) {
      startWin = w;
      gap = 0;
    } else if (++gap > headGap) break;
  }

  let endWin = lastWin;
  const maxFwd = Math.ceil(TAIL_HANGOVER_MS / TRIM_WINDOW_MS);
  const tailGap = Math.ceil(TAIL_GAP_MS / TRIM_WINDOW_MS);
  gap = 0;
  for (let w = lastWin + 1; w < count && w - lastWin <= maxFwd; w++) {
    if (active(w)) {
      endWin = w;
      gap = 0;
    } else if (++gap > tailGap) break;
  }

  const leadPad = Math.round((sampleRate * LEAD_PAD_MS) / 1000);
  const trailPad = Math.round((sampleRate * TRAIL_PAD_MS) / 1000);
  const a = Math.max(0, startWin * win - leadPad);
  const b = Math.min(samples.length, (endWin + 1) * win + trailPad);
  return samples.slice(a, b);
}

function applyFades(samples, sampleRate, fadeMs) {
  const n = Math.min(samples.length, Math.round((sampleRate * fadeMs) / 1000));
  if (n <= 1) return;
  for (let i = 0; i < n; i++) {
    const g = 0.5 * (1 - Math.cos((Math.PI * i) / (n - 1)));
    samples[i] *= g;
    samples[samples.length - 1 - i] *= g;
  }
}
