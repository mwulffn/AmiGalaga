"""Make a fighter explosion of our own that matches MAME's, and compare.

    uv run --with numpy python3 noise_match.py build/noise

Reads the reference clips written by noise_analyse.py, measures their
average spectrum and loudness envelope, and builds three candidates from
random noise of our own (nothing from the recording is copied):

  match_ideal.wav         shaped noise at full quality: what we are aiming at
  match_amiga_sample.wav  an 8-bit sample at 4 kHz with the decay baked in,
                          as Paula would play it (about 11 KB)
  match_amiga_loop.wav    a 2 KB looped noise sample with the decay done by
                          Paula's volume register, set once per frame
  compare.wav             reference, then the three candidates, 0.6 s apart

and the two Amiga samples themselves as raw signed 8-bit files.
"""

import sys
import wave
from pathlib import Path

import numpy as np

RATE = 48000
AMIGA_RATE = 4000  # sample rate of the Amiga versions
LOOP = 2048  # bytes in the looped sample


def load(path: Path) -> np.ndarray:
    w = wave.open(str(path))
    return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float)


def save(path: Path, x: np.ndarray) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(np.clip(x, -32767, 32767).astype("<i2").tobytes())


def envelope(x: np.ndarray, ms: int = 10) -> np.ndarray:
    win = RATE * ms // 1000
    return np.sqrt((x[: len(x) // win * win].reshape(-1, win) ** 2).mean(axis=1))


def shaped_noise(n: int, rate: int, freqs: np.ndarray, power: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """n samples of noise with the given power spectrum; periodic over n, unit rms."""
    f = np.fft.rfftfreq(n, 1 / rate)
    mag = np.sqrt(np.interp(f, freqs, power, right=0.0))
    spec = mag * np.exp(2j * np.pi * rng.random(len(f)))
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / np.sqrt((x**2).mean())


def paula(sample: np.ndarray, rate: int, seconds: float) -> np.ndarray:
    """Play an 8-bit sample the way an A500 would: held samples, then its fixed low-pass."""
    hold = RATE // rate
    x = np.repeat(sample.astype(float), hold)[: int(seconds * RATE)]
    a = 1 - np.exp(-2 * np.pi * 4900 / RATE)  # about 4.9 kHz, 6 dB per octave
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def bands(x: np.ndarray) -> str:
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    edges = [0, 100, 200, 400, 800, 1600, 24000]
    return " ".join(f"{100 * spec[(f >= lo) & (f < hi)].sum() / spec.sum():4.0f}" for lo, hi in zip(edges, edges[1:]))


def main() -> None:
    out = Path(sys.argv[1])
    refs = [load(p) for p in sorted(out.glob("reference_explosion_*.wav"))]
    n = min(len(r) for r in refs)
    refs = [r[:n] for r in refs]

    # Loudness: average the 10 ms envelopes, then fit "hold, then decay by half every so often".
    env = np.mean([envelope(r) for r in refs], axis=0)
    t = np.arange(len(env)) / 100
    best = None
    for hold in np.arange(0, 0.6, 0.02):
        for half in np.arange(0.2, 1.0, 0.01):
            shape = np.where(t < hold, 1.0, 0.5 ** ((t - hold) / half))
            level = (env * shape).sum() / (shape**2).sum()
            err = ((env - level * shape) ** 2).sum()
            if best is None or err < best[0]:
                best = (err, hold, half)
    _, hold, half = best
    length = (np.nonzero(env > env.max() / 100)[0][-1] + 1) / 100  # MAME's goes quiet here
    print(f"decay: full level for {hold:.2f} s, then halving every {half:.2f} s, cut off at {length:.2f} s")

    def gain_at(seconds: np.ndarray) -> np.ndarray:
        g = np.where(seconds < hold, 1.0, 0.5 ** ((seconds - hold) / half))
        return np.where(seconds > length, 0.0, g)

    # Spectrum: average power of the loud first second, smoothed over a sixth of an octave.
    seg = RATE
    power = np.mean([np.abs(np.fft.rfft(r[:seg] * np.hanning(seg))) ** 2 for r in refs], axis=0)
    freqs = np.fft.rfftfreq(seg, 1 / RATE)
    smooth = np.array([power[(freqs >= f / 1.06) & (freqs <= f * 1.06 + 1)].mean() for f in freqs])

    rng = np.random.default_rng(1981)
    total = int((length + 0.1) * RATE)
    gain = gain_at(np.arange(total) / RATE)

    ideal = shaped_noise(total, RATE, freqs, smooth, rng) * gain
    ref_rms = np.sqrt(np.mean([(r[: int(0.4 * RATE)] ** 2).mean() for r in refs]))
    scale = lambda x: x * ref_rms / np.sqrt((x[: int(0.4 * RATE)] ** 2).mean())  # noqa: E731
    ideal = scale(ideal)

    # Amiga version 1: the whole sound as one 8-bit sample.
    m = int((length + 0.05) * AMIGA_RATE)
    g = gain_at(np.arange(m) / AMIGA_RATE)
    raw = shaped_noise(m, AMIGA_RATE, freqs, smooth, rng) * g
    whole = np.round(raw / np.abs(raw).max() * 127).astype(np.int8)
    (out / "explosion_whole.raw").write_bytes(whole.tobytes())
    amiga_sample = scale(paula(whole, AMIGA_RATE, length + 0.05))

    # Amiga version 2: a short loop, Paula's 0-64 volume stepped down each level.
    loop = shaped_noise(LOOP, AMIGA_RATE, freqs, smooth, rng)
    loop8 = np.round(loop / np.abs(loop).max() * 127).astype(np.int8)
    (out / "explosion_loop.raw").write_bytes(loop8.tobytes())
    reps = int(np.ceil((length + 0.05) * AMIGA_RATE / LOOP))
    held = paula(np.tile(loop8, reps), AMIGA_RATE, length + 0.05)
    frame = np.arange(len(held)) // (RATE // 50) / 50  # volume set once per 50 Hz frame
    vol = np.round(64 * gain_at(frame))
    amiga_loop = scale(held * vol / 64)

    save(out / "match_ideal.wav", ideal)
    save(out / "match_amiga_sample.wav", amiga_sample)
    save(out / "match_amiga_loop.wav", amiga_loop)
    gap = np.zeros(int(0.6 * RATE))
    ref = refs[0][: int((length + 0.1) * RATE)]
    save(out / "compare.wav", np.concatenate([ref, gap, ideal, gap, amiga_sample, gap, amiga_loop]))

    print(f"Amiga samples: whole sound {len(whole)} bytes, loop {len(loop8)} bytes, both at {AMIGA_RATE} Hz")
    print("\nshare of energy (%) in 0-100, 100-200, 200-400, 400-800, 800-1600, above 1600 Hz:")
    for name, x in (("MAME reference", ref), ("ideal", ideal), ("Amiga whole sample", amiga_sample), ("Amiga loop", amiga_loop)):
        e = envelope(x, 300)
        print(f"  {name:19} {bands(x[:RATE])}   loudness per 0.3 s: " + " ".join(f"{v / e[0] * 100:3.0f}" for v in e[:9]))


if __name__ == "__main__":
    main()
