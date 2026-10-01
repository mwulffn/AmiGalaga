#!/bin/sh
# Run MEASURE builds in FS-UAE (stock A500, KS 1.3) and report raster time.
#   tools/measure.sh [frames] [bob counts...] ; env DEFS=-DNONASTY to drop blitter priority
set -e
cd "$(dirname "$0")/.."
frames=${1:-500}
[ $# -gt 0 ] && shift
[ $# -gt 0 ] || set -- 50
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd
for n in "$@"; do
    make -s build/exp1 NBOBS="$n" DEFS="-DMEASURE=$frames $DEFS" >/dev/null
    rm -rf $hd && mkdir -p $hd/S
    cp build/exp1 $hd/ && printf 'exp1\n' > $hd/S/startup-sequence
    fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
        --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
        >build/fs-uae.log 2>&1 &
    pid=$!
    i=0
    while [ ! -s $hd/results ] || [ "$(wc -c <$hd/results)" -lt 40968 ]; do
        sleep 1; i=$((i + 1))
        [ $i -lt 90 ] || { kill $pid; echo "timeout (bobs=$n)"; exit 1; }
    done
    kill $pid; wait $pid 2>/dev/null || true
    uv run -q --with pillow python3 tools/report.py $hd/results "bobs=$n" build/frame_"$n".png
done
make -s build/exp1 >/dev/null   # leave the normal build in place
