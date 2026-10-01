"""The arcade sound driver rewritten as plain logic, as a blueprint for the 68000.

`galaga_sound.Driver` runs the arcade's program in a Z80 emulator. This is
the same behaviour written out by hand, using only the ROM's data tables,
so that it can be ported. `python3 native.py galaga.zip [sound.bin]` checks
it against the emulated driver, tick for tick, on every sound and (given a
MAME trace) on real gameplay.

How a tick works:
  - the three voices start silent
  - request 0, the formation pulse, slides voice 0's pitch from a table
  - then the other sounds are handled in a fixed order (ORDER); each one
    that is playing advances its tracks and writes its voices, so later
    sounds overwrite earlier ones
A sound is one to three tracks, one per voice. A track is a 3-byte header
(envelope type, envelope delay, waveform) and (note, length) pairs ending
in $ff. A note is an index into 12 base frequencies plus an octave shift;
$0c is a rest. Length is multiplied by a per-sound tempo.
"""

import sys

import galaga_sound as S

# Table addresses in the Namco rev. B sound ROM.
NOTES = 0x06DA  # 13 words: base frequency per note
PULSE = 0x06F4  # 4 x 8 words: slide rates out/in, start pitches out/in
PARMS = 0x0734  # per sound: first track, number of tracks, first voice
TRACKS = 0x0779  # 47 words: track addresses
TEMPO = 0x07D7  # per sound: ticks per unit of note length

TRIGGER, COUNT, HELD = "trigger", "count", "held"
ORDER = [  # (sound, how its request byte works), in the order the arcade handles them
    (0x13, TRIGGER), (0x0F, TRIGGER), (0x03, TRIGGER), (0x02, TRIGGER), (0x04, TRIGGER),
    (0x01, TRIGGER), (0x12, COUNT), (0x05, HELD), (0x06, HELD), (0x09, HELD), (0x07, COUNT),
    (0x11, HELD), (0x0D, COUNT), (0x0E, COUNT), (0x14, COUNT), (0x15, COUNT), (0x0A, COUNT),
    (0x0B, COUNT), (0x10, HELD), (0x0C, COUNT), (0x16, COUNT), (0x08, COUNT),
]  # fmt: skip


class Native:
    def __init__(self, rom: S.Rom) -> None:
        self.rom = rom.code
        self.req = bytearray(32)  # the game writes these
        self.direction = 0  # formation breathing: $ff going in, else going out
        self.active = bytearray(32)
        self.clock = bytearray(48)  # per track: ticks into the current note
        self.pos = bytearray(48)  # per track: offset of the current note pair
        self.wave = [0, 0, 0]  # kept between ticks
        self.freq = [0, 0, 0]  # 16-bit; the chip's step is this times 16
        self.vol = [0, 0, 0]
        self.finished = False
        self.pulse_dir, self.pulse_step, self.pulse_table = 0, 0, PULSE
        self.pulse_rate, self.pulse_pitch = 0, 0
        self.beam_vol, self.beam_tick, self.beam_wave, self.beam_wave_tick = 0, 0, 0, 0

    def word(self, a: int) -> int:
        return self.rom[a] | self.rom[a + 1] << 8

    def tick(self) -> bytes:
        """One driver tick. Returns the same 19 bytes as the emulated driver, masked."""
        self.freq, self.vol = [0, 0, 0], [0, 0, 0]
        if self.req[0]:
            self.pulse()
        for sound, mode in ORDER:
            if mode == TRIGGER:
                if self.req[sound]:
                    self.req[sound] = 0
                    self.active[sound] = (self.active[sound] + 1) & 0xFF
                    self.play(sound, restart=True)
                elif self.active[sound]:
                    self.play(sound, restart=False)
            elif self.req[sound]:
                if not self.active[sound]:
                    self.active[sound] = 1
                    done = self.play(sound, restart=True)
                else:
                    done = self.play(sound, restart=False)
                if mode == COUNT and done:
                    self.count_done(sound)
                if sound == 0x05:  # tractor beam: voice 2's volume sweeps down and wraps
                    self.beam_tick += 1
                    if self.beam_tick >= 6:
                        self.beam_tick = 0
                        self.beam_vol = 0x0C if self.beam_vol < 4 else self.beam_vol - 1
                    self.vol[2] = self.beam_vol
                elif sound == 0x06:  # capture: voice 0 steps through the waveforms
                    self.beam_wave_tick += 1
                    if self.beam_wave_tick == 0x1C:
                        self.beam_wave_tick = 0
                        self.beam_wave = (self.beam_wave + 1) & 0xFF
                    self.wave[0] = self.beam_wave
                elif sound == 0x0E:  # results tune: fixed volumes on voices 1 and 2
                    self.vol[1], self.vol[2] = 9, 6
            elif mode == HELD:
                self.active[sound] = 0
        f, v = self.freq, self.vol
        regs = [0, f[0] & 15, f[0] >> 4 & 15, f[0] >> 8 & 15, f[0] >> 12, v[0] & 15]
        for i in (1, 2):
            regs += [f[i] & 15, f[i] >> 4 & 15, f[i] >> 8 & 15, f[i] >> 12, v[i] & 15]
        return bytes(regs) + bytes(w & 7 for w in self.wave)

    def pulse(self) -> None:
        """Request 0: voice 0 slides up while the formation spreads, down while it closes."""
        if self.direction != self.pulse_dir:
            self.pulse_dir = self.direction
            self.pulse_table = PULSE + (16 if self.direction == 0xFF else 0)
            self.clock[0] = self.pulse_step = 0
            reload = True
        else:
            self.clock[0] += 1
            reload = self.clock[0] == 0x22
            if reload:
                self.clock[0] = 0
                self.pulse_step = (self.pulse_step + 1) & 0xFF
        if reload:
            a = self.pulse_table + 2 * self.pulse_step
            self.pulse_rate, self.pulse_pitch = self.word(a), self.word(a + 0x20)
        self.pulse_pitch = (self.pulse_pitch + self.pulse_rate) & 0xFFFF
        self.freq[0], self.vol[0], self.wave[0] = self.pulse_pitch >> 8, 0x0A, 0

    def play(self, sound: int, restart: bool) -> bool:
        """Advance every track of a sound by one tick. True when it has ended."""
        first, count, voice = self.rom[PARMS + 3 * sound : PARMS + 3 * sound + 3]
        if sound == 0x0E:  # the results tune brings its voices in one at a time
            if self.pos[0x1C] == 0:
                count = 1
            elif self.pos[0x1C] == 1 or self.pos[0x1D] == 0:
                count = 2
        if restart:
            for t in range(first, first + count):
                self.pos[t] = self.clock[t] = 0
        for t in range(first, first + count):
            self.track(sound, t, voice + t - first)
        done, self.finished = self.finished, False
        if done:
            self.active[sound] = 0
        return done

    def count_done(self, sound: int) -> None:
        if sound == 0x08:  # coin: once per credit
            self.req[sound] = (self.req[sound] - 1) & 0xFF
        elif sound == 0x0C:  # name entry: alternates with sound $16
            self.req[sound] = (self.req[sound] - 1) & 0xFF
            if self.req[sound] == 0 or self.req[sound] & 1:
                self.req[0x16] = 1
        elif sound == 0x14:  # perfect: followed by the dive sound
            self.req[sound] = 0
            self.req[0x13] = 1
        else:
            self.req[sound] = 0

    def track(self, sound: int, t: int, voice: int) -> None:
        rom = self.rom
        self.clock[t] = (self.clock[t] + 1) & 0xFF
        clock = self.clock[t]
        base = self.word(TRACKS + 2 * t)
        kind, delay, wave = rom[base : base + 3]
        p = base + 3 + self.pos[t]
        note = rom[p]
        if note == 0xFF:
            self.vol[voice] = 0
            self.finished = True
            return
        self.freq[voice] = self.word(NOTES + 2 * (note & 15)) >> (note >> 4)
        if note == 0x0C:
            vol = 0
        elif kind == 1 and clock < 6:
            vol = clock * 2  # fade in
        elif kind >= 2 and clock < 6:
            vol = ~clock  # 15, 14, ... a sharp start
        elif delay == 0 or clock < delay:
            vol = 10
        else:
            vol = max(10 - (clock - delay), 0)  # fade out after the delay
        self.vol[voice] = vol & 0xFF
        self.wave[voice] = wave
        if (rom[TEMPO + sound] * rom[p + 1]) & 0xFF == clock:
            self.pos[t] = (self.pos[t] + 2) & 0xFF
            self.clock[t] = 0


def masked(regs: bytes) -> bytes:
    return bytes(b & 15 for b in regs[:16]) + bytes(b & 7 for b in regs[16:])


def main() -> None:
    rom = S.Rom(sys.argv[1])
    total = bad = 0
    for sound in S.SOUNDS:  # every sound on its own, requested three times in a row
        z, n = S.Driver(rom), Native(rom)
        misses = 0
        for t in range(3000):
            if t in (4, 1200, 1210) or (sound in S.HELD and 4 <= t < 600):
                z.request(sound)
                n.req[sound] = 1
            if sound in S.HELD and t == 600:
                z.request(sound, 0)
                n.req[sound] = 0
            d = 0xFF if (t // 272) & 1 else 0x01
            z.mem[S.FORMATION_DIR] = n.direction = d
            a, b = masked(z.tick()), n.tick()
            n.req[:] = z.mem[S.REQUESTS : S.REQUESTS + 32]  # stay in step if they diverge
            misses += a != b
        total += 3000
        bad += misses
        if misses:
            print(f"  {sound:02x} {S.SOUNDS[sound]}: {misses} ticks differ")
    print(f"each sound alone: {total} ticks, {bad} different")
    if len(sys.argv) > 2:
        data = open(sys.argv[2], "rb").read()
        n, diff = Native(rom), 0
        ticks = len(data) // 53
        for i in range(ticks):
            rec = data[i * 53 : (i + 1) * 53]
            for k in range(32):  # the game's writes; ours are already there if it matches
                if k != 0x16 or rec[k]:
                    n.req[k] = rec[k]
            n.req[8] = (n.req[8] + rec[32]) & 0xFF
            n.direction = rec[33]
            diff += n.tick() != masked(rec[34:])
        print(f"gameplay trace: {ticks} ticks, {diff} different")


if __name__ == "__main__":
    main()
