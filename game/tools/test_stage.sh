#!/bin/sh
# Check the stage (launcher, formation, dives, flights, landings) against the models:
# a test build logs every launch and landing over the first stages in FS-UAE,
# and tools/stagetest.py replays the same frames. Run for the exact build
# and the PAL build.
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-../original/galaga.zip}
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
frames=${1:-3600}
hd=build/hd
for exact in 1 0; do
    make -s build/galaga DEFS="-DSTAGE_TEST=1 -DTEST_FRAMES=$frames -DEXACT_TIMING=$exact" >/dev/null
    rm -rf $hd && mkdir -p $hd/S
    cp build/galaga $hd/ && printf 'galaga\n' > $hd/S/startup-sequence
    fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
        --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
        >build/fs-uae.log 2>&1 &
    pid=$!
    t=0
    while [ ! -s $hd/results ]; do
        sleep 1; t=$((t + 1))
        [ $t -lt $((frames / 40 + 60)) ] || { kill $pid; echo "timeout: the program did not exit and write its report"; exit 1; }
    done
    sleep 1
    kill $pid; wait $pid 2>/dev/null || true
    python3 tools/stagetest.py check "$ROM" $hd/results $((6 - exact)) $frames
done
make -s build/galaga >/dev/null   # leave the normal build in place
