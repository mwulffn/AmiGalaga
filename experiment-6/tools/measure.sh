#!/bin/sh
# Run MEASURE builds in FS-UAE (stock A500, KS 1.3) and report raster time
# and the cost of a sound tick.
#   tools/measure.sh frames "nfly [defs]" ...   e.g. 10 20 "0 -DNORENDER"
#   tools/measure.sh sndtest                    check the driver against the arcade model
set -e
cd "$(dirname "$0")/.."
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd

run() { # nfly, defs, expected size of results
    make -s build/exp6 DEFS="$2" NFLY="$1" >/dev/null
    rm -rf $hd && mkdir -p $hd/S
    cp build/exp6 $hd/ && printf 'exp6\n' > $hd/S/startup-sequence
    fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
        --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
        >build/fs-uae.log 2>&1 &
    pid=$!
    t=0
    while [ ! -s $hd/results ] || [ "$(wc -c <$hd/results)" -lt "$3" ]; do
        sleep 1; t=$((t + 1))
        [ $t -lt 150 ] || { kill $pid; echo "timeout ($1 $2)"; exit 1; }
    done
    kill $pid; wait $pid 2>/dev/null || true
}

screen=$((42 * 4 * 288 + 16))
if [ "$1" = sndtest ]; then
    ticks=$(python3 tools/sndtest.py ticks)
    run 10 "-DMEASURE=$((ticks * 50 / 121 + 60)) -DSNDTEST=$ticks" $((screen + ticks * 12))
    python3 tools/report6.py $hd/results "test script, formation + 10 flyers"
    python3 tools/sndtest.py check ../original/galaga.zip $hd/results
else
    frames=${1:?usage: $0 frames \"nfly [defs]\" ... | sndtest}
    shift
    for r in "$@"; do
        n=${r%% *}
        defs=${r#"$n"}
        run "$n" "-DMEASURE=$frames $defs" $screen
        python3 tools/report6.py $hd/results "formation + $n flyers$defs"
    done
fi
make -s build/exp6 >/dev/null   # leave the normal build in place
