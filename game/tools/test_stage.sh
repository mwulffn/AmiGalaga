#!/bin/sh
# Check the game (flow, launcher, formation, dives, flights, shots, bombs, scoring) against
# the models: a test build plays itself and logs what happens in FS-UAE, and
# tools/stagetest.py replays the same frames. Run for the exact build and the PAL build,
# from stage 1 (through stage changes and a game over), from stage 3, the first
# challenging stage (through its results), and from stage 8 (fly-through enemies, and one
# that transforms). Built without capture, which the model does not have.
#   tools/test_stage.sh              or   STAGES="8:6000" tools/test_stage.sh   (first stage:frames ...)
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-../original/galaga.zip}
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd
run() {  # first stage, frames
    for exact in 1 0; do
        make -s build/galaga DEFS="-DSTAGE_TEST=1 -DCAPTURE=0 -DTEST_FRAMES=$2 -DEXACT_TIMING=$exact -DFIRST_STAGE=$1" >/dev/null
        rm -rf $hd && mkdir -p $hd/S
        cp build/galaga $hd/ && printf 'galaga\n' > $hd/S/startup-sequence
        fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
            --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
            >build/fs-uae.log 2>&1 &
        pid=$!
        t=0
        while [ ! -s $hd/results ]; do
            sleep 1; t=$((t + 1))
            [ $t -lt $(($2 / 40 + 60)) ] || { kill $pid; echo "timeout: the program did not exit and write its report"; exit 1; }
        done
        sleep 1
        kill $pid; wait $pid 2>/dev/null || true
        python3 tools/stagetest.py check "$ROM" $hd/results $((6 - exact)) $2 $1
    done
}
for spec in ${STAGES:-1:6000 3:5500 8:6000}; do
    run "${spec%:*}" "${spec#*:}"
done
make -s build/galaga >/dev/null   # leave the normal build in place
