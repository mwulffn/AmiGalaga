"""Decode the "results" file written by a MEASURE build of experiment-6."""

import struct
import sys
from pathlib import Path


def main() -> None:
    raw = Path(sys.argv[1]).read_bytes()
    worst, total, frames, tworst, ttotal, ticks = struct.unpack(">HIHHIH", raw[:16])
    avg = total / frames
    line = f"{sys.argv[2]:<34} avg {avg:6.1f} lines ({avg / 313:4.0%} of a frame)  worst {worst:3d} lines"
    if ticks:
        # one colour clock is two CPU clocks; a raster line is 227.5 colour clocks
        tavg = ttotal / ticks
        per_frame = tavg * 121.2 / 50 / 227.5
        line += (f"\n{'':<34} sound tick: avg {tavg * 2:5.0f} CPU cycles, worst {tworst * 2} "
                 f"({ticks} ticks) = {per_frame:.2f} raster lines per frame")
    print(line)


if __name__ == "__main__":
    main()
