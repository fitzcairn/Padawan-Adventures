/**
 * Minimal take cleanup: keyboard click removal, leading/trailing silence trim,
 * tiny edge fades, WAV encode.
 *
 * Deliberately does NOT EQ, denoise, compress, or otherwise process the spoken
 * word — tone adjustments will be layered back in later.
 */

const TRIM_WINDOW_MS = 8;
/** Little pad before speech so plosives aren't clipped. */
const LEAD_PAD_MS = 6;
/** Extra tail so word endings aren't clipped by silence trim / release guard. */
const TRAIL_PAD_MS = 45;
/** Speech must clear this fraction of peak (tighter = less leading hush). */
const TRIM_PEAK_FRAC = 0.07;
/** Speech must clear this multiple of the pre-press noise floor. */
const TRIM_NOISE_MULT = 5.5;
/** Fixed discard at hold edges — Space key travel / bounce. */
const PRESS_GUARD_MS = 85;
const RELEASE_GUARD_MS = 70;
const FADE_MS = 8;
const QUIET_PEAK = 1e-4;

/**
 * @param {Float32Array} samples
 * @param {Float32Array} noiseSamples pre-press room noise (for silence gate)
 * @param {number} sampleRate
 * @returns {{ samples: Float32Array, tooQuiet: boolean }}
 */
export function cleanup(samples, noiseSamples, sampleRate) {
  let out = Float32Array.from(samples);

  // 1) Hard edge guards — most reliable against Space down/up clicks.
  out = dropEdgeGuards(out, sampleRate, PRESS_GUARD_MS, RELEASE_GUARD_MS);

  // 2) Smart pass for leftover click spikes (bounce, late key noise).
  out = trimPressClick(out, sampleRate);
  out = trimReleaseClick(out, sampleRate);

  // 3) Trim blank time using the real pre-press noise floor.
  const noiseRms = Math.max(rmsOf(noiseSamples), 1e-5);
  out = trimSilence(out, sampleRate, noiseRms);

  applyFades(out, sampleRate, FADE_MS);

  const peak = peakOf(out);
  return { samples: out, tooQuiet: peak < QUIET_PEAK };
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
 * Find a short mechanical click in [from, to).
 * @param {"start"|"end"} side
 * @returns {number} sample index of click onset, or -1
 */
function findClickOnset(samples, from, to, sampleRate, peak, side) {
  const len = to - from;
  if (len < 64) return -1;

  let baseFrom;
  let baseTo;
  let searchFrom;
  let searchTo;
  if (side === "start") {
    baseFrom = from;
    baseTo = from + Math.min(len, Math.round(sampleRate * 0.05));
    searchFrom = from;
    searchTo = to;
  } else {
    baseFrom = from;
    baseTo = from + Math.floor(len * 0.5);
    searchFrom = from + Math.floor(len * 0.4);
    searchTo = to;
  }

  let baseSum = 0;
  let baseN = 0;
  for (let i = baseFrom; i < baseTo; i++) {
    baseSum += samples[i] * samples[i];
    baseN += 1;
  }
  const baseRms = Math.sqrt(baseSum / Math.max(1, baseN)) + 1e-8;
  const baseHf = hfEnergy(samples, baseFrom, baseTo) + 1e-12;
  // Lower peak fraction so quieter key clicks still register vs loud speech.
  const ampThresh = Math.max(baseRms * 4.5, peak * 0.12);
  const hfThresh = baseHf * 8;

  const win = Math.max(1, Math.round(sampleRate * 0.003));
  for (let i = searchFrom; i + win < searchTo; i += win) {
    let localPeak = 0;
    for (let j = i; j < i + win; j++) {
      const a = Math.abs(samples[j]);
      if (a > localPeak) localPeak = a;
    }
    const hf = hfEnergy(samples, i, Math.min(searchTo, i + win * 3));
    const ampHit = localPeak >= ampThresh;
    const hfHit = hf >= hfThresh && localPeak >= baseRms * 3;
    if (!ampHit && !hfHit) continue;

    // Clicks die fast; sustained speech keeps energy after the peak.
    const after = Math.min(searchTo, i + Math.round(sampleRate * 0.025));
    let afterSum = 0;
    let afterN = 0;
    for (let j = i + win; j < after; j++) {
      afterSum += samples[j] * samples[j];
      afterN += 1;
    }
    const afterRms = Math.sqrt(afterSum / Math.max(1, afterN));
    if (afterRms > localPeak * 0.5 && localPeak < peak * 0.5 && !hfHit) {
      continue;
    }
    return i;
  }
  return -1;
}

function trimPressClick(samples, sampleRate) {
  if (samples.length === 0) return samples;
  // After the hard guard, only a short head remains to scan.
  const guardMs = 180;
  const guard = Math.min(samples.length, Math.round((sampleRate * guardMs) / 1000));
  const peak = peakOf(samples);
  const onset = findClickOnset(samples, 0, guard, sampleRate, peak, "start");
  if (onset < 0) return samples;
  const cut = Math.min(
    samples.length - 1,
    onset + Math.round(sampleRate * 0.04)
  );
  return samples.slice(cut);
}

function trimReleaseClick(samples, sampleRate) {
  if (samples.length === 0) return samples;
  const guardMs = 220;
  const guard = Math.min(samples.length, Math.round((sampleRate * guardMs) / 1000));
  const start = samples.length - guard;
  const peak = peakOf(samples);
  const onset = findClickOnset(samples, start, samples.length, sampleRate, peak, "end");
  if (onset < 0) return samples;
  const cut = Math.max(0, onset - Math.round(sampleRate * 0.01));
  return samples.slice(0, Math.max(1, cut));
}

/**
 * Remove leading and trailing blank time using the pre-press noise floor.
 */
function trimSilence(samples, sampleRate, noiseRms) {
  if (samples.length === 0) return samples;
  const win = Math.max(1, Math.round((sampleRate * TRIM_WINDOW_MS) / 1000));
  const leadPad = Math.round((sampleRate * LEAD_PAD_MS) / 1000);
  const trailPad = Math.round((sampleRate * TRAIL_PAD_MS) / 1000);
  const peak = peakOf(samples);
  const threshold = Math.max(noiseRms * TRIM_NOISE_MULT, peak * TRIM_PEAK_FRAC, 1e-4);

  let firstWin = -1;
  let lastWin = -1;
  for (let start = 0; start < samples.length; start += win) {
    const end = Math.min(samples.length, start + win);
    let sum = 0;
    for (let i = start; i < end; i++) sum += samples[i] * samples[i];
    const rms = Math.sqrt(sum / (end - start));
    if (rms >= threshold) {
      if (firstWin < 0) firstWin = start;
      lastWin = end;
    }
  }
  if (firstWin < 0) {
    return samples.slice(0, Math.min(samples.length, win));
  }

  let first = firstWin;
  while (first < lastWin && Math.abs(samples[first]) < threshold) first += 1;
  let last = lastWin - 1;
  while (last > first && Math.abs(samples[last]) < threshold) last -= 1;

  const a = Math.max(0, first - leadPad);
  const b = Math.min(samples.length, last + 1 + trailPad);
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
