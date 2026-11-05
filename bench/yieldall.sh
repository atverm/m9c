#!/bin/sh
# yieldall.sh builds yieldprobe.sh's six variants of the five programs
# of docs/task-plan.md, section "Yield checks, priced", and times them
# with yieldtime.sh.
#
#   sh bench/yieldall.sh REPO OUTDIR LOGDIR
#
# $M9C names the compiler (yieldprobe.sh's default is REPO/out/m9c).
set -eu
REPO=$1; OUT=$2; LOG=$3
B=$REPO/bench
sh "$B/yieldprobe.sh" "$REPO" "$OUT" fannkuch "$B/Fannkuch.m9"
sh "$B/yieldprobe.sh" "$REPO" "$OUT" mandel "$B/Mandel.m9"
sh "$B/yieldprobe.sh" "$REPO" "$OUT" bintrees "$B/BinTrees.m9"
sh "$B/yieldprobe.sh" "$REPO" "$OUT" boids "$B/Boids.m9"
sh "$B/yieldprobe-m9c.sh" "$REPO" "$OUT"
sh "$B/yieldtime.sh" "$OUT" "$LOG"
