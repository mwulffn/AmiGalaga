"""Build the sound data for the Amiga player from the user's ROM set.

    python3 make_sound_data.py path/to/galaga.zip build

Writes (derived from the ROM, so not for the repository):
  snd_data.i   the driver's tables as assembler source: tracks, track
               offsets, per-sound parameters and tempo, the formation pulse
               table, and two lookup tables that turn a note byte or a pulse
               pitch into a Paula period plus waveform length
  snd_chip.bin the samples for chip RAM: the 8 waveforms in lengths 32, 16
               and 8, then the explosion noise loop

The explosion loop is our own noise, shaped to a spectrum measured from
MAME's noise chip (sound/noise_analyse.py); nothing in it comes from the ROM.
"""

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "sound"))
import galaga_sound as S  # noqa: E402
import native as N  # noqa: E402

PAULA_CLOCK = 3546895  # PAL
NOISE_RATE, NOISE_LEN = 8000, 4000
NOISE_ROUNDS, NOISE_CREST = 12, 1.15  # peak flattening: rounds, clip level in rms
# Relative power of the arcade's fighter explosion at these frequencies (Hz).
SPECTRUM = [
    (40, 0.0186), (46, 0.0250), (53, 0.0260), (62, 0.0422), (71, 0.0685), (83, 0.1006), (95, 0.1240),
    (110, 0.1894), (127, 0.4062), (147, 0.7816), (170, 1.0000), (197, 0.7977), (228, 0.4183),
    (263, 0.2355), (304, 0.1828), (352, 0.1410), (406, 0.1247), (470, 0.1019), (543, 0.0745),
    (628, 0.0418), (725, 0.0198), (838, 0.0103), (969, 0.0053), (1120, 0.0029), (1295, 0.0016),
    (1497, 0.0008), (1730, 0.0004), (2000, 0.0002),
]  # fmt: skip


def paula_entry(freq16: int) -> int:
    """Chip frequency (the 16 bits the driver sets) -> Paula period, with the
    waveform length to use in bits 12-13 (0 = 32 samples, 1 = 16, 2 = 8).

    The shortest copy is chosen so the period never drops below 200, which
    keeps the pitch within a quarter of a percent. 0 means silent.
    """
    if freq16 == 0:
        return 0
    hz = freq16 * 16 * S.CHIP_HZ / (1 << 20)
    for code, n in enumerate((32, 16, 8)):
        period = round(PAULA_CLOCK / (hz * n))
        if period > 0xFFF:
            return 0  # below anything the game plays
        if period >= 200 or n == 8:
            return max(period, 124) | code << 12
    return 0


def noise_loop() -> bytes:
    """A seamless loop of noise with the measured spectrum, signed 8-bit.

    Plain random-phase noise has rare tall peaks, so scaled to fit 8 bits it
    is quiet on average. A few rounds of "clip the peaks, then put the
    spectrum back" keep the same spectrum but flatten the peaks, which makes
    the loop about 7 dB louder at Paula's full volume.
    """
    rng = random.Random(1981)
    n = NOISE_LEN
    cos = [math.cos(2 * math.pi * i / n) for i in range(n)]
    sin = [math.sin(2 * math.pi * i / n) for i in range(n)]
    logf = [math.log(f) for f, _ in SPECTRUM]
    bins = {}
    for k in range(1, n // 2):
        f = k * NOISE_RATE / n
        if not SPECTRUM[0][0] <= f <= 1000:  # under 1% of the power lies above 1 kHz
            continue
        i = max(j for j in range(len(SPECTRUM)) if SPECTRUM[j][0] <= f)
        j = min(i + 1, len(SPECTRUM) - 1)
        t = 0 if i == j else (math.log(f) - logf[i]) / (logf[j] - logf[i])
        bins[k] = (math.sqrt(SPECTRUM[i][1] + (SPECTRUM[j][1] - SPECTRUM[i][1]) * t), rng.random() * 2 * math.pi)

    def build() -> list[float]:
        x = [0.0] * n
        for k, (amp, phase) in bins.items():
            c, s_ = amp * math.cos(phase), amp * math.sin(phase)
            for i in range(n):
                m = k * i % n
                x[i] += c * cos[m] - s_ * sin[m]
        return x

    x = build()
    for _ in range(NOISE_ROUNDS):
        rms = math.sqrt(sum(v * v for v in x) / n)
        limit = NOISE_CREST * rms
        x = [max(-limit, min(limit, v)) for v in x]
        for k, (amp, _) in bins.items():  # keep each bin's new phase, restore its level
            re = sum(x[i] * cos[k * i % n] for i in range(n))
            im = -sum(x[i] * sin[k * i % n] for i in range(n))
            bins[k] = (amp, math.atan2(im, re))
        x = build()
    peak = max(abs(v) for v in x)
    return bytes(round(v / peak * 127) & 0xFF for v in x)


def dcb(data: bytes, width: int = 16) -> list[str]:
    return ["\tdc.b\t" + ",".join(f"${b:02x}" for b in data[i : i + width]) for i in range(0, len(data), width)]


def dcw(words: list[int], width: int = 8) -> list[str]:
    return ["\tdc.w\t" + ",".join(f"${w:04x}" for w in words[i : i + width]) for i in range(0, len(words), width)]


def main() -> None:
    rom = S.Rom(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    code = rom.code
    word = lambda a: code[a] | code[a + 1] << 8  # noqa: E731

    ptrs = [word(N.TRACKS + 2 * i) for i in range(47)]
    first = min(ptrs)
    end = max(ptrs) + 3
    while code[end] != 0xFF:
        end += 2
    tracks = code[first : end + 1]

    notes = [0] * 256
    for octave in range(16):
        for note in range(13):
            notes[octave << 4 | note] = paula_entry(word(N.NOTES + 2 * note) >> octave)

    asm = ["; generated by tools/make_sound_data.py from the user's ROM - do not edit, do not commit"]
    asm += ["snd_parms:\t; per sound: first track, number of tracks, first voice"] + dcb(code[N.PARMS : N.PARMS + 69], 3)
    asm += ["snd_tempo:\t; per sound: ticks per unit of note length"] + dcb(code[N.TEMPO : N.TEMPO + 23], 23)
    asm += ["\teven", "snd_trackptr:\t; per track: offset into snd_tracks"] + dcw([p - first for p in ptrs])
    asm += ["snd_pulse:\t; formation pulse: slide rates out, in; start pitches out, in"]
    asm += dcw([word(N.PULSE + 2 * i) for i in range(32)])
    asm += ["snd_notes:\t; note byte -> Paula period | waveform length code << 12"] + dcw(notes)
    asm += ["snd_pulseper:\t; pulse pitch (high byte) -> the same"] + dcw([paula_entry(h) for h in range(256)])
    asm += ["snd_tracks:\t; header (envelope, delay, waveform) then (note, length) pairs, $ff ends"] + dcb(tracks)
    asm += ["\teven"]
    (out / "snd_data.i").write_text("\n".join(asm) + "\n")

    chip = bytearray()
    for n in (32, 16, 8):
        for w in rom.waves:
            step = 32 // n
            for i in range(n):
                v = sum(w[i * step : (i + 1) * step]) / step
                chip.append(int(round((v - 7.5) * 16)) & 0xFF)
    waves = len(chip)
    chip += noise_loop()
    (out / "snd_chip.bin").write_bytes(chip)
    tables = 69 + 23 + 1 + 94 + 64 + 512 + 512 + len(tracks)
    noise = [b - 256 if b > 127 else b for b in chip[waves:]]
    rms = math.sqrt(sum(v * v for v in noise) / len(noise))
    print(f"tables {tables} bytes (tracks {len(tracks)}), waveforms {waves} bytes, "
          f"noise loop {NOISE_LEN} bytes at rms {rms:.0f} of 127")


if __name__ == "__main__":
    main()
