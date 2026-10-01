"""Per-scene colour usage from MAME traces (sprite/char tile:colour sets per frame)."""
import re
from collections import defaultdict
from pathlib import Path

R = Path("rom")
pal = (R / "prom-5.5n").read_bytes()
chr_lut = (R / "prom-4.2n").read_bytes()
spr_lut = (R / "prom-3.1c").read_bytes()
chr_rom = (R / "gg1_9.4l").read_bytes()
spr_rom = (R / "gg1_11.4d").read_bytes() + (R / "gg1_10.4f").read_bytes()
W3, W2 = (0x21, 0x47, 0x97), (0x51, 0xAE)
HW_CODES = {7, 9}  # sprite colour codes assumed to be Amiga hardware sprites


def ocs(v: int) -> str:
    r = sum(W3[i] for i in range(3) if v >> i & 1)
    g = sum(W3[i] for i in range(3) if v >> (3 + i) & 1)
    b = sum(W2[i] for i in range(2) if v >> (6 + i) & 1)
    return "".join(f"{round(x / 17):X}" for x in (r, g, b))


def pens(rom: bytes, size: int, n: int) -> list[set[int]]:
    out = []
    for t in range(n):
        s = set()
        for b in rom[t * size:(t + 1) * size]:
            for k in range(4):
                s.add(((b >> k) & 1) | (((b >> (k + 4)) & 1) << 1))
        out.append(s)
    return out


SPR_PENS, CHR_PENS = pens(spr_rom, 64, 128), pens(chr_rom, 16, 256)
cache: dict[tuple[str, str], frozenset[str]] = {}


def cols(kind: str, key: str) -> frozenset[str]:
    if (kind, key) not in cache:
        tile, code = (int(x, 16) for x in key.split(":"))
        if kind == "s":
            idx = [spr_lut[code * 4 + p] & 15 for p in SPR_PENS[tile]]
            res = {ocs(pal[i]) for i in idx if i != 15}
        else:
            idx = [chr_lut[code * 4 + p] & 15 for p in CHR_PENS[tile]]
            res = {ocs(pal[i | 16]) for i in idx if i != 15}
        cache[(kind, key)] = frozenset(res)
    return cache[(kind, key)]


LINE = re.compile(r"^(\d+)\t(\d+)\t(\d+)\t([0-9a-f:,]*)\t([0-9a-f:,]*)$")


class Scene:
    def __init__(self) -> None:
        self.spr, self.chr, self.bp = set(), set(), set()
        self.max_all = self.max_bp = self.max_spr = 0
        self.codes: dict[int, set[int]] = defaultdict(set)
        self.ccodes: set[int] = set()
        self.frames = 0
        self.worst = None

    def add(self, frame: int, sk: list[str], ck: list[str]) -> None:
        s_all, s_bp, c = set(), set(), set()
        for k in sk:
            code = int(k[3:], 16)
            cc = cols("s", k)
            if cc:
                self.codes[code].add(int(k[:2], 16))
            s_all |= cc
            if code not in HW_CODES:
                s_bp |= cc
        for k in ck:
            cc = cols("c", k)
            if cc:
                self.ccodes.add(int(k[3:], 16))
            c |= cc
        self.spr |= s_all; self.chr |= c; self.bp |= s_bp | c
        self.max_spr = max(self.max_spr, len(s_all))
        self.max_all = max(self.max_all, len(s_all | c))
        if len(s_bp | c) > self.max_bp:
            self.max_bp, self.worst = len(s_bp | c), frame
        self.frames += 1


def scene_of(src: str, frame: int, stage: int, lives: int) -> str | None:
    if frame < 1000:
        return None  # power-on self test
    if src == "attract":
        return "attract (title, demo, hi-scores)"
    if frame < 1405:
        return None
    if lives in (0, 255) and frame > 140000:
        return "game over / results / name entry"
    return "challenging stages" if stage % 4 == 3 else "normal stages"


scenes: dict[str, Scene] = defaultdict(Scene)
per_stage: dict[int, Scene] = defaultdict(Scene)
for src in ("attract", "play"):
    bad = 0
    for line in open(f"{src}.txt"):
        m = LINE.match(line.rstrip("\n"))
        if not m:
            bad += 1
            continue
        frame, stage, lives = int(m[1]), int(m[2]), int(m[3])
        name = scene_of(src, frame, stage, lives)
        if not name:
            continue
        sk = m[4].split(",") if m[4] else []
        ck = m[5].split(",") if m[5] else []
        for sc in (scenes[name], scenes["ALL SCENES"]):
            sc.add(frame, sk, ck)
        if src == "play" and "stages" in name:
            per_stage[stage].add(frame, sk, ck)
    print(f"{src}: {bad} malformed lines skipped")

print("\nscene | states | sprite colours (union / max at once) | char colours | "
      "all layers max at once | bitplane-only union | bitplane-only max at once")
for name, sc in scenes.items():
    print(f"{name} | {sc.frames} | {len(sc.spr)} / {sc.max_spr} | {len(sc.chr)} | "
          f"{sc.max_all} | {len(sc.bp)} | {sc.max_bp} (frame {sc.worst})")
    print("   sprite codes:", sorted(sc.codes), "| char codes:", sorted(sc.ccodes))
    print("   bitplane colours:", " ".join(sorted(sc.bp)))

a = scenes["ALL SCENES"]
print("\nsprite colour code -> tiles seen")
for code in sorted(a.codes):
    t = sorted(a.codes[code])
    print(f"  {code:2d}: {' '.join(f'{x:02x}' for x in t)}")

print("\nper stage: stage, sprite codes, bitplane union, bitplane max")
for st in sorted(per_stage):
    sc = per_stage[st]
    print(f"  {st:2d} {'C' if st % 4 == 3 else ' '} codes={sorted(sc.codes)} "
          f"chr={sorted(sc.ccodes)} union={len(sc.bp)} max={sc.max_bp}")
