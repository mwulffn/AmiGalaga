#!/bin/sh
# Check the sound driver against the arcade model: a test build runs a script
# of sound requests in FS-UAE and logs what it sends to Paula; the same script
# is replayed through sound/native.py and the two are compared.
set -e
cd "$(dirname "$0")/.."
ROM=${ROM:-../original/galaga.zip}
KICK=${KICK:-$HOME/Documents/FS-UAE/Kickstarts/kick34005.A500}
hd=build/hd
ticks=$(python3 tools/sndtest.py ticks)
make -s build/galaga DEFS="-DTEST_FRAMES=$((ticks * 50 / 121 + 60)) -DSOUND_TEST=$ticks" >/dev/null
rm -rf $hd && mkdir -p $hd/S
cp build/galaga $hd/ && printf 'galaga\n' > $hd/S/startup-sequence
fs-uae --amiga_model=A500 --kickstart_file="$KICK" --slow_memory=0 \
    --hard_drive_0="$PWD/$hd" --floppy_drive_volume=0 --automatic_input_grab=0 \
    >build/fs-uae.log 2>&1 &
pid=$!
t=0
while [ ! -s $hd/results ] || [ "$(wc -c <$hd/results)" -lt $((ticks * 12)) ]; do
    sleep 1; t=$((t + 1))
    [ $t -lt 150 ] || { kill $pid; echo "timeout: the program did not exit and write its report"; exit 1; }
done
kill $pid; wait $pid 2>/dev/null || true
python3 tools/sndtest.py check "$ROM" $hd/results
make -s build/galaga >/dev/null   # leave the normal build in place
