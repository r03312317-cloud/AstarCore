#!/usr/bin/env bash
# Host simulation only; never flashes a board. No automatic simulator rebuild.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-}; NAME=${2:-}; LIMIT=${3:-2000000000}
if [[ "$MODE" != start && "$MODE" != resume ]] || [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
 echo 'usage: run_checkpointed_video.sh start|resume RUN_NAME [absolute_max_cycles]' >&2; exit 2
fi
cd "$ROOT"
MODEL=${RV32_VIDEO_MODEL:-$ROOT/build/savablevideo_v4/Vrv32_linux_video_top}
BUNDLE=${RV32_BOOT_BUNDLE:-$ROOT/firmware/boot-video-v4}
STATE=${RV32_STATE_ROOT:-$ROOT/../rv32_runtime_state}/$NAME
[[ -x "$MODEL" ]] || { echo 'Build a separate --savable model first; see README.' >&2; exit 2; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || exit 2
if [[ "$MODE" == start && -e "$STATE" ]]; then echo 'Refusing to overwrite an existing run; use resume or a new RUN_NAME.' >&2; exit 2; fi
if [[ "$MODE" == resume && ! -f "$STATE/model.ckpt" ]]; then echo 'No complete checkpoint to resume.' >&2; exit 2; fi
mkdir -p "$STATE"
SEGMENT="$STATE/$(date -u +%Y%m%dT%H%M%SZ)_$MODE"
mkdir "$SEGMENT"
export RV32_CHECKPOINT="$STATE/model.ckpt"
export RV32_CHECKPOINT_INTERVAL=${RV32_CHECKPOINT_INTERVAL:-10000000}
export RV32_VIDEO_OUTPUT="$SEGMENT/captures"
export RV32_UART_SCRIPT=${RV32_UART_SCRIPT:-$ROOT/sim/linux_echo_paced_commands.tsv}
# PCs are for the frozen Image b45784c8... only, not generic Linux addresses.
EXPECTED=b45784c8b683c36d71146dee873c950e39dc926b767229e312897bee19eaed2c
ACTUAL=$(sha256sum "$BUNDLE/Image" | cut -d' ' -f1)
if [[ -z "${RV32_PROFILE_PC+x}" ]]; then
 [[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'Different kernel: supply matching RV32_PROFILE_PC explicitly (empty disables).' >&2; exit 2; }
 export RV32_PROFILE_PC='shmem_inode:c006c124,random_u32:c019f97c,cpio_name:c01ecb80,cpio_copy:c01ed134,unpack:c01ec768,populate:c01ed204,uart_probe:c019d994,fb_probe:c0170e48,fb_pan:c0170c60,load_elf:c00df9e4,run_init:c01df228'
fi
if [[ "$MODE" == resume ]]; then export RV32_RESUME="$STATE/model.ckpt"; else unset RV32_RESUME; fi
unset RV32_STOP_AFTER_CHECKPOINT
printf '%s\n' "$$" > "$SEGMENT/launcher.pid"
sha256sum "$MODEL" "$BUNDLE/fw_jump_quiet.bin" "$BUNDLE/Image" "$BUNDLE/rootfs.cpio" "$RV32_UART_SCRIPT" > "$SEGMENT/inputs.sha256"
printf '%s\n' "$MODE" "absolute_max_cycles=$LIMIT" "profile=$RV32_PROFILE_PC" "checkpoint=$RV32_CHECKPOINT" > "$SEGMENT/run.txt"
printf '%s\n' "$SEGMENT" | tee "$STATE/latest_segment.txt"
# For precise progress use PROFILE/IRQ counters and actual UART, not maxcycle exit.
exec "$MODEL" "$BUNDLE/fw_jump_quiet.bin" "$LIMIT" "$BUNDLE/Image@80400000" "$BUNDLE/rootfs.cpio@82400000" > "$SEGMENT/uart.log" 2> "$SEGMENT/trace.log"
