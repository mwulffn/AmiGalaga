"""Print the report a test build writes to "results"."""

import struct
import sys
from pathlib import Path

PAL_LINES = 313
# the parts of a frame's work, each from one of the game's PROF_ marks to the next
PARTS = (
    "sprites and panel", "logic", "moving the flights", "shots, bombs, hits", "rebuilding strips",
    "erasing flyers", "drawing the formation", "the beam", "drawing the flights", "drawing blasts",
    "drawing bombs", "drawing text", "waiting for the last blit",
)  # fmt: skip


def main() -> None:
    raw = Path(sys.argv[1]).read_bytes()
    worst, total, frames, worst_at, over = struct.unpack(">HIHHH", raw[:12])
    avg = total / frames
    print(
        f"{frames} frames: work took {avg:.1f} raster lines on average "
        f"({avg / PAL_LINES:.0%} of a frame), {worst} at worst (frame {worst_at}); "
        f"{over} frames took more than {PAL_LINES}"
    )
    marks = len(PARTS)
    profile = raw[len(raw) - 6 * marks :]
    worst_marks = struct.unpack(f">{marks}H", profile[: 2 * marks])
    sums = struct.unpack(f">{marks}I", profile[2 * marks :])
    late = struct.unpack(f">{(len(raw) - 12 - 6 * marks) // 2}H", raw[12 : len(raw) - 6 * marks])
    if over:
        print("  late frames (frame: lines, with flying/landed/bombs/blasts on screen):")
        for f, n, on in zip(late[0::3], late[1::3], late[2::3]):
            if n:
                print(f"    {f}: {n}, {on >> 12}/{on >> 8 & 15}/{on >> 4 & 15}/{on & 15}")


    if not any(sums):
        return  # not a PROFILE build
    # each part runs from its mark to the next; the last one to the end of the frame's work
    print("  where the lines go (average, and in the worst frame):")
    ends_avg = [n / frames for n in sums[1:]] + [avg]
    ends_worst = [*worst_marks[1:], worst]
    for i, part in enumerate(PARTS):
        print(f"    {part:28s}{ends_avg[i] - sums[i] / frames:6.1f}{ends_worst[i] - worst_marks[i]:6d}")
    print(f"    {'(before the work begins)':28s}{sums[0] / frames:6.1f}{worst_marks[0]:6d}")


if __name__ == "__main__":
    main()
