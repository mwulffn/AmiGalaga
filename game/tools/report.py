"""Print the report a test build writes to "results"."""

import struct
import sys
from pathlib import Path

PAL_LINES = 313


def main() -> None:
    raw = Path(sys.argv[1]).read_bytes()
    worst, total, frames, worst_at, over = struct.unpack(">HIHHH", raw[:12])
    avg = total / frames
    print(
        f"{frames} frames: work took {avg:.1f} raster lines on average "
        f"({avg / PAL_LINES:.0%} of a frame), {worst} at worst (frame {worst_at}); "
        f"{over} frames took more than {PAL_LINES}"
    )
    late = struct.unpack(f">{(len(raw) - 12) // 2}H", raw[12:])
    if over:
        print("  late frames (frame: lines, with flying/landed/bombs/blasts on screen):")
        for f, n, on in zip(late[0::3], late[1::3], late[2::3]):
            if n:
                print(f"    {f}: {n}, {on >> 12}/{on >> 8 & 15}/{on >> 4 & 15}/{on & 15}")


if __name__ == "__main__":
    main()
