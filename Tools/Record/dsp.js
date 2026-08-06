/**
 * Voice cleanup: DC removal, zero-phase 80 Hz high-pass, STFT spectral
 * subtraction, RMS silence trim, fades, peak normalize, and WAV encoding.
 */
import { transform } from "./fft.js";

const FFT_SIZE = 1024;
const HOP = 256;
const HP_HZ = 80;
const HP_Q = 0.707;
const SUBTRACT_ALPHA = 2.0;
const FLOOR_BETA = 0.05;
const TRIM_WINDOW_MS = 10;
/** Keep a tiny pad so plosive attacks / releases aren't clipped. */
const TRIM_PAD_MS = 8;
/** Drop leading/trailing windows below this fraction of peak amplitude. */
const TRIM_PEAK_FRAC = 0.08;
/** Drop leading/trailing windows below this multiple of the noise floor. */
const TRIM_NOISE_MULT = 6;
const FADE_MS = 12;
const PEAK_TARGET = 0.89;
const QUIET_PEAK = 1e-4;

/**
 * @param {Float32Array} samples
 * @param {Float32Array} noiseSamples
 * @param {number} sampleRate
 * @returns {{ samples: Float32Array, tooQuiet: boolean }}
 */
export function cleanup(samples, noiseSamples, sampleRate) {
  let out = Float32Array.from(samples);
  removeDC(out);

  const hp = makeHighPass(sampleRate, HP_HZ, HP_Q);
  applyBiquadInPlace(out, hp);
  // Zero-phase: reverse, filter again, reverse back.
  reverseInPlace(out);
  applyBiquadInPlace(out, makeHighPass(sampleRate, HP_HZ, HP_Q));
  reverseInPlace(out);

  const noise = Float32Array.from(noiseSamples);
  removeDC(noise);
  applyBiquadInPlace(noise, makeHighPass(sampleRate, HP_HZ, HP_Q));
  reverseInPlace(noise);
  applyBiquadInPlace(noise, makeHighPass(sampleRate, HP_HZ, HP_Q));
  reverseInPlace(noise);

  out = spectralSubtract(out, noise);
  // Prefer the cleaned signal's own edge floor so residual denoise hiss
  // doesn't keep pre/post-roll blank time after the RMS gate.
  const noiseRms = Math.max(rmsOf(noise), edgeNoiseRms(out, sampleRate));
  out = trimSilence(out, sampleRate, noiseRms);
  applyFades(out, sampleRate, FADE_MS);

  const peak = peakOf(out);
  if (peak < QUIET_PEAK) {
    return { samples: out, tooQuiet: true };
  }
  const scale = PEAK_TARGET / peak;
  for (let i = 0; i < out.length; i++) {
    out[i] *= scale;
  }
  return { samples: out, tooQuiet: false };
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

function removeDC(samples) {
  if (samples.length === 0) return;
  let sum = 0;
  for (let i = 0; i < samples.length; i++) sum += samples[i];
  const mean = sum / samples.length;
  for (let i = 0; i < samples.length; i++) samples[i] -= mean;
}

function reverseInPlace(samples) {
  for (let i = 0, j = samples.length - 1; i < j; i++, j--) {
    const t = samples[i];
    samples[i] = samples[j];
    samples[j] = t;
  }
}

/** RBJ cookbook high-pass biquad coefficients. */
function makeHighPass(sampleRate, freq, q) {
  const w0 = (2 * Math.PI * freq) / sampleRate;
  const cos = Math.cos(w0);
  const sin = Math.sin(w0);
  const alpha = sin / (2 * q);
  const b0 = (1 + cos) / 2;
  const b1 = -(1 + cos);
  const b2 = (1 + cos) / 2;
  const a0 = 1 + alpha;
  const a1 = -2 * cos;
  const a2 = 1 - alpha;
  return {
    b0: b0 / a0,
    b1: b1 / a0,
    b2: b2 / a0,
    a1: a1 / a0,
    a2: a2 / a0,
  };
}

function applyBiquadInPlace(samples, c) {
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  for (let i = 0; i < samples.length; i++) {
    const x0 = samples[i];
    const y0 = c.b0 * x0 + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
    samples[i] = y0;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
  }
}

function hannWindow(size) {
  const w = new Float32Array(size);
  for (let i = 0; i < size; i++) {
    w[i] = 0.5 * (1 - Math.cos((2 * Math.PI * i) / (size - 1)));
  }
  return w;
}

function noiseMagnitudeProfile(noiseSamples) {
  const window = hannWindow(FFT_SIZE);
  const bins = FFT_SIZE / 2 + 1;
  const accum = new Float64Array(bins);
  let frames = 0;
  const re = new Float64Array(FFT_SIZE);
  const im = new Float64Array(FFT_SIZE);

  if (noiseSamples.length < FFT_SIZE) {
    // Pad a short noise buffer once.
    for (let i = 0; i < FFT_SIZE; i++) {
      const s = i < noiseSamples.length ? noiseSamples[i] : 0;
      re[i] = s * window[i];
      im[i] = 0;
    }
    transform(re, im, false);
    for (let k = 0; k < bins; k++) {
      accum[k] = Math.hypot(re[k], im[k]);
    }
    frames = 1;
  } else {
    for (let start = 0; start + FFT_SIZE <= noiseSamples.length; start += HOP) {
      for (let i = 0; i < FFT_SIZE; i++) {
        re[i] = noiseSamples[start + i] * window[i];
        im[i] = 0;
      }
      transform(re, im, false);
      for (let k = 0; k < bins; k++) {
        accum[k] += Math.hypot(re[k], im[k]);
      }
      frames += 1;
    }
  }

  const profile = new Float64Array(bins);
  for (let k = 0; k < bins; k++) {
    profile[k] = accum[k] / frames;
  }
  return profile;
}

function spectralSubtract(samples, noiseSamples) {
  if (samples.length === 0) return samples;
  const window = hannWindow(FFT_SIZE);
  const noiseProfile = noiseMagnitudeProfile(noiseSamples);
  const bins = FFT_SIZE / 2 + 1;

  // Pad so we process every sample.
  const pad = FFT_SIZE;
  const paddedLen = samples.length + pad;
  const padded = new Float32Array(paddedLen);
  padded.set(samples, 0);

  const outLen = paddedLen + FFT_SIZE;
  const output = new Float64Array(outLen);
  const windowSum = new Float64Array(outLen);

  const re = new Float64Array(FFT_SIZE);
  const im = new Float64Array(FFT_SIZE);

  for (let start = 0; start + FFT_SIZE <= paddedLen; start += HOP) {
    for (let i = 0; i < FFT_SIZE; i++) {
      re[i] = padded[start + i] * window[i];
      im[i] = 0;
    }
    transform(re, im, false);

    for (let k = 0; k < bins; k++) {
      const mag = Math.hypot(re[k], im[k]);
      const phase = Math.atan2(im[k], re[k]);
      const cleaned = Math.max(mag - SUBTRACT_ALPHA * noiseProfile[k], FLOOR_BETA * mag);
      re[k] = cleaned * Math.cos(phase);
      im[k] = cleaned * Math.sin(phase);
      if (k > 0 && k < FFT_SIZE / 2) {
        re[FFT_SIZE - k] = re[k];
        im[FFT_SIZE - k] = -im[k];
      }
    }
    // DC and Nyquist imag must be 0 for real signals.
    im[0] = 0;
    im[FFT_SIZE / 2] = 0;

    transform(re, im, true);

    for (let i = 0; i < FFT_SIZE; i++) {
      const w = window[i];
      output[start + i] += re[i] * w;
      windowSum[start + i] += w * w;
    }
  }

  const result = new Float32Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    const denom = windowSum[i];
    result[i] = denom < 1e-6 ? 0 : output[i] / denom;
  }
  return result;
}

function rmsOf(samples) {
  if (samples.length === 0) return 0;
  let sum = 0;
  for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
  return Math.sqrt(sum / samples.length);
}

function peakOf(samples) {
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > peak) peak = a;
  }
  return peak;
}

/** RMS of the quieter edge (first or last ~80 ms) of the cleaned buffer. */
function edgeNoiseRms(samples, sampleRate) {
  const n = Math.min(samples.length, Math.round((sampleRate * 80) / 1000));
  if (n <= 0) return 0;
  let head = 0;
  let tail = 0;
  for (let i = 0; i < n; i++) {
    head += samples[i] * samples[i];
    const t = samples[samples.length - 1 - i];
    tail += t * t;
  }
  return Math.sqrt(Math.min(head, tail) / n);
}

/**
 * Remove leading and trailing blank time. Uses RMS windows to find the
 * voiced span, then tightens to the first/last sample above threshold.
 */
function trimSilence(samples, sampleRate, noiseRms) {
  if (samples.length === 0) return samples;
  const win = Math.max(1, Math.round((sampleRate * TRIM_WINDOW_MS) / 1000));
  const pad = Math.round((sampleRate * TRIM_PAD_MS) / 1000);
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
    // All silence — keep a short center slice so encodeWav still has content.
    return samples.slice(0, Math.min(samples.length, win));
  }

  // Sample-accurate tighten inside the first/last active windows.
  let first = firstWin;
  while (first < lastWin && Math.abs(samples[first]) < threshold) first += 1;
  let last = lastWin - 1;
  while (last > first && Math.abs(samples[last]) < threshold) last -= 1;

  const a = Math.max(0, first - pad);
  const b = Math.min(samples.length, last + 1 + pad);
  return samples.slice(a, b);
}

function applyFades(samples, sampleRate, fadeMs) {
  const n = Math.min(samples.length, Math.round((sampleRate * fadeMs) / 1000));
  if (n <= 1) return;
  for (let i = 0; i < n; i++) {
    // Raised-cosine (Hann half) fade.
    const g = 0.5 * (1 - Math.cos((Math.PI * i) / (n - 1)));
    samples[i] *= g;
    samples[samples.length - 1 - i] *= g;
  }
}
