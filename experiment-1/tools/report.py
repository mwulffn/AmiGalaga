"""Decode the "results" file written by a MEASURE build of experiment-1."""

import struct
import sys
from pathlib import Path

PALETTE = [
    0x000, 0xDDF, 0xF00, 0xFF0, 0x06F, 0x0FF, 0xF0F, 0x0F0,
    0xD40, 0x09A, 0x90F, 0x00F, 0xFB0, 0xF90, 0x0BF, 0xB0F,
]  # fmt: skip


def main() -> None:
    raw = Path(sys.argv[1]).read_bytes()
    worst, total, frames = struct.unpack(">HIH", raw[:8])
    avg = total / frames
    print(
        f"{sys.argv[2]:<34} avg {avg:6.1f} lines ({avg / 313:4.0%} of a frame)  "
        f"worst {worst:3d} lines  -> {'50 fps' if worst < 313 else 'misses 50 fps'}"
    )
    if len(sys.argv) > 3:
        try:
            from PIL import Image
        except ImportError:
            return
        scr = raw[8:]
        bpr = int(sys.argv[4]) if len(sys.argv) > 4 else 40  # bytes per plane row
        rows = len(scr) // (bpr * 4)
        img = Image.new("RGB", (bpr * 8, rows))
        for y in range(rows):
            for x in range(bpr * 8):
                o, bit = y * bpr * 4 + x // 8, 7 - x % 8
                c = PALETTE[sum((scr[o + bpr * p] >> bit & 1) << p for p in range(4))]
                img.putpixel((x, y), ((c >> 8) * 17, (c >> 4 & 15) * 17, (c & 15) * 17))
        img.save(sys.argv[3])


if __name__ == "__main__":
    main()
