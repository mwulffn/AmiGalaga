"""Check that every word or long field of the structures in include/*.i is at an even offset.

    python3 tools/check_even.py include build

A 68000 traps on a word or long access at an odd address, and nothing in the
assembler stops an `rs.w` from following an odd number of `rs.b`. The fields'
offsets are worked out by vasm itself: a scrap of source that includes the
headers and stores each field's offset is assembled, and the offsets read back.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

HEADERS = ("config.i", "hw.i", "layout.i", "flight.i", "sound.i", "state.i")
FIELD = re.compile(r"^(\w+)\s+rs\.([wl])\s", re.MULTILINE)


def main() -> None:
    include, build = Path(sys.argv[1]), Path(sys.argv[2])
    fields = [
        (h, m[1]) for h in HEADERS for m in FIELD.finditer((include / h).read_text())
    ]
    source = "".join(f'\tinclude\t"{h}"\n' for h in HEADERS)
    # a field inside a conditional block may not exist in this build: 0 then
    source += "".join(
        f"\tifd\t{name}\n\tdc.l\t{name}\n\telse\n\tdc.l\t0\n\tendc\n"
        for _, name in fields
    )
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "even.s").write_text(source)
        out = Path(tmp) / "even.bin"
        cmd = [
            "vasmm68k_mot",
            "-quiet",
            "-Fbin",
            "-m68000",
            f"-I{include}",
            f"-I{build}",
            "-o",
            str(out),
        ]
        subprocess.run([*cmd, str(Path(tmp) / "even.s")], check=True)
        data = out.read_bytes()
    odd = [
        (header, name, at)
        for i, (header, name) in enumerate(fields)
        if (at := int.from_bytes(data[4 * i : 4 * i + 4], "big")) & 1
    ]
    for header, name, at in odd:
        print(
            f"{include / header}: {name} is a word or long field at an odd offset ({at})"
        )
    sys.exit(1 if odd else 0)


if __name__ == "__main__":
    main()
