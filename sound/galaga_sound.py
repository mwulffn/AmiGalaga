"""Galaga sound: the arcade's sound driver and sound chip, modelled in Python.

Nothing here contains ROM data; it is all read from the user's galaga.zip.

The arcade has a third Z80 whose only job is sound. 121 times a second
(two interrupts per video frame) it looks at a block of request bytes the
game sets, advances whichever sounds are active, and writes frequency,
volume and waveform for three voices to the sound chip. `Driver` runs that
program unmodified in a Z80 emulator (the `z80` package), so its output is
the arcade's by construction; validate.py checks it against MAME anyway.

The sound chip (Namco WSG) is a wavetable player: each voice steps through
one of eight 32-sample waveforms at a programmable rate and volume.
`render()` turns a list of register snapshots into audio.

Not modelled: the separate noise chip used for explosions (request $19).
"""

import zipfile
from pathlib import Path

SOUND_ROM, SOUND_CRC = "gg1_7b.2c", 0xD016686B
WAVE_PROM = "prom-1.1d"
TICK_HZ = 60.606 * 2  # driver ticks per second
CHIP_HZ = 96000  # the sound chip's sample rate

REQUESTS = 0x9AA0  # one byte per sound: a count or an on/off flag
ACTIVE = 0x9AC0  # one byte per sound, set by the driver while it plays
CREDITS = 0x9A79
FORMATION_DIR = 0x9211  # the pulsing formation sound follows this

# Request numbers, named from the reference disassembly and from listening.
SOUNDS = {
    0x00: "formation_pulse",  # on/off; pitch follows the formation breathing
    0x01: "hit_boss_second",
    0x02: "hit_butterfly",
    0x03: "hit_bee",
    0x04: "hit_boss_first",
    0x05: "tractor_beam",  # on/off
    0x06: "tractor_beam_capture",  # on/off
    0x07: "fighter_destroyed",
    0x08: "coin",
    0x09: "sound_09",  # on/off
    0x0A: "extra_fighter",
    0x0B: "start_theme",
    0x0C: "name_entry_theme_a",
    0x0D: "challenge_intro",
    0x0E: "challenge_results",
    0x0F: "shot",
    0x10: "name_entry_loop",  # on/off
    0x11: "fighter_rescued",  # on/off
    0x12: "transform",
    0x13: "dive",
    0x14: "challenge_perfect",
    0x15: "stage_badge_click",
    0x16: "name_entry_theme_b",
}
HELD = {0x00, 0x05, 0x06, 0x09, 0x10, 0x11}  # play for as long as the request is set


class Rom:
    def __init__(self, zip_path: str | Path) -> None:
        with zipfile.ZipFile(zip_path) as z:
            if z.getinfo(SOUND_ROM).CRC != SOUND_CRC:
                raise SystemExit(f"{SOUND_ROM}: not the Namco rev. B ROM")
            self.code = z.read(SOUND_ROM)
            prom = z.read(WAVE_PROM)
        # 8 waveforms of 32 four-bit samples
        self.waves = [[prom[w * 32 + i] & 15 for i in range(32)] for w in range(8)]


class Driver:
    """The arcade's sound program, one `tick()` per interrupt."""

    STOP = 0xFFF0  # the interrupt handler returns here

    def __init__(self, rom: Rom) -> None:
        import z80

        self.m = z80.Z80Machine()
        self.m.set_memory_block(0, rom.code)
        self.mem = self.m.memory
        self.m.set_breakpoint(self.STOP)

    def tick(self) -> bytes:
        """Run one interrupt. Returns 19 bytes: registers $10-$1f, then 3 wave selects."""
        m, mem = self.m, self.mem
        sp = 0x9B00 - 2
        mem[sp], mem[sp + 1] = self.STOP & 255, self.STOP >> 8
        m.sp, m.pc = sp, 0x0066
        while True:
            m.ticks_to_stop = 1_000_000
            if m.run() & m._BREAKPOINT_HIT:
                break
        return bytes(mem[0x6810:0x6820]) + bytes((mem[0x6805], mem[0x680A], mem[0x680F]))

    def request(self, sound: int, value: int = 1) -> None:
        self.mem[REQUESTS + sound] = value

    def busy(self, sound: int) -> bool:
        return bool(self.mem[REQUESTS + sound] or self.mem[ACTIVE + sound])


def voices(regs: bytes) -> list[tuple[int, int, int]]:
    """(frequency, volume, waveform) for the three voices of one snapshot.

    Frequency is the chip's 20-bit step: pitch in Hz = step * 96000 / 2^20.
    """
    r = [b & 15 for b in regs[:16]]
    f0 = r[0] | r[1] << 4 | r[2] << 8 | r[3] << 12 | r[4] << 16
    f1 = r[6] << 4 | r[7] << 8 | r[8] << 12 | r[9] << 16
    f2 = r[11] << 4 | r[12] << 8 | r[13] << 12 | r[14] << 16
    return [(f0, r[5], regs[16] & 7), (f1, r[10], regs[17] & 7), (f2, r[15], regs[18] & 7)]


def hz(step: int) -> float:
    return step * CHIP_HZ / (1 << 20)


def render(rom: Rom, ticks: list[bytes], rate: int = 44100) -> bytes:
    """16-bit mono PCM of the sound chip playing these snapshots, one per tick."""
    import array

    out = array.array("h")
    phase = [0.0, 0.0, 0.0]
    done = 0.0
    for regs in ticks:
        vs = voices(regs)
        done += rate / TICK_HZ
        n = int(done)
        done -= n
        for _ in range(n):
            s = 0
            for v, (step, vol, wave) in enumerate(vs):
                if vol and step:
                    phase[v] = (phase[v] + step * CHIP_HZ / rate) % (1 << 20)
                    s += (rom.waves[wave][int(phase[v]) >> 15] - 7.5) * vol
            out.append(int(s * 90))
    return out.tobytes()
