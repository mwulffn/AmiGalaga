"""Prototype: the arcade flight stepper running 1.2 arcade frames per PAL frame.

    python3 pal_scale.py path/to/galaga.zip [motion.bin]

The scaled stepper keeps the arcade's scripts untouched and differs from the
arcade routine only in how time is counted:

  - a step's duration is held in fifths of an arcade frame (5 per frame);
    a PAL frame consumes 6 of them (5 in the exact build)
  - the heading is a 32-bit value (2^32 = full turn), so turning is one add
    and nothing is lost to rounding over a long path
  - turn and distance for k fifths of a frame come from small tables
    (TURN, DIST); when a step ends part-way through a PAL frame, each step
    contributes its own share

With 5 fifths per frame it must reproduce the arcade exactly; that is checked
first. Then the 6-fifths version is compared with the arcade at equal times.
With a MAME trace (trace_motion.lua) the dive scripts are compared too,
starting from states the real game produced.
"""

import math
import sys
from dataclasses import dataclass

import galaga_motion as G

# Heading added per unit of turn rate in k fifths of an arcade frame, as a
# 16-bit factor that is then shifted left 8 (one muls and a shift on the 68000).
TURN = tuple(round(k * 16384 / 5) for k in range(7))
# Distance in 1/128 pixel for speed 0..15 over k fifths of an arcade frame.
DIST = tuple(tuple(round(v * k * 128 / 5) for v in range(16)) for k in range(7))


@dataclass
class State:
    y: int
    x: int
    h: int  # heading, 2^32 = full turn
    ptr: int
    obj: int
    mirror: bool
    left: int = 0  # fifths of an arcade frame left in the current step
    lo: int = 0
    hi: int = 0
    turn: int = 0
    pause: bool = False
    diving: bool = False
    homing: bool = False
    ty: int = 0
    tx: int = 0
    xo: int = 0  # formation offset added for display while homing
    yo: int = 0
    active: bool = True
    bomb_timer: int = 0  # arcade frames to its next chance to bomb
    bomb_bits: int = 0  # its chances: one bit a time, low bit first


def from_slot(s: bytes) -> State:
    turn = s[0x0C] - 256 if s[0x0C] & 0x80 else s[0x0C]
    return State(
        y=s[0] | s[1] << 8, x=s[2] | s[3] << 8, h=((s[4] | s[5] << 8) << 22) & 0xFFFFFFFF,
        ptr=s[8] | s[9] << 8, obj=s[0x10], mirror=bool(s[0x13] & 0x80),
        left=5 * ((s[0x0D] - 1) & 0xFF), lo=s[0x0A], hi=s[0x0B], turn=turn,
        diving=bool(s[0x13] & 0x20), homing=bool(s[0x13] & 0x40), ty=s[6], tx=s[7],
    )  # fmt: skip


def load(st: State, rom: G.Rom, env: G.Env) -> bool:
    """Run script tokens until one takes time. False when the object leaves."""
    sub = rom.sub
    rc = sub[G.HOME_RC + st.obj : G.HOME_RC + st.obj + 2] if st.obj < 0x60 else b"\0\0"
    while True:
        p, t = st.ptr, sub[st.ptr]
        if t < 0xEF:
            turn = sub[p + 1] - 256 if sub[p + 1] & 0x80 else sub[p + 1]
            st.lo, st.hi, st.turn = t & 15, t >> 4, -turn if st.mirror else turn
            st.left, st.ptr, st.pause = 5 * (sub[p + 2] or 256), p + 3, False
            return True
        if t == 0xFF:
            st.active = False
            return False
        if t == 0xFD:
            st.ptr = sub[p + 1] | sub[p + 2] << 8
        elif t in (0xFE, 0xF3):
            if t == 0xFE:
                a = env.fighter_x_hw or 0x80
                if not ((env.flip & 1) ^ st.mirror):
                    a = (-a + 0xF2) & 0xFF
                idx = ((a + 0x0E) & 0xFF) // 30
            else:
                a = min(max(env.fighter_x, 0x1E), 0xD1) >> 1
                d = a - (st.x >> 8)
                a = ((d & 0xFF) >> 1) | (0x80 if d < 0 else 0)
                if st.mirror:
                    a = -a & 0xFF
                a = (a + 0x18) & 0xFF
                idx = min(0 if a & 0x80 else a, 0x2F) // 6 + 1
            st.left, st.ptr, st.pause = 5 * (sub[p + idx] or 256), p + 9, False
            return True
        elif t == 0xFC:
            st.ty, st.diving = sub[p + 1], True
            st.left, st.ptr, st.pause = 5 * 256, p + 2, False
            return True
        elif t == 0xFB:
            env.obj_state[st.obj] = 9
            xo, xc = env.home_loc[rc[1]], env.home_loc[rc[1] + 1] >> 1
            yo, yc = env.home_loc[rc[0]], env.home_loc[rc[0] + 1]
            st.yo, st.xo = (yo - 256 if yo & 0x80 else yo), (xo - 256 if xo & 0x80 else xo)
            st.y = (st.y + st.yo * 128) & 0xFFFF
            st.x = (st.x - st.xo * 128) & 0xFFFF
            st.h = (G.heading_to(yc, xc, st.y >> 8, st.x >> 8) << 22) & 0xFFFFFFFF
            st.ty, st.tx, st.homing = yc, xc, True
            st.ptr = p + 1
        elif t in (0xFA, 0xF7):
            if t == 0xFA:
                taken = ((env.boss_killed_task - 1) & env.last_stand & 0xFF) == 0
            else:
                taken = (st.obj & 0x38) == 0x38
            st.ptr = sub[p + 1] | sub[p + 2] << 8 if taken else p + 3
        elif t in (0xF9, 0xF8, 0xF6, 0xF1, 0xF0, 0xEF):  # one arcade frame standing still
            st.ptr = p + 1
            if t == 0xF9:
                st.x = (st.x & 0xFF) | (env.home_x[rc[1]] >> 1) << 8
            elif t == 0xF8:
                st.y = (st.y & 0xFF) | 0x9C00
            elif t == 0xF6:
                a = sub[p + 1]
                if st.mirror:
                    a = -(a + 0x80) & 0xFF
                st.h, st.ptr = (a << 24) & 0xFFFFFFFF, p + 2
                st.bomb_timer, st.bomb_bits = 0x1E, env.bomb_bits  # and a new set of chances to bomb
            elif t == 0xF1:
                st.y = (st.y & 0xFF) | ((env.home_loc[rc[0] + 1] + 0x20) & 0xFF) << 8
            elif env.stage_parms[8 if t == 0xF0 else 9]:
                st.ptr = sub[p + 1] | sub[p + 2] << 8
            else:
                st.ptr = p + 3
            st.left, st.pause = 5, True
            return True
        elif t == 0xF5:
            st.ptr = p + 1
        elif t == 0xF4:
            a = ((env.fighter_x + 3) & 0xF8) + 1
            a = 0x29 if a < 0x29 else 0xC9 if a >= 0xCA else a
            st.h = (G.heading_to(0x48, a >> 1, st.y >> 8, st.x >> 8) << 22) & 0xFFFFFFFF
            st.ptr = p + 1
        else:  # 0xF2: the escort is spawned elsewhere
            st.ptr = p + 3


def frame(st: State, rom: G.Rom, env: G.Env, fifths: int) -> str | None:
    """One displayed frame: `fifths` fifths of an arcade frame (5 exact, 6 PAL)."""
    budget, dh, dist, heading = fifths, 0, 0, st.h
    while budget:
        if st.left == 0:
            if not load(st, rom, env):
                return "end"
            if st.h != heading:  # the script set the heading: drop the old step's turn
                dh, heading = 0, st.h
        k = min(st.left, budget)
        if not st.pause:
            dh += (st.turn * TURN[k]) << 8
            dist += DIST[k][st.lo if env.frame & 1 else st.hi]
        st.left -= k
        budget -= k
    if st.pause:  # arcade: nothing else happens on a standing frame
        return None
    y8, x8 = st.y >> 8, st.x >> 8
    if st.homing:
        reach = 1 if fifths == 5 else 2  # faster steps need a wider catch
        if abs(((y8 - st.ty + 128) & 0xFF) - 128) <= reach and abs(((x8 - st.tx + 128) & 0xFF) - 128) <= reach:
            st.active = False
            st.y, st.x = st.ty << 8, st.tx << 8
            return "home"
    if st.diving:
        d = (y8 - st.ty) & 0xFF
        if d in (0, 0xFF) or (fifths != 5 and d >= 0x80):  # reached, or passed it
            st.left, st.diving = 0, False
    if dist:
        octant, frac = heading >> 29, heading >> 22 & 0x7F
        if octant & 1:
            frac ^= 0x7F
        along = dist if not (octant + 1) & 4 else -dist
        across = (dist * frac) >> 7
        if ((octant ^ 2) - 1) & 4:
            across = -across
        if (octant + 1) & 2:  # octants 1, 2, 5, 6: y is the dominant axis
            st.y, st.x = (st.y + along) & 0xFFFF, (st.x + across) & 0xFFFF
        else:
            st.x, st.y = (st.x + along) & 0xFFFF, (st.y + across) & 0xFFFF
    st.h = (st.h + dh) & 0xFFFFFFFF
    return None


def pos(y: int, x: int, yo: int = 0, xo: int = 0) -> tuple[float, float]:
    """Displayed position in pixels; a homing object is drawn at slot + offset."""
    return (x / 128 + xo) % 512, (y / 128 - yo) % 512


def apart(p: tuple[float, float], q: tuple[float, float]) -> float:
    """Distance in pixels; positions wrap at 512."""
    dx, dy = ((p[0] - q[0] + 256) % 512) - 256, ((p[1] - q[1] + 256) % 512) - 256
    return math.hypot(dx, dy)


def on_screen(p: tuple[float, float]) -> bool:
    x, y = p[0] - 17, 312 - p[1]
    return -16 < x < 224 and -16 < y < 288


def run_exact(slot: bytes, rom: G.Rom, env: G.Env, limit: int = 2000) -> tuple[list, str]:
    s, pts = bytearray(slot), []
    for f in range(limit):
        env.frame = f
        ev = G.step(s, rom, env)
        sign = lambda v: v - 256 if v & 0x80 else v  # noqa: E731
        off = (sign(s[0x12]), sign(s[0x11])) if s[0x13] & 0x40 or ev == "home" else (0, 0)
        pts.append(pos(s[0] | s[1] << 8, s[2] | s[3] << 8, *off))
        if ev in ("end", "home"):
            return pts, ev
    return pts, "timeout"


def run_scaled(slot: bytes, rom: G.Rom, env: G.Env, fifths: int, limit: int = 2000) -> tuple[list, str]:
    st, pts = from_slot(slot), []
    for f in range(limit):
        env.frame = f
        ev = frame(st, rom, env, fifths)
        pts.append(pos(st.y, st.x, st.yo, st.xo) if st.homing else pos(st.y, st.x))
        if ev in ("end", "home"):
            return pts, ev
    return pts, "timeout"


def formation_env() -> G.Env:
    """A formation at rest: columns 16 px apart, six rows."""
    cols = [49 + 16 * i for i in range(10)]
    rows = [146, 138, 130, 124, 118, 112]
    loc = bytes(v for c in cols + rows for v in (0, c))
    home_x = bytes(v for c in cols for v in (c, 0)) + bytes(12)
    return G.Env(home_x=home_x, home_loc=loc, obj_state={}, fighter_x=0x70, fighter_x_hw=0x70)


def compare(slot: bytes, rom: G.Rom, make_env) -> tuple[bool, float, float, float, str, str]:
    """(exact build identical, max px apart, end px apart, end time diff in arcade frames, ...)."""
    a, ev_a = run_exact(slot, rom, make_env())
    e, ev_e = run_scaled(slot, rom, make_env(), 5)
    same = ev_a == ev_e and len(a) == len(e) and all(
        abs(p[0] - q[0]) < 1 / 64 and abs(p[1] - q[1]) < 1 / 64 for p, q in zip(a, e)
    )
    s, ev_s = run_scaled(slot, rom, make_env(), 6)
    worst = 0.0
    for i, q in enumerate(s[:-1]):  # PAL frame i is arcade time 1.2 (i + 1) - 1
        t = 1.2 * (i + 1) - 1
        j = min(int(t), len(a) - 2)
        if j < 0 or j + 1 >= len(a) - 1:
            continue
        u = t - j
        if apart(a[j], a[j + 1]) > 32:  # the script moved it (wrap to top, home column)
            continue
        px = a[j][0] + (((a[j + 1][0] - a[j][0] + 256) % 512) - 256) * u
        py = a[j][1] + (((a[j + 1][1] - a[j][1] + 256) % 512) - 256) * u
        if on_screen(q) and on_screen((px % 512, py % 512)):  # off-screen drift is invisible
            worst = max(worst, apart(q, (px, py)))
    end = apart(s[-1], a[-1])
    return same, worst, end, len(s) * 1.2 - len(a), ev_a, ev_s


def main() -> None:
    rom = G.Rom(sys.argv[1])
    entries, starts = rom.entry_paths(), rom.start_positions()
    objects = rom.main[G.WAVE_OBJECTS : G.WAVE_OBJECTS + 40]
    rows = []
    for i, (script, k) in enumerate(entries):
        for mirror in (False, True):
            for obj in objects if i < 6 else objects[:1]:
                slot = bytearray(20)
                slot[1], slot[3], slot[5] = starts[2 * k + mirror]
                slot[8], slot[9], slot[0x0D], slot[0x10] = script & 255, script >> 8, 1, obj
                slot[0x13] = 0x81 if mirror else 0x01
                rows.append((f"entry {i:2d}", *compare(bytes(slot), rom, formation_env)))
    if len(sys.argv) > 2:  # dives as the real game started them
        import validate as V

        data = open(sys.argv[2], "rb").read()
        recs = [data[i : i + V.REC] for i in range(0, len(data) - V.REC + 1, V.REC)]
        seen = 0
        for t in range(1, len(recs)):
            for i in range(12):
                before, now = recs[t - 1][1 + 20 * i : 21 + 20 * i], recs[t][1 + 20 * i : 21 + 20 * i]
                p = now[8] | now[9] << 8
                if not before[0x13] & 1 and now[0x13] & 1 and now[0x0D] == 1 and p in G.DIVES and seen < 400:
                    seen += 1
                    base = V.env_of(recs[t])

                    def env(base: G.Env = base, obj: int = now[0x10]) -> G.Env:
                        e = formation_env()
                        e.home_x, e.home_loc, e.stage_parms = base.home_x, base.home_loc, base.stage_parms
                        e.fighter_x, e.fighter_x_hw, e.obj_state = base.fighter_x, base.fighter_x_hw, {obj: 9}
                        return e

                    rows.append((G.DIVES[p], *compare(now, rom, env)))

    groups: dict[str, list] = {}
    for name, *r in rows:
        groups.setdefault(name, []).append(r)
    print("path             runs  exact-build   max apart   end apart   end time   outcome arcade -> PAL")
    print("                       identical     (pixels)    (pixels)    (frames)")
    for name, rs in groups.items():
        outcomes = sorted({f"{r[4]} -> {r[5]}" for r in rs})
        print(
            f"{name:16} {len(rs):4}  {sum(r[0] for r in rs):4}/{len(rs):<4}    "
            f"{max(r[1] for r in rs):6.1f}      {max(r[2] for r in rs):6.1f}     "
            f"{max(abs(r[3]) for r in rs):6.1f}     {', '.join(outcomes)}"
        )


if __name__ == "__main__":
    main()
