#!/usr/bin/env python3
"""Loudness-normalise every clip under `Resources/Audio` to one baseline level.

The assets arrived from several sources (macOS `say`, the Tools/Record browser
recorder, stock FX packs, music) and most had been peak-normalised, which says
nothing about how loud they actually sound: a plosive letter cue and a sustained
music bed can both touch 0 dBFS while differing by 20 LU of perceived loudness.

This script measures each clip's loudness to ITU-R BS.1770 and applies a fixed
gain so every asset shares one baseline. Relative balance between categories
stays where it belongs — in `SoundEffectsController` / `BackgroundMusicController`,
which scale phonetics, ambience, lightsaber FX and music against each other at
playback time. Those scales were tuned against the existing spread of assets, so
the target sits near the current median and the mix keeps its character.

Usage:
    scripts/normalise_audio.py --dry-run     # report only, touch nothing
    scripts/normalise_audio.py               # normalise in place
    scripts/normalise_audio.py --target -18  # different baseline

Requires ffmpeg/ffprobe (`brew install ffmpeg`).
"""

from __future__ import annotations

import argparse
import concurrent.futures
import math
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from paths import AUDIO

AUDIO_EXTS = {".m4a", ".mp3", ".wav", ".caf", ".aiff"}

# Baseline loudness. Chosen near the median of the original assets so the
# playback mix scales keep working, and low enough that only a handful of very
# peaky clips need any limiting to stay under the ceiling.
DEFAULT_TARGET_LUFS = -20.0

# True-peak ceiling. 33 of the original clips exceeded 0 dBTP (peak-normalised to
# full scale, so inter-sample peaks clipped on playback); this leaves headroom.
DEFAULT_CEILING_DBTP = -1.0

# Verification retries. Limiting lowers loudness and the AAC encoder can nudge
# peaks, so we re-measure the result and correct the gain rather than trusting
# the first render.
MAX_PASSES = 5
VERIFY_TOLERANCE_LU = 0.5
PEAK_TOLERANCE_DB = 0.1

# A clip already this close to target and under the ceiling is left alone. It
# matches the verification tolerance on purpose: re-encoding lossy audio costs
# quality, so the script must not rewrite clips it would accept as correct, and
# a second run over a normalised library is then a no-op.
SKIP_TOLERANCE_LU = VERIFY_TOLERANCE_LU

# The limiter works on sample peak, so it aims this far below the true-peak
# ceiling to leave room for inter-sample peaks.
LIMITER_MARGIN_DB = 0.6

# Peak limiting budget. A limiter only reshapes the samples above its threshold,
# so how much a clip can absorb depends on how much of its waveform sits up
# there: an isolated transient (a footstep, a jump whoosh) can lose 9 dB off the
# spike inaudibly, while a dense crackling loop would just get squashed. Each
# clip gets as much limiting as keeps the reshaped share of its waveform under
# LIMIT_AFFECTED_FRACTION. Clips that still cannot reach target are left quieter
# and listed in the report rather than crushed.
MAX_LIMITING_DB = 9.0
LIMIT_AFFECTED_FRACTION = 0.02

# --- BS.1770 K-weighting, used only for clips too short for ffmpeg to gate. ---
KWEIGHT_HZ = 48000
_STAGE1 = (
    "biquad=b0=1.53512485958697:b1=-2.69169618940638:b2=1.19839281085285"
    ":a0=1:a1=-1.69065929318241:a2=0.73248077421585"
)
_STAGE2 = "biquad=b0=1.0:b1=-2.0:b2=1.0:a0=1:a1=-1.99004745483398:a2=0.99007225036621"
KWEIGHT_CHAIN = f"aresample={KWEIGHT_HZ}:resampler=soxr,{_STAGE1},{_STAGE2}"
LUFS_OFFSET = -0.691

# Silence gate for finding the active region of a short clip. Well below any real
# content, above the noise floor of the TTS renders.
SILENCE_THRESHOLD_DB = -50

# The K-weighted RMS path reads slightly lower than ffmpeg's gated integrated
# loudness (measured across this library: ~0.3 LU on sub-second clips). Correcting
# it keeps short clips from being pushed louder than everything else.
UNGATED_CALIBRATION_LU = 0.3

# ffmpeg's ebur128 reports -70 LUFS when a clip has no complete 400ms block.
EBUR128_FLOOR = -70.0

# Re-encode bitrate policy. Applying gain means decoding and re-encoding, and many
# of these clips were encoded very frugally (some at 16-30 kbps), where a second
# generation measurably degrades them. Measuring re-encode error against a
# gain-only reference across this library, quality climbs steeply up to roughly
# 2 bits per sample per channel and flattens after, so that is the floor. Sources
# already above it keep their own bitrate.
BITRATE_BITS_PER_SAMPLE = 2.0
BITRATE_CAP = 320_000

# Delivery ceiling for MP3, which is where the music beds live and therefore most
# of the bundle. 44.1 kHz at 192 kbps is transparent for this material, cuts the
# 320 kbps beds by 40%, and shrinks the PCM the player holds for a 48 kHz file.
MP3_MAX_SAMPLE_RATE = 44_100
MP3_MAX_BITRATE = 192_000


@dataclass
class Clip:
    path: Path
    duration: float
    codec: str
    bitrate: int
    sample_rate: int
    channels: int
    lufs: float
    true_peak: float
    gated: bool

    @property
    def label(self) -> str:
        try:
            return str(self.path.relative_to(AUDIO))
        except ValueError:
            return self.path.name


@dataclass
class Result:
    clip: Clip
    gain_db: float
    # How much the clip's crest factor shrank, i.e. how much the limiter actually
    # reshaped it. Planned rather than measured for a dry run.
    squash_db: float
    final_lufs: float | None
    final_peak: float | None
    action: str
    note: str = ""


def run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    return proc.stdout + proc.stderr


def ffmpeg_analyse(path: Path, filters: str) -> str:
    return run(["ffmpeg", "-nostdin", "-hide_banner", "-nostats",
                "-i", str(path), "-map", "a:0", "-af", filters, "-f", "null", "-"])


def probe(path: Path) -> dict[str, str]:
    out = run(["ffprobe", "-v", "error", "-select_streams", "a:0",
               "-show_entries", "stream=codec_name,bit_rate,sample_rate,channels",
               "-show_entries", "format=duration,bit_rate",
               "-of", "default=nw=1", str(path)])
    fields: dict[str, str] = {}
    for line in out.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields.setdefault(key, value)
    return fields


def ebur128(path: Path) -> tuple[float | None, float | None]:
    """Gated integrated loudness (LUFS) and true peak (dBTP), or None if ungateable."""
    out = ffmpeg_analyse(path, "ebur128=peak=true")
    summary = out.split("Summary:")[-1] if "Summary:" in out else ""
    match = re.search(r"^\s*I:\s*(-?[\d.]+)", summary, re.M)
    loudness = float(match.group(1)) if match else None
    if loudness is not None and loudness <= EBUR128_FLOOR:
        loudness = None
    peaks = re.findall(r"Peak:\s*(-?[\d.]+)", summary)
    return loudness, (float(peaks[-1]) if peaks else None)


def kweighted_lufs(path: Path) -> float | None:
    """Loudness of a clip's active region, for clips ffmpeg cannot gate."""
    trim = (f"silenceremove=start_periods=1:start_silence=0"
            f":start_threshold={SILENCE_THRESHOLD_DB}dB"
            f":stop_periods=-1:stop_silence=0.02"
            f":stop_threshold={SILENCE_THRESHOLD_DB}dB:detection=rms")
    chain = f"{KWEIGHT_CHAIN},{trim},astats=measure_perchannel=none:measure_overall=RMS_level"
    out = ffmpeg_analyse(path, chain)
    match = re.search(r"RMS level dB:\s*(-?[\d.]+|-?inf)", out)
    if not match or "inf" in match.group(1):
        return None
    rms = float(match.group(1))
    channels = 1
    ch = re.search(r"Number of channels:\s*(\d+)", out)
    if ch:
        channels = int(ch.group(1))
    # astats power-averages channels; BS.1770 sums them (G = 1.0 for L/R).
    summed = rms + (10 * math.log10(channels) if channels > 1 else 0.0)
    return summed + LUFS_OFFSET + UNGATED_CALIBRATION_LU


def limiting_budget(path: Path) -> float:
    """How much peak limiting this waveform can absorb without being squashed.

    Returns the largest reduction, in dB below the clip's own peak, that still
    leaves at most `LIMIT_AFFECTED_FRACTION` of the samples above the threshold.
    """
    proc = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-map", "a:0",
         "-f", "f32le", "-c:a", "pcm_f32le", "-ac", "1", "-"],
        stdin=subprocess.DEVNULL, capture_output=True)
    if proc.returncode != 0 or not proc.stdout:
        return 0.0

    samples = np.abs(np.frombuffer(proc.stdout, dtype=np.float32).astype(np.float64))
    peak = samples.max() if samples.size else 0.0
    if peak <= 0:
        return 0.0
    # The share of the waveform above `peak - budget`, for each candidate budget.
    quietest_kept = np.quantile(samples, 1.0 - LIMIT_AFFECTED_FRACTION)
    if quietest_kept <= 0:
        return MAX_LIMITING_DB
    return float(min(MAX_LIMITING_DB, max(0.0, 20 * math.log10(peak / quietest_kept))))


def sample_peak_dbfs(path: Path) -> float:
    out = ffmpeg_analyse(path, "volumedetect")
    match = re.search(r"max_volume:\s*(-?[\d.]+)", out)
    return float(match.group(1)) if match else 0.0


def measure(path: Path) -> Clip | None:
    info = probe(path)
    try:
        duration = float(info.get("duration", ""))
    except ValueError:
        return None

    loudness, peak = ebur128(path)
    gated = loudness is not None
    if loudness is None:
        loudness = kweighted_lufs(path)
    if loudness is None:
        return None
    if peak is None:
        peak = sample_peak_dbfs(path)

    return Clip(
        path=path,
        duration=duration,
        codec=info.get("codec_name", ""),
        bitrate=int(info.get("bit_rate") or 0),
        sample_rate=int(info.get("sample_rate") or 48000),
        channels=int(info.get("channels") or 1),
        lufs=loudness,
        true_peak=peak,
        gated=gated,
    )


def is_mp3(clip: Clip) -> bool:
    return clip.path.suffix.lower() == ".mp3"


def output_sample_rate(clip: Clip) -> int:
    if is_mp3(clip):
        return min(clip.sample_rate, MP3_MAX_SAMPLE_RATE)
    return clip.sample_rate


def target_bitrate(clip: Clip) -> int:
    floor = int(BITRATE_BITS_PER_SAMPLE * output_sample_rate(clip) * clip.channels)
    bitrate = min(max(clip.bitrate, floor), BITRATE_CAP)
    if is_mp3(clip):
        bitrate = min(bitrate, MP3_MAX_BITRATE)
    return bitrate


def needs_reformat(clip: Clip) -> bool:
    """True when the clip ships above the delivery format, regardless of loudness.

    A clip whose level already happens to sit on target still has to be re-encoded
    if it is above the sample rate or bitrate we want to ship.
    """
    return (output_sample_rate(clip) != clip.sample_rate
            or target_bitrate(clip) < clip.bitrate)


def encoder_args(clip: Clip) -> list[str]:
    if is_mp3(clip):
        codec = ["-c:a", "libmp3lame"]
    else:
        # Apple's AudioToolbox AAC beats ffmpeg's native encoder, especially at the
        # low bitrates some of these clips use.
        codec = ["-c:a", "aac_at"]
    return codec + ["-b:a", str(target_bitrate(clip)),
                    "-ar", str(output_sample_rate(clip)), "-ac", str(clip.channels)]


def render(clip: Clip, gain_db: float, limit_to_dbfs: float | None, out_path: Path) -> bool:
    """Write `clip` with `gain_db` applied, optionally limited, to `out_path`."""
    chain = [f"volume={gain_db:.3f}dB"]
    rate = output_sample_rate(clip)
    if rate != clip.sample_rate:
        # Resample before limiting so the limiter works on the sample grid that
        # actually ships. soxr because 48k -> 44.1k is not a whole-number ratio.
        chain.append(f"aresample={rate}:resampler=soxr:precision=28")
    if limit_to_dbfs is not None:
        limit = min(1.0, 10 ** (limit_to_dbfs / 20))
        # `level=disabled` stops alimiter making up gain; `latency` keeps the
        # lookahead from time-shifting the clip.
        chain.append(f"alimiter=limit={limit:.6f}:attack=5:release=50"
                     f":level=disabled:latency=1")
    cmd = ["ffmpeg", "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
           "-i", str(clip.path), "-map", "a:0", "-af", ",".join(chain),
           *encoder_args(clip), "-map_metadata", "0", str(out_path)]
    proc = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True)
    if proc.returncode != 0 or not out_path.exists() or out_path.stat().st_size == 0:
        sys.stderr.write(f"  ffmpeg failed for {clip.label}: {proc.stderr.strip()[:300]}\n")
        return False
    return True


def normalise(clip: Clip, target: float, ceiling: float, dry_run: bool) -> Result:
    wanted = target - clip.lufs
    headroom = ceiling - clip.true_peak

    reformat = needs_reformat(clip)
    if (abs(wanted) <= SKIP_TOLERANCE_LU
            and clip.true_peak <= ceiling + PEAK_TOLERANCE_DB
            and not reformat):
        return Result(clip, 0.0, 0.0, clip.lufs, clip.true_peak, "unchanged",
                      "already on target")

    gain = wanted
    if wanted > headroom:
        # Reaching target means limiting; take only what this waveform can absorb.
        gain = min(wanted, headroom + limiting_budget(clip.path))
    capped = gain < wanted - 1e-6

    if dry_run:
        return Result(clip, gain, max(0.0, gain - headroom), None, None, "planned")

    suffix = clip.path.suffix
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / f"render{suffix}"
        keep = Path(tmp) / f"best{suffix}"
        applied = gain
        # Extra limiter tightening, raised when a render's measured true peak still
        # breaches the ceiling — the AAC encoder can lift peaks by over a dB.
        tightening = 0.0
        previous_error: float | None = None
        best: tuple[tuple[bool, float], Clip, float] | None = None

        for _ in range(MAX_PASSES):
            needs_limiter = clip.true_peak + applied > ceiling or tightening > 0
            limit = ceiling - LIMITER_MARGIN_DB - tightening if needs_limiter else None
            if not render(clip, applied, limit, out):
                return Result(clip, applied, 0.0, None, None, "failed", "ffmpeg error")

            check = measure(out)
            if check is None:
                return Result(clip, applied, 0.0, None, None, "failed", "unmeasurable")

            legal = check.true_peak <= ceiling + PEAK_TOLERANCE_DB
            error = target - check.lufs
            # Prefer renders that respect the ceiling, then those closest to target.
            rank = (not legal, abs(error))
            if best is None or rank < best[0]:
                best = (rank, check, applied)
                shutil.copy2(out, keep)

            if legal and abs(error) <= VERIFY_TOLERANCE_LU:
                break
            if not legal:
                tightening += (check.true_peak - ceiling) + 0.2
                continue
            if error > 0 and capped:
                break  # already at the limiting budget; leave it below target
            if previous_error is not None and abs(error) > abs(previous_error) - 0.1:
                break  # more gain is being eaten by the limiter, not helping
            previous_error = error
            applied += error

        assert best is not None
        _, check, applied = best

        # Never spend a re-encode that does not earn it. A clip whose peaks stop it
        # reaching target gains nothing from another generation of lossy encoding
        # and more limiting, so leave it as it is — this is what makes repeated
        # runs over an already-normalised library safe.
        closer = abs(target - check.lufs) < abs(target - clip.lufs) - 0.1
        fixes_peak = (clip.true_peak > ceiling + PEAK_TOLERANCE_DB
                      and check.true_peak <= ceiling + PEAK_TOLERANCE_DB)
        if not closer and not fixes_peak and not reformat:
            return Result(clip, 0.0, 0.0, clip.lufs, clip.true_peak, "unchanged",
                          "as close to target as its peaks allow")

        mode = clip.path.stat().st_mode & 0o7777
        shutil.copy2(keep, clip.path)
        clip.path.chmod(mode)

    note = ""
    if abs(target - check.lufs) > VERIFY_TOLERANCE_LU:
        note = f"{target - check.lufs:+.1f} LU off target (peak-bound)"
    if check.true_peak > ceiling + PEAK_TOLERANCE_DB:
        note = (note + "; " if note else "") + f"peak {check.true_peak:+.1f} dBTP over ceiling"
    squash = max(0.0, (clip.true_peak - clip.lufs) - (check.true_peak - check.lufs))
    return Result(clip, applied, squash, check.lufs, check.true_peak, "normalised", note)


def find_audio(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*")
                  if p.is_file() and p.suffix.lower() in AUDIO_EXTS)


def spread(values: list[float]) -> str:
    ordered = sorted(values)
    n = len(ordered)
    return (f"min={ordered[0]:6.1f}  p10={ordered[n // 10]:6.1f}  "
            f"median={ordered[n // 2]:6.1f}  p90={ordered[9 * n // 10]:6.1f}  "
            f"max={ordered[-1]:6.1f}   spread={ordered[-1] - ordered[0]:.1f} LU")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--audio-dir", type=Path, default=AUDIO)
    parser.add_argument("--target", type=float, default=DEFAULT_TARGET_LUFS,
                        help=f"baseline loudness in LUFS (default {DEFAULT_TARGET_LUFS})")
    parser.add_argument("--ceiling", type=float, default=DEFAULT_CEILING_DBTP,
                        help=f"true-peak ceiling in dBTP (default {DEFAULT_CEILING_DBTP})")
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--verbose", action="store_true", help="list every clip")
    args = parser.parse_args()

    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        sys.stderr.write("ffmpeg and ffprobe are required (brew install ffmpeg)\n")
        return 1

    files = find_audio(args.audio_dir)
    if not files:
        sys.stderr.write(f"no audio found under {args.audio_dir}\n")
        return 1

    print(f"measuring {len(files)} clips under {args.audio_dir}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        clips = [c for c in pool.map(measure, files) if c is not None]
    if len(clips) != len(files):
        print(f"warning: {len(files) - len(clips)} clip(s) could not be measured")

    print(f"  before: {spread([c.lufs for c in clips])}")
    ungated = sum(1 for c in clips if not c.gated)
    if ungated:
        print(f"  ({ungated} clips shorter than one 400ms gating block, "
              f"measured as K-weighted RMS over their active region)")
    hot = [c for c in clips if c.true_peak > args.ceiling + PEAK_TOLERANCE_DB]
    print(f"  {len(hot)} clip(s) above the {args.ceiling:+.1f} dBTP ceiling, "
          f"{sum(1 for c in clips if c.true_peak > 0)} of them clipping over 0 dBTP")

    verb = "would normalise" if args.dry_run else "normalising"
    print(f"\n{verb} to {args.target:+.1f} LUFS / {args.ceiling:+.1f} dBTP")

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(
            lambda c: normalise(c, args.target, args.ceiling, args.dry_run), clips))

    changed = [r for r in results if r.action in ("normalised", "planned")]
    unchanged = [r for r in results if r.action == "unchanged"]
    failed = [r for r in results if r.action == "failed"]
    limited = [r for r in changed if r.squash_db > 0.05]

    if args.verbose:
        print()
        for r in sorted(results, key=lambda r: r.clip.label):
            final = f"-> {r.final_lufs:6.1f} LUFS {r.final_peak:+5.1f} dBTP" if r.final_lufs else ""
            lim = f" crest -{r.squash_db:.1f}dB" if r.squash_db > 0.05 else ""
            print(f"  {r.clip.label:58} {r.clip.lufs:6.1f} {r.gain_db:+6.1f}dB "
                  f"{final}{lim} {r.note}")

    print(f"\n  {len(changed)} changed, {len(unchanged)} already on target, "
          f"{len(failed)} failed")
    if limited:
        print(f"  {len(limited)} needed peak limiting; largest crest reduction "
              f"{max(r.squash_db for r in limited):.1f} dB")
    off = [r for r in results if "off target" in r.note]
    if off:
        print(f"  {len(off)} left below target rather than squashing their transients:")
        for r in sorted(off, key=lambda r: r.clip.label):
            print(f"    {r.clip.label:58} {r.note}")
    over = [r for r in results if "over ceiling" in r.note]
    if over:
        print(f"  {len(over)} could not be held under the ceiling:")
        for r in sorted(over, key=lambda r: r.clip.label):
            print(f"    {r.clip.label:58} {r.note}")
    for r in failed:
        print(f"    failed: {r.clip.label}: {r.note}")

    if not args.dry_run:
        finals = [r.final_lufs for r in results if r.final_lufs is not None]
        if finals:
            print(f"\n  after:  {spread(finals)}")
        peaks = [r.final_peak for r in results if r.final_peak is not None]
        if peaks:
            over = sum(1 for p in peaks if p > args.ceiling + 0.1)
            print(f"  peaks:  max={max(peaks):+.1f} dBTP, "
                  f"{over} above ceiling")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
