"""Check the emulated sound driver against a MAME trace (trace_sound.lua).

Each tick, give the driver the same request bytes the real game had and
compare the 19 bytes it writes to the sound chip with what MAME's wrote.
"""

import sys
from collections import Counter

import galaga_sound as S

REC = 32 + 2 + 16 + 3


def main() -> None:
    rom = S.Rom(sys.argv[1])
    data = open(sys.argv[2], "rb").read()
    d = S.Driver(rom)
    ok = bad = 0
    first, seen = [], Counter()
    for i in range(len(data) // REC):
        rec = data[i * REC : (i + 1) * REC]
        d.mem[S.REQUESTS : S.REQUESTS + 32] = rec[:32]
        d.mem[S.CREDITS], d.mem[S.FORMATION_DIR] = rec[32], rec[33]
        for k in range(0x17):
            if rec[k]:
                seen[k] += 1
        got = d.tick()
        if got == rec[34:]:
            ok += 1
        else:
            bad += 1
            if len(first) < 5:
                first.append((i, rec[:32].hex(), got.hex(), rec[34:].hex()))
    print(f"{ok + bad} ticks: {ok} identical, {bad} different")
    print("sounds requested in the trace:", ", ".join(S.SOUNDS[k] for k in sorted(seen)))
    for f in first:
        print(f)


if __name__ == "__main__":
    main()
