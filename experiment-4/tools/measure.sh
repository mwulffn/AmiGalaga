#!/bin/sh
# Run MEASURE builds in FS-UAE (stock A500, KS 1.3) and report raster time.
#   tools/measure.sh frames "nfly [defs]" ...   e.g. 10 20 "10 -DNOCOMPOSE"
set -e
cd "$(dirname "$0")/.."
frames=${1:?usage: $0 frames \"nfly [defs]\" ...}
shift
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd
i=0
for run in "$@"; do
    i=$((i + 1))
    n=${run%% *}
    defs=${run#"$n"}
    make -s build/exp4 DEFS="-DMEASURE=$frames $defs" NFLY="$n" >/dev/null
    rm -rf $hd && mkdir -p $hd/S
    cp build/exp4 $hd/ && printf 'exp4\n' > $hd/S/startup-sequence
    fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
        --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
        >build/fs-uae.log 2>&1 &
    pid=$!
    t=0
    while [ ! -s $hd/results ] || [ "$(wc -c <$hd/results)" -lt 48392 ]; do
        sleep 1; t=$((t + 1))
        [ $t -lt 90 ] || { kill $pid; echo "timeout ($run)"; exit 1; }
    done
    kill $pid; wait $pid 2>/dev/null || true
    uv run -q --with pillow python3 ../experiment-1/tools/report.py $hd/results "formation + $n flyers$defs" build/frame_$i.png 42
done
make -s build/exp4 >/dev/null   # leave the normal build in place
