#!/bin/sh
# Build with TEST_FRAMES, run in FS-UAE (stock A500, Kickstart 1.3) until the
# program exits and writes "results", then print the report.
#   tools/test.sh [frames] [extra -D options]
set -e
cd "$(dirname "$0")/.."
frames=${1:-200}
[ $# -gt 0 ] && shift
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd
make -s build/galaga DEFS="-DTEST_FRAMES=$frames $*" >/dev/null
rm -rf $hd && mkdir -p $hd/S
cp build/galaga $hd/ && printf 'galaga\n' > $hd/S/startup-sequence
fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
    --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
    >build/fs-uae.log 2>&1 &
pid=$!
t=0
while [ ! -s $hd/results ]; do
    sleep 1; t=$((t + 1))
    [ $t -lt 90 ] || { kill $pid; echo "timeout: the program did not exit and write its report"; exit 1; }
done
sleep 1
kill $pid; wait $pid 2>/dev/null || true
python3 tools/report.py $hd/results
make -s build/galaga >/dev/null   # leave the normal build in place
