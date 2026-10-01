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
        print("  late frames (frame: lines): " + ", ".join(f"{f}: {n}" for f, n in zip(late[0::2], late[1::2]) if n))


if __name__ == "__main__":
    main()
