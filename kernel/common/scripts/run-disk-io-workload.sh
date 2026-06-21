#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run a Docker-based disk I/O workload for AutoFDO profiling.

Usage:
  ../common/scripts/run-disk-io-workload.sh

Defaults:
  duration:       30 minutes
  cadence:        10 seconds I/O, 50 seconds sleep
  target dir:     ./out/disk-io-workload
  workload file:  4 GiB sparse file
  burst size:     256 MiB sequential read/write + small random I/O
  container:      archlinux@ARCH_IMAGE_DIGEST from ./variant.env

Optional environment overrides:
  TARGET_DIR=/mnt/nvme/autofdo-io
  DURATION_MINUTES=45
  FILE_SIZE_GIB=16
  IO_ACTIVE_SECONDS=5
  IO_SLEEP_SECONDS=55
  KEEP_DATA=1
USAGE
}

workload_root="${WORKLOAD_ROOT:-$(pwd -P)}"
variant_env="${VARIANT_ENV:-$workload_root/variant.env}"

DURATION_MINUTES="${DURATION_MINUTES:-30}"
DURATION_SECONDS="${DURATION_SECONDS:-}"
TARGET_DIR="${TARGET_DIR:-$workload_root/out/disk-io-workload}"
FILE_SIZE_GIB="${FILE_SIZE_GIB:-4}"
FILE_SIZE_MIB="${FILE_SIZE_MIB:-}"
IMAGE="${IMAGE:-}"
KEEP_DATA="${KEEP_DATA:-0}"
IO_ACTIVE_SECONDS="${IO_ACTIVE_SECONDS:-10}"
IO_SLEEP_SECONDS="${IO_SLEEP_SECONDS:-50}"
SEQ_CHUNK_MIB="${SEQ_CHUNK_MIB:-256}"
SEQ_BLOCK_MIB="${SEQ_BLOCK_MIB:-8}"
RANDOM_BLOCK_KIB="${RANDOM_BLOCK_KIB:-4}"
RANDOM_OPS_PER_BURST="${RANDOM_OPS_PER_BURST:-256}"

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_positive_int() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "$name must be a positive integer, got: $value" >&2
    exit 2
  fi
}

require_positive_int DURATION_MINUTES "$DURATION_MINUTES"
if [[ -n "$DURATION_SECONDS" ]]; then
  require_positive_int DURATION_SECONDS "$DURATION_SECONDS"
fi
require_positive_int FILE_SIZE_GIB "$FILE_SIZE_GIB"
if [[ -n "$FILE_SIZE_MIB" ]]; then
  require_positive_int FILE_SIZE_MIB "$FILE_SIZE_MIB"
fi
require_positive_int SEQ_BLOCK_MIB "$SEQ_BLOCK_MIB"
require_positive_int RANDOM_BLOCK_KIB "$RANDOM_BLOCK_KIB"
require_positive_int IO_ACTIVE_SECONDS "$IO_ACTIVE_SECONDS"
require_positive_int IO_SLEEP_SECONDS "$IO_SLEEP_SECONDS"
require_positive_int SEQ_CHUNK_MIB "$SEQ_CHUNK_MIB"
require_positive_int RANDOM_OPS_PER_BURST "$RANDOM_OPS_PER_BURST"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for this workload" >&2
  exit 127
fi

if [[ -z "$IMAGE" ]]; then
  ARCH_IMAGE_DIGEST="${ARCH_IMAGE_DIGEST:-}"
  if [[ -z "$ARCH_IMAGE_DIGEST" && -f "$variant_env" ]]; then
    ARCH_IMAGE_DIGEST="$(sed -n 's/^ARCH_IMAGE_DIGEST=//p' "$variant_env" | head -n1)"
  fi

  if [[ -z "$ARCH_IMAGE_DIGEST" ]]; then
    echo "ARCH_IMAGE_DIGEST is required. Set it in $variant_env or export it." >&2
    exit 2
  fi

  IMAGE="archlinux@$ARCH_IMAGE_DIGEST"
fi

mkdir -p "$TARGET_DIR"
target_dir_abs="$(cd "$TARGET_DIR" && pwd -P)"
container_script="$(mktemp)"
trap 'rm -f "$container_script"' EXIT

cat >"$container_script" <<'CONTAINER_SCRIPT'
#!/bin/sh
set -eu

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

run_dd() {
  if dd "$@" 2>/dev/null; then
    return 0
  fi

  return 1
}

seq_window() {
  max_start=$((FILE_SIZE_MIB - SEQ_CHUNK_MIB))
  if [ "$max_start" -le 0 ]; then
    echo 0
    return
  fi

  echo $(((BURST - 1) * SEQ_CHUNK_MIB % max_start))
}

seq_write() {
  start_mib="$(seq_window)"
  log "sequential write: ${SEQ_CHUNK_MIB}MiB at ${start_mib}MiB"
  if run_dd if=/dev/zero of="$WORKLOAD_FILE" bs="${SEQ_BLOCK_MIB}M" count="$SEQ_COUNT" seek="$((start_mib / SEQ_BLOCK_MIB))" conv=notrunc oflag=direct; then
    return 0
  fi

  run_dd if=/dev/zero of="$WORKLOAD_FILE" bs="${SEQ_BLOCK_MIB}M" count="$SEQ_COUNT" seek="$((start_mib / SEQ_BLOCK_MIB))" conv=notrunc
  sync
}

seq_read() {
  start_mib="$(seq_window)"
  log "sequential read: ${SEQ_CHUNK_MIB}MiB at ${start_mib}MiB"
  if run_dd if="$WORKLOAD_FILE" of=/dev/null bs="${SEQ_BLOCK_MIB}M" count="$SEQ_COUNT" skip="$((start_mib / SEQ_BLOCK_MIB))" iflag=direct; then
    return 0
  fi

  run_dd if="$WORKLOAD_FILE" of=/dev/null bs="${SEQ_BLOCK_MIB}M" count="$SEQ_COUNT" skip="$((start_mib / SEQ_BLOCK_MIB))"
}

random_block() {
  od -An -N4 -tu4 /dev/urandom | awk -v max="$RANDOM_BLOCKS" '{ print $1 % max }'
}

random_reads() {
  log "random reads: ${RANDOM_OPS_PER_BURST} x ${RANDOM_BLOCK_KIB}KiB"
  i=0
  while [ "$i" -lt "$RANDOM_OPS_PER_BURST" ]; do
    [ "$(date +%s)" -ge "$BURST_DEADLINE" ] && return 0
    block="$(random_block)"
    if ! run_dd if="$WORKLOAD_FILE" of=/dev/null bs="${RANDOM_BLOCK_KIB}K" count=1 skip="$block" iflag=direct; then
      run_dd if="$WORKLOAD_FILE" of=/dev/null bs="${RANDOM_BLOCK_KIB}K" count=1 skip="$block"
    fi
    i=$((i + 1))
  done
}

random_writes() {
  log "random overwrites: ${RANDOM_OPS_PER_BURST} x ${RANDOM_BLOCK_KIB}KiB"
  i=0
  while [ "$i" -lt "$RANDOM_OPS_PER_BURST" ]; do
    [ "$(date +%s)" -ge "$BURST_DEADLINE" ] && return 0
    block="$(random_block)"
    if ! run_dd if=/dev/zero of="$WORKLOAD_FILE" bs="${RANDOM_BLOCK_KIB}K" count=1 seek="$block" conv=notrunc oflag=direct; then
      run_dd if=/dev/zero of="$WORKLOAD_FILE" bs="${RANDOM_BLOCK_KIB}K" count=1 seek="$block" conv=notrunc
    fi
    i=$((i + 1))
  done
  sync
}

cleanup() {
  if [ "${KEEP_DATA:-0}" != "1" ]; then
    rm -f "$WORKLOAD_FILE"
  fi
}

: "${DURATION_SECONDS:?missing DURATION_SECONDS}"
: "${FILE_SIZE_MIB:?missing FILE_SIZE_MIB}"
: "${IO_ACTIVE_SECONDS:?missing IO_ACTIVE_SECONDS}"
: "${IO_SLEEP_SECONDS:?missing IO_SLEEP_SECONDS}"
: "${SEQ_CHUNK_MIB:?missing SEQ_CHUNK_MIB}"
: "${SEQ_BLOCK_MIB:?missing SEQ_BLOCK_MIB}"
: "${RANDOM_BLOCK_KIB:?missing RANDOM_BLOCK_KIB}"
: "${RANDOM_OPS_PER_BURST:?missing RANDOM_OPS_PER_BURST}"
: "${KEEP_DATA:?missing KEEP_DATA}"

WORKLOAD_FILE=/workload/autofdo-disk-io.bin
SEQ_COUNT=$((SEQ_CHUNK_MIB / SEQ_BLOCK_MIB))
RANDOM_BLOCKS=$((FILE_SIZE_MIB * 1024 / RANDOM_BLOCK_KIB))
DEADLINE=$(($(date +%s) + DURATION_SECONDS))

if [ "$SEQ_CHUNK_MIB" -gt "$FILE_SIZE_MIB" ]; then
  echo "SEQ_CHUNK_MIB must be less than or equal to FILE_SIZE_MIB" >&2
  exit 2
fi

if [ $((SEQ_CHUNK_MIB % SEQ_BLOCK_MIB)) -ne 0 ]; then
  echo "SEQ_CHUNK_MIB must be divisible by SEQ_BLOCK_MIB" >&2
  exit 2
fi

if [ "$RANDOM_BLOCKS" -lt 1 ]; then
  echo "file size must be at least one random block" >&2
  exit 2
fi

trap cleanup EXIT INT TERM

log "starting disk I/O workload until $(date -d "@$DEADLINE" '+%H:%M:%S' 2>/dev/null || date)"
log "target file: $WORKLOAD_FILE"
truncate -s "${FILE_SIZE_MIB}M" "$WORKLOAD_FILE"

BURST=1
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  now="$(date +%s)"
  BURST_DEADLINE=$((now + IO_ACTIVE_SECONDS))
  if [ "$BURST_DEADLINE" -gt "$DEADLINE" ]; then
    BURST_DEADLINE="$DEADLINE"
  fi

  log "burst $BURST: I/O until $(date -d "@$BURST_DEADLINE" '+%H:%M:%S' 2>/dev/null || date)"
  seq_write
  if [ "$(date +%s)" -lt "$BURST_DEADLINE" ]; then
    seq_read
  fi
  if [ "$(date +%s)" -lt "$BURST_DEADLINE" ]; then
    random_reads
  fi
  if [ "$(date +%s)" -lt "$BURST_DEADLINE" ]; then
    random_writes
  fi

  now="$(date +%s)"
  [ "$now" -ge "$DEADLINE" ] && break
  sleep_for="$IO_SLEEP_SECONDS"
  if [ $((now + sleep_for)) -gt "$DEADLINE" ]; then
    sleep_for=$((DEADLINE - now))
  fi
  if [ "$sleep_for" -gt 0 ]; then
    log "sleeping ${sleep_for}s"
    sleep "$sleep_for"
  fi
  BURST=$((BURST + 1))
done

log "finished disk I/O workload"
CONTAINER_SCRIPT

chmod 0755 "$container_script"

duration_seconds="${DURATION_SECONDS:-$((DURATION_MINUTES * 60))}"
file_size_mib="${FILE_SIZE_MIB:-$((FILE_SIZE_GIB * 1024))}"
container_name="autofdo-disk-io-$$"

cat <<EOF
Starting AutoFDO disk I/O workload
  duration:       ${duration_seconds} second(s)
  target dir:     ${target_dir_abs}
  file size:      ${file_size_mib}MiB
  cadence:        ${IO_ACTIVE_SECONDS}s I/O, ${IO_SLEEP_SECONDS}s sleep
  seq burst:      ${SEQ_CHUNK_MIB}MiB
  random ops:     ${RANDOM_OPS_PER_BURST} per burst
  docker image:   ${IMAGE}
  keep data:      ${KEEP_DATA}
EOF

docker run --rm \
  --name "$container_name" \
  -e DURATION_SECONDS="$duration_seconds" \
  -e FILE_SIZE_MIB="$file_size_mib" \
  -e IO_ACTIVE_SECONDS="$IO_ACTIVE_SECONDS" \
  -e IO_SLEEP_SECONDS="$IO_SLEEP_SECONDS" \
  -e SEQ_CHUNK_MIB="$SEQ_CHUNK_MIB" \
  -e SEQ_BLOCK_MIB="$SEQ_BLOCK_MIB" \
  -e RANDOM_BLOCK_KIB="$RANDOM_BLOCK_KIB" \
  -e RANDOM_OPS_PER_BURST="$RANDOM_OPS_PER_BURST" \
  -e KEEP_DATA="$KEEP_DATA" \
  -v "$target_dir_abs:/workload" \
  -v "$container_script:/run-workload.sh:ro" \
  "$IMAGE" \
  /bin/sh /run-workload.sh
