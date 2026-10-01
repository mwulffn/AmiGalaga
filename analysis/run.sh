#!/bin/zsh
# usage: run.sh mode out frames snap_every [die_last] ; env GPOKE=1 for infinite lives
rm -rf cfg nvram snap_$1 $2
GMODE=$1 GOUT=$2 GFRAMES=$3 GSNAP=$4 GDIE=${5:-0} mame galaga -rompath /Users/wulff/Projects/Galaga-port/original -video none -sound none -nothrottle -skip_gameinfo -autoboot_script trace.lua -autoboot_delay 0 -snapshot_directory snap_$1 -cfg_directory cfg -nvram_directory nvram -snapname "%i" 2>&1 > log_$1.txt 2>&1; tail -3 log_$1.txt
