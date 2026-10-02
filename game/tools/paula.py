"""Play Paula's four channels again from the notes of what was written to her registers.

The recorder (record.py) notes every write to the sound registers and the moment it
was made, in CPU cycles. This plays them as the chip would have: each channel loops
the waveform its pointer and length give, a sample every `period` colour clocks, at
its volume. A new pointer or length waits for the loop to end, as in the chip; a new
period or volume is taken at once (the chip takes a period with the next sample,
which is at most a few hundred microseconds later).

The result is a stereo WAV at a high rate, the stepped signal as it is; whoever
wants it at 48 kHz filters it down (ffmpeg, in record.py). Channels 0 and 3 are the
left and 1 and 2 the right, as on the Amiga, each side with some of the other mixed
in, as most people listen to an Amiga.

Needs numpy.
"""

import wave
from pathlib import Path

import numpy as np

CPU_CLOCK = 7093790  # cycles a second: PAL
CYCLES_PER_CLOCK = 2  # a period counts colour clocks, each two CPU cycles
RATE = 192000  # samples a second of the result
CUSTOM = 0xDFF000
DMACON, DMA_SET, AUDIO_FIRST, AUDIO_STEP = 0x096, 0x8000, 0x0A0, 0x10
LC_HIGH, LC_LOW, LEN, PER, VOL = 0x0, 0x2, 0x4, 0x6, 0x8
LEFT = (0, 3)  # the channels on the left; the others are on the right
OTHER_SIDE = 0.3  # how much of the other side each side has
FULL = (
    127 * 64 * 2
)  # the loudest a side can be: two channels at full volume; the default

Event = tuple[int, int, int, int]  # cycle, register (from $dff000), bytes, value


def read_notes(path: Path) -> tuple[list[Event], int, int]:
    """The notes: the register writes, and the cycles of the first and last frame."""
    events: list[Event] = []
    frames: list[int] = []
    for line in path.read_text().splitlines():
        cycle, what, size, value = line.split()
        if what == "frame":
            frames.append(int(cycle))
        else:
            events.append((int(cycle), int(what) - CUSTOM, int(size), int(value)))
    return events, frames[0], frames[-1]


def words(events: list[Event]) -> list[tuple[int, int, int]]:
    """The writes as (cycle, register, word): a long is two words, a byte is left out."""
    out = []
    for cycle, register, size, value in events:
        if size == 4:
            out.append((cycle, register, value >> 16 & 0xFFFF))
            out.append((cycle, register + 2, value & 0xFFFF))
        elif size == 2:
            out.append((cycle, register, value & 0xFFFF))
    return out


def waveforms(events: list[Event]) -> set[tuple[int, int]]:
    """Every (address, bytes) a channel may have played: every pointer with every length."""
    pointers, lengths = set(), set()
    high = [0] * 4
    for _, register, value in words(events):
        channel, part = divmod(register - AUDIO_FIRST, AUDIO_STEP)
        if not 0 <= channel < 4:
            continue
        if part == LC_HIGH:
            high[channel] = value
        elif part == LC_LOW:
            pointers.add(high[channel] << 16 | value)
        elif part == LEN:
            lengths.add(2 * (value or 0x10000))
    return {(at, length) for at in pointers for length in lengths}


def channel(
    number: int, writes: list[tuple[int, int, int]], memory: dict, first: int, last: int
) -> np.ndarray:
    """One channel from cycle `first` to `last`, as samples times volume."""
    count = (last - first) * RATE // CPU_CLOCK
    out = np.zeros(count, dtype=np.float32)
    base = AUDIO_FIRST + number * AUDIO_STEP
    pointer = length = period = volume = 0  # what the registers hold
    playing: bytes | None = None  # the waveform being looped, and where in it
    at = 0.0
    on = False
    now = 0  # the cycle up to which the channel has been played

    def play(until: int) -> None:
        """Play from `now` to `until`."""
        nonlocal playing, at
        start, stop = max(now, first), min(until, last)
        if on and playing and period > 0:
            cycles = period * CYCLES_PER_CLOCK
            if stop > start and volume:
                k0 = -(-(start - first) * RATE // CPU_CLOCK)
                k1 = min(-(-(stop - first) * RATE // CPU_CLOCK), count)
                if k1 > k0:
                    moments = first + np.arange(k0, k1) * (CPU_CLOCK / RATE)
                    index = (at + (moments - now) / cycles).astype(np.int64)
                    wraps = index // len(playing)
                    data = np.frombuffer(playing, dtype=np.int8).astype(np.float32)
                    out[k0:k1] = data[index % len(playing)] * volume
                    # after the first wrap it is the waveform the registers hold now
                    if wraps.max() > 0 and memory[(pointer, length)] is not playing:
                        new = np.frombuffer(
                            memory[(pointer, length)], dtype=np.int8
                        ).astype(np.float32)
                        later = wraps > 0
                        passed = index[later] - len(playing)
                        out[k0:k1][later] = new[passed % len(new)] * volume
            moved = at + (until - now) / cycles
            if moved >= len(playing):
                moved -= len(playing)
                playing = memory[(pointer, length)]
                moved %= len(playing)
            at = moved

    for cycle, register, value in writes:
        if register == DMACON:
            bit = 1 << number
            if value & bit:
                play(cycle)
                now = cycle
                was, on = on, bool(value & DMA_SET)
                if on and not was and length:
                    playing, at = memory[(pointer, length)], 0.0
            continue
        if not base <= register < base + AUDIO_STEP:
            continue
        play(cycle)
        now = cycle
        part = register - base
        if part == LC_HIGH:
            pointer = value << 16 | pointer & 0xFFFF
        elif part == LC_LOW:
            pointer = pointer & 0xFFFF0000 | value
        elif part == LEN:
            length = 2 * (value or 0x10000)
        elif part == PER:
            period = value
        elif part == VOL:
            volume = min(value & 0x7F, 64)
    play(last)
    return out


def render(
    events: list[Event],
    memory: dict,
    first: int,
    last: int,
    path: Path,
    full: float = FULL,
) -> None:
    """Write the sound from cycle `first` to `last` as a WAV. `full` is what a side's
    samples times volumes add up to at the loudest that is to be allowed for."""
    writes = words(events)
    sides = [0.0, 0.0]
    for number in range(4):
        sides[0 if number in LEFT else 1] += channel(
            number, writes, memory, first, last
        )
    left = (sides[0] + OTHER_SIDE * sides[1]) / (1 + OTHER_SIDE)
    right = (sides[1] + OTHER_SIDE * sides[0]) / (1 + OTHER_SIDE)
    both = np.stack([left, right], axis=1) * (32000 / full)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(np.clip(both, -32767, 32767).astype("<i2").tobytes())
