#!/bin/sh
# Run MEASURE builds in FS-UAE (A500, KS 1.3) and report raster time.
#   tools/measure.sh frames "nfly [defs]" ...     e.g. 10 "10 -DQUEUE" "20 -DQUEUE -DNONASTY"
#   FAST=1024 tools/measure.sh ...                the same on an A500 with 1 MB of fast RAM
#   tools/measure.sh matrix [frames]              wait loop against queue, on both machines
set -e
cd "$(dirname "$0")/.."
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd
screen=$((42 * 4 * 288 + 16))

run() { # nfly, defs, fast RAM in KB, label
    make -s build/exp7 DEFS="$2" NFLY="$1" >/dev/null
    rm -rf $hd && mkdir -p $hd/S
    cp build/exp7 $hd/ && printf 'exp7\n' > $hd/S/startup-sequence
    fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 --fast_memory="$3" \
        --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
        >build/fs-uae.log 2>&1 &
    pid=$!
    t=0
    while [ ! -s $hd/results ] || [ "$(wc -c <$hd/results)" -lt $screen ]; do
        sleep 1; t=$((t + 1))
        [ $t -lt 120 ] || { kill $pid; echo "timeout ($4)"; return 0; }
    done
    kill $pid; wait $pid 2>/dev/null || true
    python3 ../experiment-6/tools/report6.py $hd/results "$4" | head -1
}

if [ "$1" = matrix ]; then
    frames=${2:-300}
    for fast in 0 1024; do
        [ $fast = 0 ] && machine="stock A500" || machine="A500 + fast RAM"
        for n in 10 20; do
            for pri in "" " -DNONASTY"; do
                [ -z "$pri" ] && p="priority on " || p="priority off"
                run $n "-DMEASURE=$frames$pri" $fast "$machine, $n flyers, $p, wait loop"
                run $n "-DMEASURE=$frames$pri -DQUEUE" $fast "$machine, $n flyers, $p, queue"
            done
        done
    done
else
    frames=${1:?usage: $0 frames \"nfly [defs]\" ... | matrix [frames]}
    shift
    for r in "$@"; do
        n=${r%% *}
        defs=${r#"$n"}
        run "$n" "-DMEASURE=$frames $defs" "${FAST:-0}" "$n flyers$defs${FAST:+, fast RAM}"
    done
fi
make -s build/exp7 >/dev/null   # leave the normal build in place
