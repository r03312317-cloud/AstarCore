#!/bin/sh
# Host-only ABI ownership fixture; not a kernel-driver or scanout test.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
cc -shared -fPIC -Wall -Wextra -o "$TEMP/fb.so" "$ROOT/gui/fake_fb_test.c"
mkdir -p "$ROOT/reports/gui_test"
for BANK in 0 1; do
 truncate -s 0 "$TEMP/fb"; truncate -s 921600 "$TEMP/fb"
 if [ "$BANK" = 1 ]; then export FAKE_FB_BANK1=1; else unset FAKE_FB_BANK1; fi
 LD_PRELOAD="$TEMP/fb.so" "$ROOT/gui/build/rv32-gui" --fb "$TEMP/fb" --fifo "$TEMP/fifo" --frames 500 > "$ROOT/reports/gui_test/fbdev_bank${BANK}.log" 2>&1 &
 CHILD=$!
 COUNT=0
 while [ ! -p "$TEMP/fifo" ]; do
  kill -0 "$CHILD"; COUNT=$((COUNT+1)); [ "$COUNT" -lt 100 ]; sleep .01
 done
 printf 'status\n' > "$TEMP/fifo"
 wait "$CHILD"
 test "$(grep -c FAKE_FB_PAN_PASS "$ROOT/reports/gui_test/fbdev_bank${BANK}.log")" -ge 3
 echo "PASS: inactive-bank ownership, initial bank $BANK (host ABI mock only)"
done
