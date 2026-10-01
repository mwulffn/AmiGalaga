"""Print the report a test build writes to "results"."""

import struct
import sys
from pathlib import Path

PAL_LINES = 313


def main() -> None:
    raw = Path(sys.argv[1]).read_bytes()
    worst, total, frames = struct.unpack(">HIH", raw[:8])
    avg = total / frames
    print(
        f"{frames} frames: work took {avg:.1f} raster lines on average "
        f"({avg / PAL_LINES:.0%} of a frame), {worst} at worst"
    )


if __name__ == "__main__":
    main()
