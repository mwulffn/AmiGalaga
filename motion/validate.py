"""Check galaga_motion.step() against a MAME trace made with trace_motion.lua.

For every frame and every active slot, step a copy of the previous frame's
slot and compare all 20 bytes with what the arcade code produced.
"""

import sys
from collections import Counter

import galaga_motion as G

REC = 1 + 240 + 128 + 32 + 32 + 11 + 8


def env_of(rec: bytes) -> G.Env:
    o = 241
    states = {i: rec[o + i] for i in range(0, 128, 2)}
    o += 128
    home_x, home_loc, parms = rec[o : o + 32], rec[o + 32 : o + 64], rec[o + 64 : o + 75]
    fx, fxhw, flip, last, task, reload_, bits, _stage = rec[o + 75 : o + 83]
    return G.Env(rec[0], flip, fx, fxhw, states, home_x, home_loc, parms, last, task, reload_, bits)


def main() -> None:
    rom = G.Rom(sys.argv[1])
    data = open(sys.argv[2], "rb").read()
    recs = [data[i : i + REC] for i in range(0, len(data) - REC + 1, REC)]
    ok = bad = late = 0
    why: Counter[str] = Counter()
    examples = []
    seen_keys: set[str] = set()
    for t in range(1, len(recs)):
        prev, cur = recs[t - 1], recs[t]
        if (cur[0] - prev[0]) & 0xFF != 1:
            continue  # sub CPU did not run exactly once
        # The main CPU updates the formation and fighter during the same frame, so
        # the stepper may have seen either this frame's or last frame's inputs.
        env = env_of(cur)
        env.obj_state = env_of(prev).obj_state
        env_old = env_of(prev)
        env_old.frame = cur[0]
        for i in range(12):
            before = prev[1 + 20 * i : 21 + 20 * i]
            after = cur[1 + 20 * i : 21 + 20 * i]
            if not before[0x13] & 1:
                continue
            s = bytearray(before)
            p = before[8] | before[9] << 8
            token = rom.sub[p] if before[0x0D] == 1 else None
            G.step(s, rom, env)
            if bytes(s) == after:
                ok += 1
                continue
            s2 = bytearray(before)
            G.step(s2, rom, env_old)
            s2[0x11:0x13] = after[0x11:0x13]  # rewritten by the formation update
            if bytes(s2) == after:
                ok += 1
                late += 1
                continue
            bad += 1
            diff = [k for k in range(20) if s[k] != after[k]]
            key = G.NAMES.get(token, "step" if token is not None else "mid-step")
            key += " " + ",".join(f"{k:02x}" for k in diff)
            if not after[0x13] & 1 and s[0x13] & 1:
                key = "slot freed by the game (shot, wave reset)"
            elif p in G.CAPTURE_HOVER or (after[8] | after[9] << 8) in G.CAPTURE_HOVER:
                key = "capture boss hovering: turn and timer driven by the main CPU"
            elif set(diff) <= {0x11, 0x12}:
                key = "home offset moved with the formation (set by the main CPU)"
            elif set(diff) <= {0x0E, 0x0F}:
                key += ": bomb timer only"
            why[key] += 1
            if len(examples) < 14 and "freed" not in key and "formation" not in key and key not in seen_keys:
                seen_keys.add(key)
                examples.append((t, i, key, diff, before.hex(), bytes(s).hex(), after.hex()))
    print(f"{ok + bad} slot-steps compared: {ok} identical, {bad} different ({bad / (ok + bad):.3%})")
    print(f"  ({late} of the identical ones needed the previous frame's inputs)")
    for k, n in why.most_common():
        print(f"  {n:6d}  {k}")
    for e in examples:
        print(e)


if __name__ == "__main__":
    main()
