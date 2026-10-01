"""Cut the explosions out of a MAME recording made with trace_noise.lua and measure them.

    uv run --with numpy python3 noise_analyse.py noise.wav noise_events.txt build/noise

Writes one reference WAV per isolated explosion (for listening and analysis
only; they are MAME's output and stay in build/) and prints, for each, the
loudness envelope and where its energy sits in the spectrum.
"""

import sys
import wave
from pathlib import Path

import numpy as np

CLIP = 4.5  # seconds kept per explosion


def main() -> None:
    w = wave.open(sys.argv[1])
    rate, ch = w.getframerate(), w.getnchannels()
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, ch).mean(axis=1)
    times = [float(line.split()[0]) for line in open(sys.argv[2]) if line.split()[1] == "bang"]
    out = Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    print(f"{len(times)} explosion commands; recording is {len(pcm) / rate:.0f} s at {rate} Hz, {ch} channel(s)")
    print(f"overall peak {np.abs(pcm).max():.0f} of 32768; level away from explosions "
          f"{np.sqrt((pcm[int(20 * rate):int(40 * rate)] ** 2).mean()):.1f} rms")
    env_all, spec_all = [], []
    for n, t in enumerate(times):
        nxt = times[n + 1] if n + 1 < len(times) else 1e9
        if nxt - t < CLIP:
            continue  # the next one would overlap
        clip = pcm[int(t * rate) : int((t + CLIP) * rate)]
        if len(clip) < CLIP * rate:
            continue
        win = rate // 100  # 10 ms
        env = np.sqrt((clip[: len(clip) // win * win].reshape(-1, win) ** 2).mean(axis=1))
        peak = env.max()
        over = np.nonzero(env > peak / 100)[0]  # within 40 dB of the peak
        start, end = over[0] * 10, over[-1] * 10
        loud = clip[int(start / 1000 * rate) : int(end / 1000 * rate)]
        spec = np.abs(np.fft.rfft(loud * np.hanning(len(loud)))) ** 2
        freqs = np.fft.rfftfreq(len(loud), 1 / rate)
        cum = np.cumsum(spec) / spec.sum()
        f10, f50, f90 = (freqs[np.searchsorted(cum, q)] for q in (0.1, 0.5, 0.9))
        label = "boot_sound_test" if t < 20 else f"explosion_{n:02d}"
        with wave.open(str(out / f"reference_{label}.wav"), "wb") as o:
            o.setnchannels(1)
            o.setsampwidth(2)
            o.setframerate(rate)
            o.writeframes(clip.astype("<i2").tobytes())
        print(f"{label}: starts {start} ms after the command, audible for {end - start} ms, peak rms {peak:.0f}; "
              f"energy 10/50/90% below {f10:.0f}/{f50:.0f}/{f90:.0f} Hz")
        if t > 20:
            env_all.append(env[over[0] :][:400])
            band = [spec[(freqs >= lo) & (freqs < hi)].sum() / spec.sum() for lo, hi in BANDS]
            spec_all.append(band)
    env = np.mean([np.pad(e, (0, 400 - len(e))) for e in env_all], axis=0)
    print("\naverage loudness every 100 ms, percent of peak:")
    print("  " + " ".join(f"{100 * v / env.max():.0f}" for v in env[::10][:40]))
    spread = np.std([e[:100].sum() for e in env_all]) / np.mean([e[:100].sum() for e in env_all])
    print(f"explosions differ from each other by {100 * spread:.0f}% in total loudness")
    print("share of energy per band:")
    for (lo, hi), share in zip(BANDS, np.mean(spec_all, axis=0)):
        print(f"  {lo:5d}-{hi:<5d} Hz  {100 * share:5.1f}%")


BANDS = [(0, 100), (100, 200), (200, 400), (400, 800), (800, 1600), (1600, 3200), (3200, 6400), (6400, 24000)]

if __name__ == "__main__":
    main()
