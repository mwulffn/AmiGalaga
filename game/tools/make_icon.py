"""Make the program's Workbench icon: build/AmiGalaga.info.

    python3 tools/make_icon.py build/AmiGalaga.info

A fighter of the game's own drawing (not the arcade's), in Workbench's four pens.
The pens are other colours on Workbench 1.3 (blue, white, black, orange) than on 2.0
and later (grey, black, white, blue), so the picture is made to read on both: a body
in pen 1 with an edge in pen 2, and the accent pen for the cockpit.

The file is a DiskObject as Kickstart 1.2 and every later one read it: the header,
with a gadget in it, then one image of two planes.
"""

import struct
import sys
from pathlib import Path

# "." nothing, "#" the body (pen 1), "o" its edge (pen 2), "+" the accent (pen 3)
PENS = {".": 0, "#": 1, "o": 2, "+": 3}
FIGHTER = (
    ".......oo.......",
    "......o##o......",
    "......o##o......",
    ".....o####o.....",
    ".....o####o.....",
    ".oo..o#++#o..oo.",
    ".o#o.o#++#o.o#o.",
    ".o#oo######oo#o.",
    ".o#o########o#o.",
    "o##############o",
    "o###o######o###o",
    "o##o.o####o.o##o",
    "o#o...o##o...o#o",
    ".o.....oo.....o.",
)
# A Workbench pixel is about twice as tall as it is wide, so a point of the drawing is
# four pixels by two.
ACROSS, DOWN = 4, 2
DEPTH = 2
MAGIC, VERSION = 0xE310, 1
GADGET_IMAGE, GADGET_BACKFILL = (
    4,
    1,
)  # the gadget's flags: it has a picture; how it shows as chosen
RELVERIFY, IMMEDIATE = 1, 2  # its activation
BOOL_GADGET = 1
TOOL = 3  # the kind of icon: a program
NO_POSITION = 0x80000000  # Workbench places it
STACK = 4096
POINTER = 1  # where the file has a pointer that only needs to be not nought


def planes() -> tuple[bytes, int, int]:
    """The picture's planes one after the other, and its width and height."""
    rows = [
        [PENS[point] for point in line for _ in range(ACROSS)]
        for line in FIGHTER
        for _ in range(DOWN)
    ]
    width, height = len(rows[0]), len(rows)
    data = bytearray()
    for plane in range(DEPTH):
        for row in rows:
            row = row + [0] * (-width % 16)
            bits = sum(
                1 << (len(row) - 1 - x) for x, pen in enumerate(row) if pen >> plane & 1
            )
            data += bits.to_bytes(len(row) // 8, "big")
    return bytes(data), width, height


def disk_object() -> bytes:
    """The whole .info file."""
    data, width, height = planes()
    gadget = struct.pack(
        ">IhhhhHHHIIIiIHI",
        0,  # no next gadget
        0,
        0,
        width,
        height,
        GADGET_IMAGE | GADGET_BACKFILL,
        RELVERIFY | IMMEDIATE,
        BOOL_GADGET,
        POINTER,  # its picture follows
        0,  # no second picture for when it is chosen
        0,  # no text
        0,
        0,
        0,
        0,
    )
    header = struct.pack(">HH", MAGIC, VERSION) + gadget
    header += struct.pack(
        ">BxIIIIIII", TOOL, 0, 0, NO_POSITION, NO_POSITION, 0, 0, STACK
    )
    image = struct.pack(
        ">hhhhhIBBI", 0, 0, width, height, DEPTH, POINTER, (1 << DEPTH) - 1, 0, 0
    )
    return header + image + data


def main() -> None:
    Path(sys.argv[1]).write_bytes(disk_object())


if __name__ == "__main__":
    main()
