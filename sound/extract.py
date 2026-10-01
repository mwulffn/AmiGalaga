"""Extract Galaga's sounds from the user's own ROM set.

    uv run --with z80 python3 extract.py path/to/galaga.zip build

Each sound is requested on its own from the arcade's sound driver and run
until it ends. Writes (all derived from the ROM; keep out of the repository):
  wav/NN_name.wav     the sound as the arcade's chip would play it
  stream/NN_name.bin  what the driver wrote to the chip: 19 bytes per tick
                      (registers $10-$1f, then the three wave selects)
  waves.bin           the 8 waveforms as signed 8-bit samples, in lengths
                      32, 16, 8 and 4 for playing higher notes on Paula
  sounds.txt          length, voices and pitch range of every sound
"""

import sys
import wave
from pathlib import Path

import galaga_sound as S

HELD_SECONDS = 4.0  # how long to hold an on/off request for the recording
FORMATION_TICKS = 272  # the formation changes direction about this often
PAULA_MAX_HZ = 28000  # highest sample rate Paula plays reliably


def record(rom: S.Rom, sound: int) -> list[bytes]:
    """Driver output, tick by tick, for one sound requested on its own."""
    d = S.Driver(rom)
    for _ in range(4):
        d.tick()
    ticks: list[bytes] = []
    if sound in S.HELD:
        for t in range(int(HELD_SECONDS * S.TICK_HZ)):
            d.request(sound)
            if sound == 0:  # the pulse follows the formation breathing in and out
                d.mem[S.FORMATION_DIR] = 0xFF if (t // FORMATION_TICKS) & 1 else 0x01
            ticks.append(d.tick())
        d.request(sound, 0)
    else:
        d.request(sound)
    quiet = 0
    while quiet < 12 and len(ticks) < 40 * S.TICK_HZ:
        ticks.append(d.tick())
        silent = not any(vol for _, vol, _ in S.voices(ticks[-1]))
        quiet = quiet + 1 if silent and not d.busy(sound) else 0
    return ticks[: len(ticks) - 11]


def wave_length(pitch: float) -> int:
    """Longest waveform copy (32, 16, 8, 4) Paula can play at this pitch."""
    for n in (32, 16, 8, 4):
        if pitch * n <= PAULA_MAX_HZ:
            return n
    return 0


def main() -> None:
    rom = S.Rom(sys.argv[1])
    out = Path(sys.argv[2])
    for sub in ("wav", "stream"):
        (out / sub).mkdir(parents=True, exist_ok=True)

    blob = bytearray()
    for n in (32, 16, 8, 4):
        for w in rom.waves:
            step = 32 // n
            for i in range(n):  # average each group so short copies keep the shape
                v = sum(w[i * step : (i + 1) * step]) / step
                blob.append(int(round((v - 7.5) * 16)) & 0xFF)
    (out / "waves.bin").write_bytes(blob)

    lines = ["nr  name                   seconds  voices  waves     pitch range (Hz)   shortest waveform needed"]
    total, shortest_overall = 0.0, 32
    for sound, name in S.SOUNDS.items():
        ticks = record(rom, sound)
        stem = f"{sound:02x}_{name}"
        (out / "stream" / f"{stem}.bin").write_bytes(b"".join(ticks))
        with wave.open(str(out / "wav" / f"{stem}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(44100)
            w.writeframes(S.render(rom, ticks))
        used, waves, lo, hi = set(), set(), 1e9, 0.0
        for t in ticks:
            for v, (step, vol, wsel) in enumerate(S.voices(t)):
                if vol and step:
                    used.add(v)
                    waves.add(wsel)
                    lo, hi = min(lo, S.hz(step)), max(hi, S.hz(step))
        secs = len(ticks) / S.TICK_HZ
        if not used:
            lines.append(f"{sound:02x}  {name:22} {secs:6.2f}   (silent when requested on its own)")
            continue
        need = wave_length(hi)
        shortest_overall = min(shortest_overall, need)
        total += 0 if sound in S.HELD else secs
        lines.append(
            f"{sound:02x}  {name:22} {secs:6.2f}   {','.join(str(v) for v in sorted(used)):6}  "
            f"{','.join(str(w) for w in sorted(waves)):8}  {lo:7.0f} - {hi:6.0f}     {need}"
            + ("  (held for the recording)" if sound in S.HELD else "")
        )
    lines.append("")
    lines.append(f"one-shot sounds total {total:.1f} s; shortest waveform copy any sound needs: {shortest_overall} samples")
    (out / "sounds.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
