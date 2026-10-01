"""Static colour analysis of the Galaga (Namco rev. B) PROMs and gfx ROMs."""
from pathlib import Path

R = Path("rom")
pal = (R / "prom-5.5n").read_bytes()
chr_lut = (R / "prom-4.2n").read_bytes()
spr_lut = (R / "prom-3.1c").read_bytes()
chr_rom = (R / "gg1_9.4l").read_bytes()
spr_rom = (R / "gg1_11.4d").read_bytes() + (R / "gg1_10.4f").read_bytes()

W3 = (0x21, 0x47, 0x97)  # 1k / 470 / 220 ohm
W2 = (0x51, 0xAE)  # 470 / 220 ohm


def rgb(v: int) -> tuple[int, int, int]:
    r = sum(W3[i] for i in range(3) if v >> i & 1)
    g = sum(W3[i] for i in range(3) if v >> (3 + i) & 1)
    b = sum(W2[i] for i in range(2) if v >> (6 + i) & 1)
    return r, g, b


def amiga(c: tuple[int, int, int]) -> str:
    return "".join(f"{round(x / 17):X}" for x in c)


colors = [rgb(v) for v in pal]
print("== 32-entry palette PROM (0-15 sprites, 16-31 chars) ==")
for i, (v, c) in enumerate(zip(pal, colors)):
    print(f"{i:2d} prom={v:02X} rgb=#{c[0]:02X}{c[1]:02X}{c[2]:02X} ocs=${amiga(c)}")
for name, sl in (("sprite bank 0-15", slice(0, 16)), ("char bank 16-31", slice(16, 32))):
    print(name, "distinct rgb:", len(set(colors[sl])),
          "distinct ocs:", len({amiga(c) for c in colors[sl]}))
print("whole prom distinct rgb:", len(set(colors)),
      "ocs:", len({amiga(c) for c in colors}))


def pens(rom: bytes, size: int, n: int) -> list[set[int]]:
    """Set of 2bpp pixel values used by each tile (orientation irrelevant)."""
    out = []
    for t in range(n):
        s = set()
        for b in rom[t * size:(t + 1) * size]:
            for k in range(4):
                s.add(((b >> k) & 1) | (((b >> (k + 4)) & 1) << 1))
        out.append(s)
    return out


spr_pens = pens(spr_rom, 64, 128)
chr_pens = pens(chr_rom, 16, 256)

for name, lut, base, trans in (("SPRITE", spr_lut, 0, 0x0F), ("CHAR", chr_lut, 16, 0x1F)):
    print(f"\n== {name} colour codes (4 pens -> palette index), transparent={trans} ==")
    groups: dict[tuple, list[int]] = {}
    for code in range(64):
        e = tuple((lut[code * 4 + p] & 0x0F) | base for p in range(4))
        groups.setdefault(e, []).append(code)
    used = set()
    for e, codes in groups.items():
        vis = [x for x in e if x != trans]
        used.update(vis)
        desc = " ".join("--" if x == trans else f"{x:2d}" for x in e)
        print(f"codes {codes}: [{desc}]  opaque distinct={len(set(vis))}")
    print(f"distinct code definitions: {len(groups)}")
    print(f"palette entries reachable (opaque): {sorted(used)} -> {len(used)} entries,",
          len({colors[i] for i in used}), "distinct rgb,",
          len({amiga(colors[i]) for i in used}), "distinct ocs")
    print("upper 128 bytes of LUT:", set(lut[128:]) if len(set(lut[128:])) < 4 else "varied",
          "| high nibbles:", {b >> 4 for b in lut})

print("\n== pixel values used per sprite tile ==")
from collections import Counter
print(Counter(tuple(sorted(s)) for s in spr_pens))
print("blank sprite tiles:", [i for i, s in enumerate(spr_pens) if len(s) == 1])
print("char tiles:", Counter(tuple(sorted(s)) for s in chr_pens))

star = set()
for i in range(64):
    comp = []
    for sh in (0, 2, 4):
        comp.append(sum(W2[k] for k in range(2) if i >> (sh + k) & 1))
    star.add(tuple(comp))
print("\nstars: 64 codes ->", len(star), "rgb,", len({amiga(c) for c in star}), "ocs (approx weights)")
