"""Galaga enemy movement: ROM tables and a reference flight-path stepper.

Nothing here contains ROM data. Everything is read from the user's own
galaga.zip (Namco rev. B set) at run time.

The arcade keeps up to 12 flying objects in a queue of 20-byte slots and
steps each one once per frame from a small script in the sub CPU's ROM.
`step()` is a faithful port of that routine (sub CPU, $08D3), checked
against MAME by validate.py.

Slot layout (offsets as in the arcade's RAM):
  00-01  y, 9.7 fixed point (byte 01 = y / 2)
  02-03  x, 9.7 fixed point (byte 03 = x / 2)
  04-05  heading, 10 bits, 1024 = full turn
  06-07  target y, x (home position, or dive depth)
  08-09  script pointer
  0A,0B  speed on odd / even frames
  0C     turn per frame (signed)
  0D     frames left in this script step
  0E,0F  bomb timer, bomb enable bits
  10     object number
  11,12  home x, y offset while homing
  13     flags: 01 active, 20 watch dive depth, 40 homing, 80 mirrored
"""

import zipfile
from dataclasses import dataclass, field
from pathlib import Path

SUB_ROM = "gg1_5b.3f"
MAIN_ROMS = ("gg1_1b.3p", "gg1_2b.3m", "gg1_3.2m", "gg1_4b.2l")
SUB_CRC = 0xBB5CAAE3  # Namco rev. B; other sets have the tables elsewhere

MAIN_CRCS = (0xAB036C9F, 0xD9232240, 0x753CE503, 0x499FCC76)

# Addresses in the main CPU ROM.
STAGE_IDX = 0x26A8  # 4 ranks x 17 bytes: row offset into the combat stage data
CHALLENGE_IDX = 0x26EC  # 8 bytes: row offset into the challenge stage data
STAGE_DATA = 0x26F4  # 13 rows of 18 bytes
CHALLENGE_DATA = 0x27DE  # 8 rows of 18 bytes
WAVE_OBJECTS = 0x286E  # 40 object numbers: 5 waves of 8
PATH_TABLE = 0x2A3C  # 24 words: script address | start position index << 13
START_POS = 0x2A6C  # 12 x (y/2, x/2, heading high byte)
ESCORT_TABLE = 0x1B65  # 3 script addresses for a diving bee's escorts
# Addresses in the sub CPU ROM.
HOME_RC = 0x0100  # per object: row index, column index into the home tables
BREATHE_PATTERNS = 0x1E6A  # main ROM: 4 sets of 16 bit patterns, see formation.py
# Scripts the main CPU starts by address (dives and special cases).
DIVES = {
    0x034F: "bee_dive",
    0x03A9: "butterfly_dive",
    0x0411: "boss_dive",
    0x0444: "rogue_fighter",
    0x0454: "boss_capture",
    0x046B: "boss_after_capture",
    0x0502: "escort_leaves",
    0x00F1: "script_00f1",  # started from the boss dive code; purpose not yet identified
    # what a transformed enemy flies, by its colour set (4, 5, 6); see transform.py
    0x04EA: "flagship_dive",
    0x0473: "scorpion_dive",
    0x04AB: "spy_ship_dive",
}
CAPTURE_HOVER = (0x045D, 0x0460)  # the capture boss's "hold still" step

NAMES = {
    0xFF: "end",  # object leaves play
    0xFE: "aim_at_fighter",  # pick this step's duration from 8 values by fighter x
    0xFD: "jump",
    0xFC: "dive_to",  # run until y reaches the given depth
    0xFB: "go_home",  # head for the formation slot
    0xFA: "jump_unless_last_stand",
    0xF9: "column_x",  # take x from the home column
    0xF8: "wrap_to_top",
    0xF7: "jump_if_transient",
    0xF6: "set_heading",
    0xF5: "become_flyer",
    0xF4: "aim_capture",
    0xF3: "aim_red",  # as aim_at_fighter, for the red enemy's dive
    0xF2: "spawn_escort",
    0xF1: "home_row_y",
    0xF0: "jump_if_hard",  # taken when stage parameter 8 is set
    0xEF: "jump_if_harder",  # stage parameter 9
}
ARG_BYTES = {0xFE: 8, 0xFD: 2, 0xFC: 1, 0xFA: 2, 0xF7: 2, 0xF6: 1, 0xF3: 8, 0xF2: 2, 0xF0: 2, 0xEF: 2}
JUMPS = {0xFD, 0xFA, 0xF7, 0xF2, 0xF0, 0xEF}


class Rom:
    def __init__(self, zip_path: str | Path) -> None:
        with zipfile.ZipFile(zip_path) as z:
            crc = z.getinfo(SUB_ROM).CRC
            if crc != SUB_CRC:
                raise SystemExit(f"{SUB_ROM}: CRC {crc:08x}, expected {SUB_CRC:08x} (Namco rev. B set)")
            for name, want in zip(MAIN_ROMS, MAIN_CRCS):
                if z.getinfo(name).CRC != want:
                    raise SystemExit(f"{name}: not the Namco rev. B ROM")
            self.sub = z.read(SUB_ROM)
            self.main = b"".join(z.read(n) for n in MAIN_ROMS)

    def word(self, rom: bytes, a: int) -> int:
        return rom[a] | rom[a + 1] << 8

    def entry_paths(self) -> list[tuple[int, int]]:
        """(script address, start position index) for the 24 entry paths."""
        out = []
        for i in range(24):
            w = self.word(self.main, PATH_TABLE + 2 * i)
            out.append((w & 0x1FFF, w >> 13))
        return out

    def start_positions(self) -> list[tuple[int, int, int]]:
        return [tuple(self.main[START_POS + 3 * i : START_POS + 3 * i + 3]) for i in range(12)]


def screen_pos(s: bytes) -> tuple[int, int]:
    """Top left of the 16x16 sprite on the upright 224x288 screen (not homing)."""
    return 2 * s[3] + (s[2] >> 7) - 17, 312 - 2 * s[1] - (s[0] >> 7)


def div16(hl: int, a: int) -> int:
    """HL / A as the arcade does it ($0EAA): 17 shift-subtract rounds."""
    c, acc, carry = a, 0, 0
    for _ in range(17):
        acc = acc * 2 + carry
        if acc > 0xFF:
            acc = (acc - c) & 0xFF
            carry = 1
        elif acc >= c:
            acc -= c
            carry = 1
        else:
            carry = 0
        hl = hl * 2 + carry
        carry = hl >> 16
        hl &= 0xFFFF
    return hl


def heading_to(ty: int, tx: int, y: int, x: int) -> int:
    """Heading from (y, x) towards (ty, tx), all in half pixels ($0E5B)."""
    b = 0
    a = (tx - x) & 0xFF
    if tx < x:
        b |= 1
        a = -a & 0xFF
    c = a
    a = (ty - y) & 0xFF
    if ty < y:
        b = (b ^ 1) | 2
        a = -a & 0xFF
    less = a < c
    t = ((a << 1) | less) & 0xFF
    t ^= b
    b = ((b << 1) | (1 - (t & 1))) & 0xFF
    if less:
        a, c = c, a
    hl = div16(c << 8, a)
    lo = hl & 0xFF
    if ((hl >> 8) ^ b) & 1:
        lo ^= 0xFF
    return (b << 8 | lo) >> 1


@dataclass
class Env:
    """What the stepper reads besides the slot and the script."""

    frame: int = 0  # the arcade's frame counter; its low bit picks the speed
    flip: int = 0
    fighter_x: int = 0x80  # sprite x of the fighter (two registers in the arcade)
    fighter_x_hw: int = 0x80
    obj_state: dict[int, int] = field(default_factory=dict)
    home_x: bytes = bytes(0x20)  # $9800: pixel x per formation column (and rows)
    home_loc: bytes = bytes(0x20)  # $9900: (offset, origin / 2) per column and row
    stage_parms: bytes = bytes(11)  # $99C0
    last_stand: int = 0  # $92AA: one enemy left, attacks continuously
    boss_killed_task: int = 0  # $901D
    bomb_reload: int = 0  # $92E2
    bomb_bits: int = 0  # $92C8


def step(s: bytearray, rom: Rom, env: Env) -> str | None:
    """Advance one active slot by one frame. Returns an event name or None."""
    sub = rom.sub
    obj = s[0x10]
    if env.obj_state.get(obj, 3) not in (3, 7, 9):
        s[0x13] = 0
        return "end"
    mirror = s[0x13] & 0x80
    home_rc = sub[HOME_RC + obj : HOME_RC + obj + 2] if obj < 0x60 else b"\0\0"

    s[0x0D] = (s[0x0D] - 1) & 0xFF
    if s[0x0D] == 0:
        p = s[0x08] | s[0x09] << 8
        while True:
            t = sub[p]
            if t < 0xEF:  # plain step: speeds, turn, duration
                s[0x0A], s[0x0B] = t & 15, t >> 4
                s[0x0C] = -sub[p + 1] & 0xFF if mirror else sub[p + 1]
                s[0x0D] = sub[p + 2]
                p += 3
                break
            if t == 0xFF:
                s[0x13] = 0
                env.obj_state[obj] = 0x80
                return "end"
            if t in (0xFD,):
                p = sub[p + 1] | sub[p + 2] << 8
            elif t in (0xFE, 0xF3):  # duration chosen by where the fighter is
                if t == 0xFE:
                    a = env.fighter_x_hw or 0x80
                    if not ((env.flip & 1) ^ (s[0x13] >> 7)):
                        a = (-a + 0xF2) & 0xFF
                    a = (a + 0x0E) & 0xFF
                    idx = div16(a << 8 | 0x14, 0x1E) >> 8
                else:
                    a = min(max(env.fighter_x, 0x1E), 0xD1)
                    if env.flip & 1:
                        a = -(a + 0x0E) & 0xFF
                    a >>= 1
                    d = a - s[0x03]
                    a = ((d & 0xFF) >> 1) | (0x80 if d < 0 else 0)
                    if mirror:
                        a = -a & 0xFF
                    a = (a + 0x18) & 0xFF
                    if a & 0x80:
                        a = 0
                    a = min(a, 0x2F)
                    idx = (div16(a << 8 | 0x14, 6) >> 8) + 1
                s[0x0D] = sub[p + idx]
                p += 9
                break
            elif t == 0xFC:
                s[0x06], s[0x07] = sub[p + 1], 0
                s[0x13] |= 0x20
                p += 2
                break
            elif t == 0xFB:
                env.obj_state[obj] = 9
                row, col = home_rc
                xo, xc = env.home_loc[col], env.home_loc[col + 1] >> 1
                yo, yc = env.home_loc[row], env.home_loc[row + 1]
                s[0x11], s[0x12] = xo, yo
                if env.flip:
                    xo, yo = -xo & 0xFF, -yo & 0xFF
                sy = yo - 256 if yo & 0x80 else yo
                sx = xo - 256 if xo & 0x80 else xo
                y = ((s[0] | s[1] << 8) + sy * 128) & 0xFFFF
                x = ((s[2] | s[3] << 8) - sx * 128) & 0xFFFF
                s[0], s[1], s[2], s[3] = y & 255, y >> 8, x & 255, x >> 8
                h = heading_to(yc, xc, s[1], s[3])
                s[4], s[5], s[6], s[7] = h & 255, h >> 8, yc, xc
                s[0x13] |= 0x40
                p += 1
            elif t in (0xFA, 0xF7):
                if t == 0xFA:
                    taken = ((env.boss_killed_task - 1) & env.last_stand & 0xFF) == 0
                else:
                    taken = (obj & 0x38) == 0x38
                p = sub[p + 1] | sub[p + 2] << 8 if taken else p + 3
            elif t in (0xF9, 0xF8, 0xF6, 0xF1, 0xF0, 0xEF):  # set something, wait a frame
                if t == 0xF9:
                    a = env.home_x[home_rc[1]]
                    if env.flip & 1:
                        a = -(a + 0x0E) & 0xFF
                    s[3] = a >> 1
                elif t == 0xF8:
                    s[1] = 0x9C
                elif t == 0xF6:
                    a = sub[p + 1]
                    if mirror:
                        a = -(a + 0x80) & 0xFF
                    s[4], s[5] = (a << 2) & 0xFF, a >> 6
                    s[0x0E], s[0x0F] = 0x1E, env.bomb_bits
                    p += 1
                elif t == 0xF1:
                    s[1] = (env.home_loc[home_rc[0] + 1] + 0x20) & 0xFF
                else:
                    if env.stage_parms[8 if t == 0xF0 else 9]:
                        p = (sub[p + 1] | sub[p + 2] << 8) - 1
                    else:
                        p += 2
                p += 1
                s[0x08], s[0x09] = p & 255, p >> 8
                s[0x0D] = 1
                return NAMES[t]
            elif t == 0xF5:
                env.obj_state[obj] = 3
                p += 1
            elif t == 0xF4:
                a = ((env.fighter_x + 3) & 0xF8) + 1
                a = 0x29 if a < 0x29 else 0xC9 if a >= 0xCA else a
                if env.flip & 1:
                    a = ~(a + 13) & 0xFF
                h = heading_to(0x48, a >> 1, s[1], s[3])
                s[4], s[5] = h & 255, h >> 8
                p += 1
            elif t == 0xF2:  # the escort itself is spawned by the caller
                p += 3
            else:
                raise ValueError(f"token {t:02x} at {p:04x}")
        s[0x08], s[0x09] = p & 255, p >> 8

    event = None
    if s[0x13] & 0x40:  # homing: arrived when within one unit on both axes
        dy = (s[1] - s[6]) & 0xFF
        dx = (s[3] - s[7]) & 0xFF
        if dy in (0, 1, 0xFF) and dx in (0, 1, 0xFF):
            s[0x13] &= ~1
            s[0] = s[2] = 0
            s[1], s[3] = s[6], s[7]
            env.obj_state[obj] = 2
            event = "home"
    if event is None:
        if s[0x13] & 0x20 and (s[1] - s[6]) & 0xFF in (0, 0xFF):
            s[0x0D] = 1
            s[0x13] &= ~0x20
        turn = s[0x0C]
        lo, hi = s[4], s[5]
        total = lo + turn
        s[4] = total & 0xFF
        if turn & 0x80:
            if total < 0x100:
                s[5] = (hi - 1) & 0xFF
        elif total > 0xFF:
            s[5] = (hi + 1) & 0xFF
        speed = s[0x0A] if env.frame & 1 else s[0x0B]
        if speed:
            octant = (hi & 3) << 1 | lo >> 7  # heading in 45 degree steps
            main = 0 if ((hi & 1) ^ (lo >> 7)) else 2  # dominant axis: y or x
            sign = -1 if (octant + 1) & 4 else 1
            v = ((s[main] | s[main + 1] << 8) + sign * speed * 128) & 0xFFFF
            s[main], s[main + 1] = v & 255, v >> 8
            frac = lo & 0x7F
            if lo & 0x80:
                frac ^= 0x7F
            minor = main ^ 2
            sign = -1 if ((octant ^ 2) - 1) & 4 else 1
            v = ((s[minor] | s[minor + 1] << 8) + sign * frac * speed) & 0xFFFF
            s[minor], s[minor + 1] = v & 255, v >> 8
    s[0x0E] = (s[0x0E] - 1) & 0xFF
    if s[0x0E] == 0:
        s[0x0F] >>= 1
        s[0x0E] = env.bomb_reload
    return event


def parse_script(rom: Rom, start: int) -> dict[int, tuple]:
    """Follow a script from `start`: {address: ("step", hi, lo, turn, n) | (name, args...)}."""
    sub, seen, todo = rom.sub, {}, [start]
    while todo:
        p = todo.pop()
        while p not in seen:
            t = sub[p]
            if t < 0xEF:
                turn = sub[p + 1] - 256 if sub[p + 1] & 0x80 else sub[p + 1]
                seen[p] = ("step", t >> 4, t & 15, turn, sub[p + 2])
                p += 3
                continue
            n = ARG_BYTES.get(t, 0)
            args = tuple(sub[p + 1 : p + 1 + n])
            if t in JUMPS:
                target = args[0] | args[1] << 8
                seen[p] = (NAMES[t], target)
                todo.append(target)
                if t == 0xFD:
                    break
            else:
                seen[p] = (NAMES[t], *args)
                if t == 0xFF:
                    break
            p += 1 + n
    return dict(sorted(seen.items()))
