#!/bin/sh
# Check the flight stepper against the model the arcade was checked against:
# a test build flies every test case in FS-UAE and reports where each went;
# motion/pal_scale.py flies the same cases and the two are compared. Run for
# the exact build (identical to the arcade) and the PAL build.
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-../original/galaga.zip}
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd
size=$((8 + 16 * $(python3 tools/flighttest.py count "$ROM")))
for exact in 1 0; do
    make -s build/galaga DEFS="-DFLIGHT_TEST=1 -DEXACT_TIMING=$exact" >/dev/null
    rm -rf $hd && mkdir -p $hd/S
    cp build/galaga $hd/ && printf 'galaga\n' > $hd/S/startup-sequence
    fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
        --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
        >build/fs-uae.log 2>&1 &
    pid=$!
    t=0
    while [ ! -s $hd/results ] || [ "$(wc -c <$hd/results)" -lt $size ]; do
        sleep 1; t=$((t + 1))
        [ $t -lt 240 ] || { kill $pid; echo "timeout: the program did not exit and write its report"; exit 1; }
    done
    kill $pid; wait $pid 2>/dev/null || true
    python3 tools/flighttest.py check "$ROM" $hd/results $((6 - exact))
done
make -s build/galaga >/dev/null   # leave the normal build in place
