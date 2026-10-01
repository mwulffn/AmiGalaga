"""Animate arcade timing against PAL timing, side by side.

    uv run --with pillow python3 render_compare.py ../original/galaga.zip build/compare.gif

Left: the arcade stepper, shown at the arcade's own speed. Middle: the PAL
stepper (1.2 arcade frames per 50 Hz frame). Right: both drawn on top of each
other, arcade in its real colours and PAL as a white outline. The GIF plays at
50 frames per second, so the PAL panel shows every frame it would on an Amiga
and the arcade panel shows the arcade frame nearest to the same moment.

The scene is the opening of stage 1 (four butterflies and four bees looping in
from the top) followed by two bees diving from the formation and returning.
The output uses the game's sprites, so it stays in build/ like everything else
derived from the ROM.
"""

import sys
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

import galaga_motion as G
import pal_scale as P

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "experiment-1" / "tools"))
import extract_gfx as X  # noqa: E402

W, H, SCALE = 224, 288, 2
SPAWN_GAP = 8  # arcade frames between enemies of a wave
DIVES = ((0x08, False, 170), (0x0A, True, 230))  # object, mirrored, arcade frame
LENGTH = 560  # arcade frames


def sprite_frames(zip_path: str) -> dict[str, list[Image.Image]]:
    """Eight RGBA frames per enemy type, upright orientation as extracted."""
    with zipfile.ZipFile(zip_path) as z:
        rom = z.read("gg1_11.4d") + z.read("gg1_10.4f")
        pal, lut = z.read("prom-5.5n"), z.read("prom-3.1c")
    out = {}
    for name, code, first in (("bee", 3, 0x18), ("butterfly", 2, 0x10)):
        cols = [lut[code * 4 + p] & 15 for p in range(4)]
        frames = []
        for t in range(first, first + 8):
            img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
            for y, row in enumerate(X.tile_pens(rom, t)):
                for x, pen in enumerate(row):
                    if cols[pen] != 15:
                        c = X.ocs(pal[cols[pen]])
                        img.putpixel((x, y), ((c >> 8) * 17, (c >> 4 & 15) * 17, (c & 15) * 17, 255))
            frames.append(img)
        out[name] = frames
    return out


def pose(heading: int) -> tuple[int, bool, bool]:
    """Rotation frame and flips for a 10-bit heading, as the arcade picks them."""
    quadrant, a = heading >> 8 & 3, heading & 0xFF
    if quadrant & 1:
        a ^= 0xFF
    a += 21
    frame = 6 if a > 0xFF else (((a >> 1) + (a >> 2)) >> 5) & 7
    return frame, quadrant in (0, 3), quadrant in (2, 3)  # frame, mirror, upside down


def new_slot(script: int, start: tuple[int, int, int], obj: int, mirror: bool) -> bytes:
    s = bytearray(20)
    s[1], s[3], s[5] = start
    s[8], s[9], s[0x0D], s[0x10], s[0x13] = script & 255, script >> 8, 1, obj, 0x81 if mirror else 1
    return bytes(s)


def cast(rom: G.Rom) -> list[tuple[int, bytes]]:
    """(arcade frame it appears, starting slot) for every enemy in the scene."""
    script, k = rom.entry_paths()[0]
    starts = rom.start_positions()
    objs = rom.main[G.WAVE_OBJECTS : G.WAVE_OBJECTS + 8]
    out = []
    for i in range(4):  # stage 1, first wave: both halves arrive together
        out.append((i * SPAWN_GAP, new_slot(script, starts[2 * k], objs[i], False)))
        out.append((i * SPAWN_GAP, new_slot(script, starts[2 * k + 1], objs[4 + i], True)))
    env = P.formation_env()
    for obj, mirror, at in DIVES:
        row, col = rom.sub[G.HOME_RC + obj], rom.sub[G.HOME_RC + obj + 1]
        s = bytearray(new_slot(0x034F, (env.home_loc[row + 1], env.home_loc[col + 1] >> 1, 1), obj, mirror))
        out.append((at, bytes(s)))
    return out


def kind(rom: G.Rom, obj: int) -> str:
    return "bee" if rom.sub[G.HOME_RC + obj] >= 0x1C else "butterfly"


def simulate(rom: G.Rom, fifths: int) -> list[dict[int, tuple[float, float, int, bool]]]:
    """Per displayed frame: {actor: (screen x, screen y, heading, at home)}."""
    actors = cast(rom)
    env = P.formation_env()
    states: dict[int, P.State] = {}
    home: dict[int, tuple[float, float]] = {}
    started: set[int] = set()
    for obj in DIVES:  # divers start in the formation
        row, col = rom.sub[G.HOME_RC + obj[0]], rom.sub[G.HOME_RC + obj[0] + 1]
        home[8 + DIVES.index(obj)] = (env.home_loc[col + 1] - 17, 312 - 2 * env.home_loc[row + 1])
    frames, clock, f = [], 0, 0
    while clock < LENGTH * 5:
        env.frame = f
        for i, (at, slot) in enumerate(actors):
            if i not in started and at * 5 <= clock:
                started.add(i)
                states[i] = P.from_slot(slot)
                home.pop(i, None)
        shot = {}
        for i, st in list(states.items()):
            ev = P.frame(st, rom, env, fifths)
            if ev == "home":
                home[i] = (st.x / 128 - 17, 312 - st.y / 128)
                del states[i]
            elif ev != "end":
                x, y = P.pos(st.y, st.x, st.yo, st.xo) if st.homing else P.pos(st.y, st.x)
                shot[i] = (x - 17, 312 - y, st.h >> 22, False)
        for i, (x, y) in home.items():
            shot[i] = (x, y, 256, True)
        frames.append(shot)
        clock += fifths
        f += 1
    return frames


def draw(panel: Image.Image, shot: dict, sprites: dict, kinds: list[str], tick: int, outline: bool) -> None:
    for i, (x, y, heading, at_home) in sorted(shot.items()):
        if not (-16 < x < W and -16 < y < H):
            continue
        frame, mirror, upside = pose(heading)
        if at_home:
            frame, mirror, upside = 6 + (tick // 16 & 1), False, False
        img = sprites[kinds[i]][frame]
        if mirror:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        if upside:
            img = img.transpose(Image.FLIP_TOP_BOTTOM)
        if outline:
            edge = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
            a = img.getchannel("A")
            for py in range(16):
                for px in range(16):
                    if a.getpixel((px, py)) and any(
                        not (0 <= px + dx < 16 and 0 <= py + dy < 16) or not a.getpixel((px + dx, py + dy))
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                    ):
                        edge.putpixel((px, py), (255, 255, 255, 255))
            img = edge
        panel.alpha_composite(img, (round(x), round(y))) if 0 <= round(x) <= W - 16 and 0 <= round(y) <= H - 16 else None


def main() -> None:
    rom = G.Rom(sys.argv[1])
    sprites = sprite_frames(sys.argv[1])
    actors = cast(rom)
    kinds = [kind(rom, slot[0x10]) for _, slot in actors]
    arcade, pal = simulate(rom, 5), simulate(rom, 6)
    titles = ("Arcade timing", "PAL timing (1.2 scaling)", "Both: PAL as white outline")
    out = []
    for p, pal_shot in enumerate(pal):
        arc_shot = arcade[min(round(1.2 * (p + 1)) - 1, len(arcade) - 1)]
        sheet = Image.new("RGBA", (3 * (W + 8) + 8, H + 28), (28, 28, 34, 255))
        d = ImageDraw.Draw(sheet)
        for n, title in enumerate(titles):
            panel = Image.new("RGBA", (W, H), (0, 0, 0, 255))
            if n != 1:
                draw(panel, arc_shot, sprites, kinds, p, False)
            if n == 1:
                draw(panel, pal_shot, sprites, kinds, p, False)
            if n == 2:
                draw(panel, pal_shot, sprites, kinds, p, True)
            sheet.paste(panel, (8 + n * (W + 8), 20))
            d.text((8 + n * (W + 8), 5), title, fill=(210, 210, 210, 255))
        big = sheet.convert("RGB").resize((sheet.width * SCALE, sheet.height * SCALE), Image.NEAREST)
        out.append(big.quantize(colors=32, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE))
    out[0].save(sys.argv[2], save_all=True, append_images=out[1:], duration=20, loop=0, optimize=False)
    print(f"{len(out)} frames at 50 fps ({len(out) / 50:.1f} s), {Path(sys.argv[2]).stat().st_size // 1024} KB")
    for n in (40, 100, 200, 300):  # stills for a quick look
        out[n].convert("RGB").save(Path(sys.argv[2]).with_name(f"compare_{n}.png"))


if __name__ == "__main__":
    main()
